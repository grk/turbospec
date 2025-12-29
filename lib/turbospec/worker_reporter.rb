require 'json'
require_relative 'result_serializer'

module Turbospec
  class WorkerReporter
    def initialize(socket, index)
      @socket = socket
      @index = index
    end

    def example_started(notification)
      # Optional: Notify master that execution started
    end

    def example_passed(notification)
      notify("passed", notification)
    end

    def example_failed(notification)
      notify("failed", notification)
    end

    def example_pending(notification)
      notify("pending", notification)
    end

    def example_finished(notification)
      # No-op, we used pass/fail/pending
    end

    def example_group_started(notification)
      # No-op
    end

    def example_group_finished(notification)
      # No-op
    end

    def message(notification)
      # No-op
    end

    def fail_fast_limit_met?
      false
    end

    def method_missing(name, *args, &block)
      # No-op for any other reporter methods we don't care about
    end

    def respond_to_missing?(name, include_private = false)
      true
    end

    private

    def notify(status, example)
      payload = ResultSerializer.serialize(example, @index)
      payload[:status] = status  # Override with the specific status
      @socket.puts(JSON.dump(payload))
    end
  end
end
