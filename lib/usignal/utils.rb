module USignal
  module Utils
    def self.with_thread_local(name, value, &block)
      prev, Thread.current[name] = Thread.current[name], value
      yield value
    ensure
      Thread.current[name] = prev
    end

    def self.get_thread_local(name)
      Thread.current[name]
    end
  end
end
