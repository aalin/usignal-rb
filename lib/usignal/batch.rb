module USignal
  class Batch
    CURRENT = :"USignal::Batch::CURRENT"

    def self.enqueue(signal)
      batch { _1.add(signal) }
    end

    def self.dispose(signal)
      batch { _1.dispose(signal) }
    end

    def self.current =
      Utils.get_thread_local(CURRENT)

    def self.batch(&block)
      prev = current
      is_root = !prev

      Utils.with_thread_local(CURRENT, prev || new) do |queue|
        yield queue
      ensure
        queue.flush! if is_root
      end
    end

    def initialize
      @signals = []
      @effects = []
      @disposed = []
    end

    def add(signal)
      @signals.push(signal)
    end

    def dispose(effect)
      @disposed.push(*effect.disposes)
      effect.disposes.clear
    end

    def flush!
      update_dependencies
      flush_effects!
      flush_dispose!
    end

    private

    def update_dependencies
      dependencies_to_update = @signals.dup
      @signals.clear

      while signal = dependencies_to_update.shift
        signal.computeds.each do |computed|
          next if computed.should_update?
          next unless computed.related.include?(signal)

          computed.related.clear
          computed.should_update!

          unless computed.effect?
            dependencies_to_update << computed.signal
            next
          end

          @effects.push(computed)
          computed_dependencies_to_update = [computed]

          while dep = computed_dependencies_to_update.shift
            dep.effects.each do |effect|
              effect.related.clear
              effect.should_update!
              computed_dependencies_to_update << effect
            end
          end
        end
      end
    end

    def flush_dispose!
      U.untrack do
        while dispose = @disposed.shift
          dispose.call
        end
      end
    end

    def flush_effects!
      while effect = @effects.shift
        effect.value
      end
    end
  end
end
