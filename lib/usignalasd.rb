# frozen_string_literal: true

require "set"
require_relative "usignal/version"

module USignal
  class Error < StandardError; end

  def self.with_thread_local(name, value, &block)
    prev, Thread.current[name] = Thread.current[name], value
    yield value
  ensure
    Thread.current[name] = prev
  end

  class Proxy < BasicObject
    def initialize(signal)
      @signal = signal
    end

    def method_missing(method, *args, &block)
      @signal.value.send(method, *args, &block)
    end
  end

  module ProxyRefinements
    refine Proxy do
      def __signal = @signal
    end
  end

  module Signals
    class Signal
      def initialize(value)
        @value = value
        @proxy = nil
      end

      def peek
        @value
      end

      def proxy
        @proxy ||= Proxy.new(self)
      end

      def dispose
      end
    end

    class Computed < Signal
      def self.with(computed, &block)
        USignal.with_thread_local(:U_Computed_current, computed, &block)
      end

      def self.current
        Thread.current[:U_Computed_current]
      end

      attr_reader :related
      attr_reader :signal

      def should_update? = @should_update
      def should_update! = @should_update = true
      def effect? = @is_effect

      def initialize(value = nil, is_effect: false, **options, &block)
        super(block)
        @signal = Reactive.new(value, **options)
        @is_effect = is_effect
        @related = Set.new
        @should_update = true
      end

      def dispose
        super

        if @signal.peek in Proc => p
          @signal.value = p.call
        end
      end

      def value
        if @should_update
          Computed.with(self) do
            @signal.value = @value.call(@signal.peek)
          ensure
            @should_update = false
          end
        end

        @signal.value
      end
    end

    class FX < Computed
      NOOP = ->() {}

      def initialize(value = nil, **options, &block)
        super(value, is_effect: true, **options, &block)
      end

      def run
        should_update!
        value
        self
      end

      def stop
        @value = NOOP
        @related.clear
        @signal.computeds.clear
      end
    end

    class Effect < FX
      def self.with(computed, &block) =
        USignal.with_thread_local(:U_Effect_current, computed, &block)
      def self.current =
        Thread.current[:U_Effect_current]

      attr_reader :effects
      attr_accessor :index

      def initialize(value, **options, &block)
        super(value, **options, &block)
        @index = 0
        @effects = []
      end

      def value
        Effect.with(self) do
          @index = 0
          dispose
          super
        end
      end

      def stop
        super
        dispose
        @effects.each(&:stop).clear
      end
    end

    class Reactive < Signal
      attr_reader :computeds

      def initialize(value = nil)
        super(value)
        @computeds = Set.new
      end

      def value
        if computed_signal = Computed.current
          @computeds.add(computed_signal)
          computed_signal.related.add(self)
        end

        @value
      end

      def value=(value)
        return if @value == value

        @value = value

        return if @computeds.empty?

        effects = []
        stack = [self]

        while signal = stack.shift
          signal.computeds.each do |computed|
            if !computed.should_update? && computed.related.include?(signal)
              computed.related.clear
              computed.should_update!
              if computed.effect?
                effects.push(computed)
                stack2 = [computed]
                while c = stack2.shift
                  c.effects.each do |effect|
                    effect.related.clear
                    effect.should_update!
                    stack2.push(effect)
                  end
                end
              else
                stack.push(computed.signal)
              end
            end
          end
        end

        effects.each do |effect|
          if USignal.batches
            USignal.batches.push(effect)
          else
            effect.value
          end
        end
      end
    end
  end

  def self.batches = Thread.current[:U_batches]
  def self.batch(&block)
    prev = batches

    with_thread_local(:U_batches, prev || []) do |batches|
      yield
    ensure
      batches.each(&:value) unless prev
    end
  end

  def self.signal(value, **options)
    Signals::Reactive.new(value, **options).proxy
  end

  using ProxyRefinements

  def self.write(obj, value)
    case obj
    when Proxy
      write(obj.__signal, value)
    when Signals::Signal
      obj.value = value
    end
  end

  def self.computed(value = nil, **options, &block)
    Signals::Computed.new(value, is_effect: false, **options, &block).proxy
  end

  def self.effect(value = nil, **options, &block)
    unique =
      if outer = Signals::Effect.current
        i = outer.index
        e = outer.effects
        is_new = i == e.length
        if is_new || e[i].peek != block
          e[i].stop unless is_new
          e[i] = Signals::Effect.new(value, **options, &block).run
        end
        outer.index += 1
        e[i]
      else
        Signals::Effect.new(value, **options, &block).run
      end

    ->() { unique.stop }
  end
end

a = USignal.signal(0)
b = USignal.signal(0)
c = USignal.signal(0)

d = USignal.computed { a + b }
e = USignal.computed { b + c }

dispose = USignal.effect do
  puts "d: #{d}"

  USignal.effect do
    puts "e: #{e}"
  end
end

sleep 0.1
puts "xxx"
USignal.write(b, 2)
sleep 0.1
puts "xxx"
USignal.write(a, 2)
sleep 0.1
puts "xxx"
USignal.write(c, 2)
sleep 0.1
puts "batch"

USignal.batch do
  USignal.write(a, 1)
  USignal.write(b, 3)
  USignal.write(c, 5)
end

sleep 0.1
puts "xxx"
dispose.call
USignal.write(a, 3)
