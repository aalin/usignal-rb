require_relative "utils"

module USignal
  module Signals
    def self.inspect_obj(obj)
      case obj
      in Proc
        obj.source_location => [file, line]
        "λ(#{file}:#{line})"
      else
        obj.inspect
      end
    end

    def self.equal?(a, b)
      case [a, b]
      in Base, _
        equal?(a.peek, b)
      in _, Base
        equal?(a, b.peek)
      in _, Proxy
        equal?(b, a)
      # in Proc, Proc
      #   a.source == b.source && a.source_location == b.source_location
      else
        a == b
      end
    end

    class Base
      def initialize(value, **)
        @value = value
        @proxy = nil
      end

      def to_rx = proxy

      def ==(other)
        super || Signals.equal?(@value, other)
      end

      def to_i = value.to_i
      def to_f = value.to_f
      def to_s = value.to_s
      def to_str = value.to_str

      def coerce(number)
        case number
        in Integer
          [to_i, number]
        in Float
          [to_f, number]
        else
          [to_f, number]
        end
      end

      def peek
        if self.class === @value
          @value.peek
        else
          @value
        end
      end

      def dispose = nil
      def value = peek

      def proxy
        @proxy ||= Proxy.new(self)
      end

      def inspect
        "#<#{self.class.name}:#{object_id.to_s(16)} value=#{Signals.inspect_obj(@value)}>"
      end
    end

    class Computed < Base
      CURRENT = :"USignal::Computed::CURRENT"

      def self.with(computed, &block) =
        Utils.with_thread_local(CURRENT, computed, &block)
      def self.current =
        Utils.get_thread_local(CURRENT)
      def use(&block) =
        Computed.with(self, &block)

      attr_reader :related
      attr_reader :signal

      def should_update? = @should_update
      def should_update! = @should_update = true
      def effect? = false

      def initialize(value = nil, **options, &block)
        super(block)
        @signal = Reactive.new(value, **options)
        @related = Set.new
        @should_update = true
      end

      def inspect
        color = @should_update ? "\e[33m" : "\e[32m"
        reset = "\e[0m"

        "#{color}∑#{object_id.to_s(16)}#{reset}⟦#{Signals.inspect_obj(@signal)} #{Signals.inspect_obj(peek)}⟧"
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
            @signal.value = super.call(@signal.peek)
          ensure
            @should_update = false
          end
        end

        @signal.value
      end
    end

    class FX < Computed
      NOOP = ->(*){}

      def initialize(value = nil, **options, &block)
        super(value, **options, &block)
      end

      def effect? = true

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
      CURRENT = :"USignal::Effect::CURRENT"

      def self.with(computed, &block) =
        Utils.with_thread_local(CURRENT, computed, &block)
      def self.current =
        Utils.get_thread_local(CURRENT)
      def use(&block) =
        Effect.with(self, &block)

      def self.create(value = nil, **options, &block)
        if outer = current
          index = outer.index
          effects = outer.effects
          is_new = index == effects.length

          if is_new || effects[index].peek != block
            effects[index]&.stop
            effects[index] = new(value, **options, &block).run
          end

          outer.index += 1
          effects[index]
        else
          new(value, **options, &block).run
        end
      end

      def self.on_dispose(&block)
        if outer = current
          outer.disposes.push(Dispose.new(&block))
        else
          raise "There is no active effect currently"
        end
      end

      attr_reader :disposes

      attr_reader :effects
      attr_accessor :index

      def initialize(value, **options, &block)
        super(value, **options, &block)
        @index = 0
        @effects = []
        @disposes = []
      end

      def inspect
        color = @should_update ? "\e[33m" : "\e[32m"
        reset = "\e[0m"

        "#{color}#{object_id.to_s(16)}𝑓#{reset}⟦#{Signals.inspect_obj(@signal)} #{Signals.inspect_obj(@value)}⟧"
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

      def dispose
        super
        Batch.dispose(self)
      end
    end

    class Reactive < Base
      def self.from(initial, **options)
        if initial in self
          initial
        else
          new(initial, **options)
        end
      end

      attr_reader :computeds

      def initialize(value = nil, **)
        super(value, **)
        @computeds = Set.new
      end

      def inspect
        "⚛#{object_id.to_s(16)}⟪#{@value.inspect}⟫"
      end

      def value
        if U.tracking?
          if computed_signal = Computed.current
            @computeds.add(computed_signal)
            computed_signal.related.add(self)
          end
        end

        super
      end

      def value=(new_value)
        return if @value == new_value
        @value = new_value
        return if @computeds.empty?

        Batch.enqueue(self)
      end
    end

    class Dispose < Proc
      class AlreadyCalledError < StandardError
      end

      def initialize
        super
        @called = false
      end

      def called? = @called

      def call
        called!
        U.untrack { super }
      end

      private

      def called!
        if @called
          raise AlreadyCalledError,
            "#{self.inspect} has already been called!"
        end

        @called = true
      end
    end
  end
end
