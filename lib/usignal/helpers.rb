require_relative "utils"
require_relative "signals"
require_relative "proxy"
require_relative "batch"

module USignal
  module Helpers
    include Proxy::Helpers

    def batch(&block) = Batch.batch(&block)

    def signal(initial, **options) =
      Signals::Reactive.from(initial, **options)
    def signal!(initial, **options) =
      rx(signal(initial, **options))

    def computed(initial = nil, **options, &block) =
      Signals::Computed.new(initial, is_effect: false, **options, &block)
    def computed!(initial = nil, **options, &block) =
      rx(computed(initial, **options, &block))

    def on_dispose(&block) =
      Signals::Effect.on_dispose(&block)

    def effect(initial = nil, **options, &block)
      e = Signals::Effect.create(initial, **options, &block)
      ->() { e.stop }
    end

    TRACKING = :"USignal::TRACKING"

    def track(&block) =
      Utils.with_thread_local(TRACKING, true, &block)
    def untrack(&block)
      Utils.with_thread_local(TRACKING, false, &block)
    end
    def tracking? =
      Utils.get_thread_local(TRACKING) != false

    def peek(obj)
      case obj
      in Proxy
        peek(get_signal(obj))
      in Signals::Base
        peek(obj.peek)
      else
        obj
      end
    end

    def read(obj)
      case obj
      in Proxy
        read(get_signal(obj))
      in Signals::Base
        read(obj.value)
      else
        obj
      end
    end

    def rx(obj) = RX[obj]

    def root(&block)
      root = Signals::Effect.create {}

      computed do
        dispose = -> { root.dispose }

        root.use do
          U.track do
            block.call(dispose)
          end
        end
      end.value
    end

    def root2(&block)
      root = Signals::Effect.create {}
      sig = signal(nil)

      effect do
        dispose = -> { root.dispose }

        root.use do
          sig.value = block.call(dispose)
        end
      end

      sig
    end
  end
end
