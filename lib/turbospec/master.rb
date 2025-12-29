require "socket"
require "tmpdir"
require "etc"
require "timeout"
require_relative "result_serializer"
require_relative "protocol"

module Turbospec
  class Master
    def initialize(options = {}, args = [])
      @args = args
      @workers = options[:workers] || Etc.nprocessors
      @fail_fast = options[:fail_fast] || false
      @only_failures = options[:only_failures] || false
      @order = options[:order]
      @profile = options[:profile]
      @shard = options[:shard]
      @socket_path = File.join(Dir.tmpdir, "turbospec_#{Process.pid}.sock")
      @server = UNIXServer.new(@socket_path)
      @worker_pids = []
      @failed = false
    end

    def run
      begin
        # Enable persistence (always, so we can use --only-failures in future runs)
        RSpec.configuration.example_status_persistence_file_path ||= 'spec/examples.txt'

        # Add flags to args if requested
        args_with_flags = @args.dup
        if @only_failures
          args_with_flags << '--only-failures'
        end

        # Load examples BEFORE forking
        @examples = Runner.load_examples(args_with_flags)
        @queue = (0...@examples.size).to_a

        # Order examples by runtime if requested
        if @order == 'runtime'
          sort_queue_by_runtime
        end

        # Apply sharding if requested
        if @shard
          apply_sharding
        end

        # Auto-tune worker count: don't spawn more workers than examples
        if @workers > @queue.size
          @workers = @queue.size
        end

        @reporter = RSpec.configuration.reporter
        require 'rspec/core/notifications'
        @start_time = RSpec::Core::Time.now
        @reporter.start(RSpec::Core::Notifications::StartNotification.new(@examples.size, @start_time))

        puts "Master starting with #{@workers} workers..."

        trap_signals
        spawn_workers

        run_loop

        @reporter.examples.size > 0 && @reporter.failed_examples.empty?
      ensure
        if @reporter && @start_time
          @reporter.finish

          # Print profiling information if requested
          if @profile && @profile > 0
            print_profile
          end

          # Persist example statuses if configured
          if RSpec.configuration.example_status_persistence_file_path && @examples
            require 'rspec/core/example_status_persister'
            persister = RSpec::Core::ExampleStatusPersister.new(@examples, RSpec.configuration.example_status_persistence_file_path)
            persister.persist
          end
        end
        shutdown
      end
    end

    private

    def trap_signals
      trap("INT") do
        puts "\nMaster received interrupt. Shutting down..."
        if @shutting_down
          puts "Forcing exit..."
          kill_workers("KILL")
          exit 1
        else
          @shutting_down = true
          shutdown
          exit 1
        end
      end
    end

    def kill_workers(signal)
      @worker_pids.each do |pid|
        Process.kill(signal, pid) rescue nil
      end
    end

    def spawn_workers
      Turbospec.configuration.before_fork_hook&.call

      @workers.times do |i|
        pid = fork do
          # Child process
          require_relative "worker"
          Worker.new(@socket_path, i).run
        end
        @worker_pids << pid
      end
    end

    def run_loop
      active_workers = @workers
      sockets = [@server]
      worker_to_example = {}

      while active_workers > 0
        ready, = IO.select(sockets)

        ready.each do |s|
          if s == @server
            sockets << @server.accept
          else
            line = s.gets&.strip
            case line
            when Protocol::READY
              if @queue.empty? || (@fail_fast && @failed)
                s.puts Protocol::NONE
              else
                index = @queue.shift
                worker_to_example[s] = index
                s.puts Protocol.work_command(index)
              end
            when /^\{/
              worker_to_example.delete(s)
              handle_result(line)
              if @fail_fast && @failed
                @queue.clear
              end
            when Protocol::DONE
              active_workers -= 1
              sockets.delete(s)
              s.close
            when nil
              # Socket closed or error unexpectedly
              handle_worker_crash(worker_to_example.delete(s)) if worker_to_example[s]
              active_workers -= 1
              sockets.delete(s)
              s.close
            end
          end
        end
      end
    end

    def handle_worker_crash(index)
      example = @examples[index]
      @reporter.example_started(example)

      res = example.execution_result
      res.status = :failed
      res.exception = RuntimeError.new("Worker crashed while running this example")

      @failed = true
      @reporter.example_failed(example)
    end

    def handle_result(line)
      require 'json'
      data = JSON.parse(line.strip)
      index = data["index"]
      example = @examples[index]

      @reporter.example_started(example)

      # Re-hydrate execution_result using ResultSerializer
      ResultSerializer.deserialize(data, example)

      case data["status"]
      when "passed"
        @reporter.example_passed(example)
      when "failed"
        @failed = true
        @reporter.example_failed(example)
      when "pending"
        @reporter.example_pending(example)
      end
    end

    def sort_queue_by_runtime
      # Load timing data from persistence file
      timings = load_timing_data
      return if timings.empty?

      # Sort queue by runtime (slowest first)
      @queue.sort_by! do |index|
        example = @examples[index]
        example_id = example.id
        # Default to 0 for new examples without timing data
        -(timings[example_id] || 0)
      end
    end

    def apply_sharding
      shard_index = @shard[:index]
      shard_total = @shard[:total]

      # Load timing data for smart balancing
      timings = load_timing_data

      if timings.empty?
        # No timing data: simple round-robin assignment
        @queue = @queue.select.with_index { |_, i| i % shard_total == shard_index }
      else
        # Smart balancing: distribute examples to minimize total runtime difference
        # Use greedy bin-packing: assign each example (sorted by runtime desc) to the shard with least total time

        # Get runtime for each example in queue
        examples_with_time = @queue.map do |index|
          example_id = @examples[index].id
          { index: index, runtime: timings[example_id] || 0 }
        end

        # Sort by runtime descending (process slowest first)
        examples_with_time.sort_by! { |e| -e[:runtime] }

        # Initialize shard buckets
        shard_times = Array.new(shard_total, 0.0)
        shard_assignments = Array.new(shard_total) { [] }

        # Greedy assignment: assign each example to the shard with least total time
        examples_with_time.each do |item|
          # Find shard with minimum total time
          min_shard = shard_times.each_with_index.min_by { |time, _| time }[1]
          shard_times[min_shard] += item[:runtime]
          shard_assignments[min_shard] << item[:index]
        end

        # Keep only examples assigned to our shard
        @queue = shard_assignments[shard_index]
      end

      puts "Shard #{shard_index + 1}/#{shard_total}: #{@queue.size} examples"
    end

    def load_timing_data
      timings = {}
      persistence_file = RSpec.configuration.example_status_persistence_file_path
      return timings unless persistence_file && File.exist?(persistence_file)

      File.readlines(persistence_file).each do |line|
        # Skip header lines
        next if line.start_with?('example_id', '-')

        # Parse: "./path/to/spec.rb[1:2:3] | status | 0.12345 seconds |"
        if line =~ /^(.*?)\s*\|\s*\w+\s*\|\s*([\d.]+)\s+seconds/
          example_id = $1.strip
          runtime = $2.to_f
          timings[example_id] = runtime
        end
      end

      timings
    end

    def print_profile
      # Collect examples with their run times
      examples_with_times = @reporter.examples.map do |example|
        {
          example: example,
          runtime: example.execution_result.run_time || 0
        }
      end

      # Sort by runtime (slowest first) and take top N
      slowest = examples_with_times.sort_by { |e| -e[:runtime] }.take(@profile)

      return if slowest.empty?

      total_time = @reporter.examples.sum { |ex| ex.execution_result.run_time || 0 }
      slowest_time = slowest.sum { |e| e[:runtime] }
      percentage = total_time > 0 ? (slowest_time / total_time * 100) : 0

      puts "\nTop #{slowest.size} slowest examples (#{slowest_time.round(5)} seconds, #{'%.1f' % percentage}% of total time):\n"

      slowest.each do |item|
        example = item[:example]
        runtime = item[:runtime]
        puts "  #{example.full_description}"
        puts "    #{runtime.round(5)} seconds #{example.location}"
      end
    end

    def shutdown
      return if @shutdown_complete
      @shutdown_complete = true

      puts "Master shutting down..."

      # Wait for workers to finish naturally first
      begin
        Timeout.timeout(2) do
          Process.waitall
        end
      rescue Timeout::Error
        # If workers don't finish in time, force kill them
        kill_workers("KILL")
        Process.waitall rescue nil
      end

      File.unlink(@socket_path) if File.exist?(@socket_path)
    end
  end
end
