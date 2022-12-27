module USignal
  class Proxy < BasicObject
    module Helpers
      module Refinements
        refine Proxy do
          def signal
            @signal
          end

          def value=(new_value)
            @signal.value = new_value
          end
        end
      end

      using Refinements

      def get_proxy(obj)
        case obj
        in Proxy
          obj
        in Signals::Base
          obj.proxy
        end
      end

      def get_signal(obj)
        case obj
        in Proxy
          obj.signal
        in Signals::Base
          obj
        end
      end

      def write(obj, value)
        obj => Proxy | Signals::Base
        obj.value = value
      end
    end

    using Helpers::Refinements

    def initialize(signal)
      @signal = signal
    end

    def ! = !itself
    def !=(other) = !(self == other)
    def ==(other) = itself == other.itself

    def hash = @signal.hash
    def to_rx = self

    def inspect
      "\e[2m⇛#{@signal.object_id.to_s(16)}⟅\e[22m#{super}\e[2m⟆\e[22m"
    end

    def method_missing(method, *args, &block)
      @signal.value.send(method, *args, &block)
    end
  end
end
