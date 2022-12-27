# frozen_string_literal: true

require "set"
require_relative "usignal/version"
require_relative "usignal/utils"
require_relative "usignal/signals"
require_relative "usignal/proxy"
require_relative "usignal/batch"
require_relative "usignal/rx"
require_relative "usignal/helpers"

module USignal
  class Error < StandardError; end

  module U
    extend Helpers
  end
end
