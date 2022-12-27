require_relative "signals"

module USignal
  module RX
    module Refinements
      refine Object do
        def to_rx = U.signal(self).proxy
      end

      refine Hash do
        def to_rx = Map[**self]
      end

      refine Array do
        def to_rx = List[*self]
      end
    end

    module Helpers
      using Refinements

      def [](obj) = obj.to_rx
    end

    extend Helpers

    class List
      using Refinements

      def self.[](*items) = new(items)

      def initialize(items)
        @signal = U.signal(items.map(&:to_rx))
      end

      protected attr :signal

      def ==(other)
        self.class === other && other.signal == self.signal
      end

      def replace(items) = write(items.map(&:to_rx))
      def to_rx = self

      def first
        U.computed { @signal.value.first }.value
      end

      def last
        U.computed { @signal.value.last }.value
      end

      def to_str
        U.computed do
          mid = @signal.value.map { "#{_1.inspect}" }.join(", ")
          "[#{mid}]"
        end.value
      end

      def inspect
        to_str
      end

      def push(value)
        write([*peek, value.to_rx])
        self
      end

      def pop
        peek => [*list, last]
        write(list)
        last
      end

      def shift
        peek => [first, *list]
        write(list)
        first
      end

      def unshift(value)
        write([value.to_rx, *peek])
        self
      end

      class MapResult
        include Enumerable

        def initialize(array)
          @array = array.dup.freeze
        end

        def each(&) = @array.each(&)
        def map_with_index(&) = map.with_index(&)
        def to_rx = self
      end

      def map(&block)
        disposal = []
        mapped = []
        items = []
        signals = []
        size = 0

        U.on_dispose do
          disposal.each(&:call)
        end

        U.computed! do
          new_items = @signal.value

          U.untrack do
            if new_items.empty? && size.nonzero?
              disposal.each(&:call)
              disposal = []
              mapped = []
              items = []
              break
            end

            new_items.each_with_index do |new_item, i|
              if i < items.size && items[i] != new_item
                signals[i].value = new_item.to_rx
              elsif i >= items.size
                if current = Signals::Effect.current
                  current.index = i
                end

                mapped[i] = U.root do |dispose|
                  disposal[i] = dispose
                  s = U.signal(new_item.to_rx)
                  signals[i] = s
                  block.call(s.proxy, i)
                end
              end
            end

            size = new_items.size
            disposal.slice!(size..-1).each(&:call)
            signals.slice!(size..-1)
            items = new_items.dup
            mapped.slice!(size..-1)
            MapResult.new(mapped)
          end
        end
      end

      def [](index)
        U.computed { @signal.value[index] }
      end

      def []=(index, value)
        new_array = peek
        new_array[index] = value.to_rx
        write(new_array)
      end

      private

      def write(value) = @signal.value = value
      def peek = @signal.peek
      def read = @signal.value
    end

    class Map
      using Refinements

      def self.[](**elems) = new(elems)

      def initialize(elems = {})
        @signal = U.signal(elems.transform_values(&:to_rx))
      end

      def replace(items) = write(items.map(&:to_rx))

      def ==(other)
        self.class === other && other.signal == self.signal
      end

      protected attr :signal
      def to_rx = self

      def to_str
        U.computed! do
          mid = read.map { "#{_1.inspect} => #{_2.inspect}" }.join(", ")
          "{ #{mid} }"
        end
      end

      def inspect = to_str

      def include?(key)
        U.computed! { read.include?(key) }
      end

      def [](key)
        U.computed! { read[key] }
      end

      def []=(key, value)
        hash = peek.dup

        if hash[key] in Signals::Reactive | Proxy => signal
          stored = U.peek(signal)

          if stored.nil?
            U.write(signal, value)
            return
          end

          target = U.peek(value)

          if stored.class === target
            U.write(signal, value)
            return
          end
        end

        write(**hash, key => value.to_rx)
      end

      def map(&block)
        disposal = {}
        mapped = {}
        signals = {}
        keys = Set.new

        U.computed do
          new_items = @signal.value

          U.untrack do
            if new_items.empty?
              unless items.empty?
                disposal.each_value(&:call)
                disposal = {}
                mapped = {}
                signals = {}
                keys = Set.new
                break
              end
            end

            deleted = keys.subtract(new_items.keys)

            deleted.each do |key|
              disposal.delete(key)&.call
              mapped.delete(key)
              signals.delete(key)
              keys.delete(key)
            end

            new_items.each do |key, value|
              if signals.has?(key)
                U.write(signals[key], value)
              else
                mapped[i] = U.root do |dispose|
                  disposal[key] = dispose
                  s = U.signal(value)
                  signals[key] = s
                  block.call(s.proxy)
                end
              end
            end

            keys = Set.new(new_items.keys)

            mapped.map(&:value)
          end
        end
      end

      private

      def write(value) = @signal.value = value
      def peek = @signal.peek
      def read = @signal.value
    end
  end
end
