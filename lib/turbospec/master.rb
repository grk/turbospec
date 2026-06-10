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
      @timeout = options[:timeout]
      @timings = options[:timings]
      @timings_out = options[:timings_out]
      @socket_path = File.join(Dir.tmpdir, "turbospec_#{Process.pid}.sock")
      @server = UNIXServer.new(@socket_path)
      @worker_pids = {}
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

          write_timings_out if @timings_out
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
      @worker_pids.each_value do |pid|
        Process.kill(signal, pid) rescue nil
      end
    end

    def spawn_workers
      Turbospec.configuration.before_fork_hook&.call

      @workers.times { |i| spawn_worker(i) }
    end

    def spawn_worker(index)
      pid = fork do
        # Child process
        require_relative "worker"
        Worker.new(@socket_path, index).run
      end
      @worker_pids[index] = pid
    end

    def run_loop
      @active_workers = @workers
      @sockets = [@server]
      @inflight = {}      # socket => { example_index:, since: }
      @socket_worker = {} # socket => worker index

      while @active_workers > 0
        ready, = IO.select(@sockets, nil, nil, @timeout && 1)

        (ready || []).each do |s|
          if s == @server
            @sockets << @server.accept
          else
            line = s.gets&.strip
            case line
            when /\A#{Protocol::HELLO}/o
              @socket_worker[s] = Protocol.parse_hello_command(line)
            when Protocol::READY
              if @queue.empty? || (@fail_fast && @failed)
                s.puts Protocol::NONE
              else
                index = @queue.shift
                @inflight[s] = { example_index: index, since: Time.now }
                s.puts Protocol.work_command(index)
              end
            when /^\{/
              @inflight.delete(s)
              handle_result(line)
              if @fail_fast && @failed
                @queue.clear
              end
            when Protocol::DONE
              drop_worker(s)
            when nil
              # Socket closed or error unexpectedly
              if (work = @inflight.delete(s))
                handle_worker_crash(work[:example_index])
              end
              drop_worker(s)
            end
          end
        end

        check_timeouts if @timeout
      end
    end

    def drop_worker(socket)
      @active_workers -= 1
      @socket_worker.delete(socket)
      @sockets.delete(socket)
      socket.close
    end

    def check_timeouts
      now = Time.now
      @inflight.select { |_s, work| now - work[:since] > @timeout }.keys.each do |socket|
        handle_worker_timeout(socket)
      end
    end

    def handle_worker_timeout(socket)
      work = @inflight.delete(socket)
      worker_index = @socket_worker[socket]
      example = @examples[work[:example_index]]

      warn "turbospec: example exceeded the #{@timeout}s timeout, killing worker #{worker_index}: #{example.id}"

      # A result that arrived exactly at the deadline may still be buffered on
      # the socket; we drop it and conservatively report a timeout failure.
      if (pid = @worker_pids[worker_index])
        Process.kill("KILL", pid) rescue nil
        Process.waitpid(pid) rescue nil
      end
      drop_worker(socket)

      @reporter.example_started(example)
      res = example.execution_result
      res.status = :failed
      res.exception = RuntimeError.new(
        "Example exceeded the #{@timeout}s timeout (--timeout) and its worker was killed"
      )
      @failed = true
      @reporter.example_failed(example)

      if @fail_fast
        @queue.clear
      elsif !@queue.empty?
        spawn_worker(worker_index)
        @active_workers += 1
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

      if @shard[:mode] == :hash
        require 'zlib'
        # CRC32, NOT String#hash: #hash is SipHash-seeded per process, so
        # every machine would compute a different partition — overlapping on
        # some examples and silently dropping others.
        @queue.select! { |index| Zlib.crc32(@examples[index].id) % shard_total == shard_index }
        puts "Shard #{shard_index + 1}/#{shard_total} (hash): #{@queue.size} examples"
        return
      end

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

      if @timings
        # Sorted glob order makes the merge deterministic: when an example
        # appears in several files (it moved shards between runs), the
        # lexicographically last file wins.
        Dir.glob(@timings).sort.each { |path| parse_timing_file(path, timings) }
      else
        parse_timing_file(RSpec.configuration.example_status_persistence_file_path, timings)
      end

      timings
    end

    def parse_timing_file(path, timings)
      return unless path && File.exist?(path)

      File.readlines(path).each do |line|
        # Skip header lines
        next if line.start_with?('example_id', '-')

        # Parse: "./path/to/spec.rb[1:2:3] | status | 0.12345 seconds |"
        if line =~ /^(.*?)\s*\|\s*\w+\s*\|\s*([\d.]+)\s+seconds/
          example_id = $1.strip
          runtime = $2.to_f
          timings[example_id] = runtime
        end
      end
    end

    def write_timings_out
      require 'fileutils'
      FileUtils.mkdir_p(File.dirname(@timings_out))

      File.open(@timings_out, 'w') do |f|
        @reporter.examples.each do |example|
          result = example.execution_result
          next unless result.run_time

          # %.5f, not round: tiny floats round to scientific notation
          # ("4.0e-05"), which the parser doesn't accept.
          f.puts "#{example.id} | #{result.status} | #{format('%.5f', result.run_time)} seconds |"
        end
      end
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
