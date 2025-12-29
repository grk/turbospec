require "socket"
require_relative "protocol"

module Turbospec
  class Worker
    def initialize(socket_path, index)
      @socket_path = socket_path
      @index = index
    end

    def run
      # Connect to master
      socket = UNIXSocket.new(@socket_path)

      require_relative "worker_reporter"

      setup_worker

      begin
        loop do
          socket.puts Protocol::READY

          response = socket.gets
          break unless response

          case response.strip
          when /^#{Protocol::WORK}/
            index = Protocol.parse_work_command(response.strip)
            worker_reporter = WorkerReporter.new(socket, index)
            Runner.run_example(index, worker_reporter)
            # Result is sent by the reporter
          when Protocol::NONE
            socket.puts Protocol::DONE
            break
          end
        end
      rescue Exception => e
        $stderr.puts "Worker error: #{e.class}: #{e.message}"
        $stderr.puts e.backtrace.join("\n")
        raise e
      end

      # Run after(:suite) hooks
      run_after_suite_hooks

      socket.close
    end

    private

    def setup_worker
      # Standard parallel_tests/flatware convention
      ENV['TEST_ENV_NUMBER'] = @index == 0 ? '' : (@index + 1).to_s

      # Run custom hook
      Turbospec.configuration.after_fork_hook&.call(@index)

      # Default ActiveRecord handling
      if defined?(ActiveRecord::Base)
        ActiveRecord::Base.establish_connection
      end

      # Trap INT to prevent workers from printing "Master received interrupt"
      # Workers should wait for the Master to send TERM
      trap("INT", "IGNORE")

      # Run before(:suite) hooks
      run_before_suite_hooks
    end

    def run_before_suite_hooks
      require 'rspec/core/notifications'
      notif = RSpec::Core::Notifications::NullNotification.new
      (RSpec.configuration.instance_variable_get(:@before_suite_hooks) || []).each do |h|
        h.run(notif)  # Let exceptions propagate to fail fast
      end
      $stdout.flush
    end

    def run_after_suite_hooks
      require 'rspec/core/notifications'
      notif = RSpec::Core::Notifications::NullNotification.new
      failures = []
      (RSpec.configuration.instance_variable_get(:@after_suite_hooks) || []).each do |h|
        begin
          h.run(notif)
        rescue => e
          failures << e
          $stderr.puts "Error running after(:suite) hook: #{e.class}: #{e.message}"
          $stderr.puts e.backtrace.first(5).join("\n") if e.backtrace
        end
      end
      $stdout.flush

      # Log summary if there were failures
      if failures.any?
        $stderr.puts "\n#{failures.size} after(:suite) hook(s) failed"
      end
    end
  end
end
