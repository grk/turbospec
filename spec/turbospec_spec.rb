require 'spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe "Turbospec Integration" do
  let(:turbospec) { File.expand_path('../exe/turbospec', __dir__) }

  def run_turbospec(*args, env: {})
    cmd = "bundle exec #{turbospec} #{args.join(' ')}"
    stdout, stderr, status = Open3.capture3(env, cmd)
    [stdout, stderr, status]
  end

  it "runs simple specs successfully" do
    stdout, _stderr, status = run_turbospec("spec/test_fixtures/simple.rb")
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("2 examples, 0 failures")
  end

  it "reports failures correctly" do
    stdout, _stderr, status = run_turbospec("spec/test_fixtures/failing.rb")
    expect(status.exitstatus).to eq(1)
    expect(stdout).to include("2 examples, 1 failure")
  end

  it "handles aggregate_failures with multiple expectations" do
    stdout, stderr, status = run_turbospec("-w 1 spec/test_fixtures/aggregate_failures.rb")
    expect(status.exitstatus).to eq(1)
    # Should not crash with NoMethodError for aggregation_metadata
    expect(stderr).not_to include("undefined method")
    expect(stderr).not_to include("aggregation_metadata")
    expect(stdout).to include("2 examples, 1 failure")
    # Should show all three failed expectations in the output
    expect(stdout).to include("expected: 2")
    expect(stdout).to include("expected: \"bar\"")
    expect(stdout).to include("expected [1, 2, 3] to include 4")
  end

  it "handles edge cases (pending, skipped, shared examples, large output)" do
    stdout, _stderr, status = run_turbospec("spec/test_fixtures/edge_cases.rb")

    expect(status.exitstatus).to eq(1)
    # 7 examples + 1 failure + 2 pending
    expect(stdout).to include("7 examples, 1 failure, 2 pending")
    expect(stdout).to include("Outer Error: Inner Error")
  end

  it "handles worker crashes gracefully" do
    # This might still hang if we don't have a timeout in Master.
    # We'll use a timeout here to ensure the test doesn't hang the runner.
    require 'timeout'
    begin
      Timeout.timeout(10) do
        _stdout, _stderr, status = run_turbospec("-w 2 spec/test_fixtures/edge_cases.rb", env: { 'CRASH_WORKER' => '1' })
        # If it crashes, it should probably return non-zero or at least not hang.
        expect(status.exitstatus).not_to be_nil
      end
    rescue Timeout::Error
      fail "Master hung when a worker crashed"
    end
  end

  it "raises an error if before(:all) is used" do
    stdout, stderr, status = run_turbospec("spec/test_fixtures/hooks.rb")
    expect(status.exitstatus).to eq(1)
    # The error happens during load_examples, which is in the Master process.
    # It should print to stderr or stdout before reporting 0 examples.
    expect(stdout + stderr).to include("turbospec does not support before/after(:all)")
  end

  it "runs before(:suite) and after(:suite) in workers" do
    stdout, _stderr, status = run_turbospec("-w 1 spec/test_fixtures/suite_hooks.rb")
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("HOOK: before(:suite)")
    expect(stdout).to include("HOOK: after(:suite)")
  end

  it "cleans up socket file even when initialization fails" do
    require 'tmpdir'

    # Count socket files before running
    before_sockets = Dir[File.join(Dir.tmpdir, "turbospec_*.sock")]

    # Run with a spec file that will cause an error during load_examples
    # (the hooks.rb raises an error because it has before(:all))
    _stdout, _stderr, status = run_turbospec("spec/test_fixtures/hooks.rb")
    expect(status.exitstatus).to eq(1)

    # Give the process a moment to clean up
    sleep 0.1

    # Count socket files after running - should be the same (no leak)
    after_sockets = Dir[File.join(Dir.tmpdir, "turbospec_*.sock")]
    expect(after_sockets.size).to eq(before_sockets.size)
  end

  it "fails fast when before(:suite) hook raises an error" do
    _stdout, stderr, status = run_turbospec("-w 1 spec/test_fixtures/failing_before_suite.rb")
    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("Setup failed in before(:suite)")
  end

  it "reports errors in after(:suite) hooks but completes the run" do
    stdout, stderr, _status = run_turbospec("-w 1 spec/test_fixtures/failing_after_suite.rb")
    # Examples should still run and pass
    expect(stdout).to include("2 examples, 0 failures")
    # But after(:suite) error should be logged to stderr
    expect(stderr).to include("Error running after(:suite) hook:")
    expect(stderr).to include("after(:suite) hook(s) failed")
  end

  it "handles load errors gracefully" do
    stdout, _stderr, status = run_turbospec("spec/test_fixtures/load_error.rb")
    expect(status.exitstatus).to eq(1)
    expect(stdout).to include("An error occurred while loading")
    expect(stdout).to include("LoadError")
    expect(stdout).to include("cannot load such file")
  end

  it "handles worker crashes mid-execution" do
    stdout, _stderr, status = run_turbospec("-w 2 spec/test_fixtures/worker_exit.rb", env: { 'FORCE_WORKER_EXIT' => '1' })
    expect(status.exitstatus).to eq(1)
    expect(stdout).to include("3 examples, 1 failure")
    expect(stdout).to include("Worker crashed while running this example")
  end

  it "handles threads with abort_on_exception" do
    stdout, _stderr, status = run_turbospec("-w 1 spec/test_fixtures/thread_abort.rb")
    expect(status.exitstatus).to eq(1)
    expect(stdout).to include("2 examples, 1 failure")
    expect(stdout).to include("Thread explosion!")
  end

  it "handles syntax errors in spec files" do
    stdout, _stderr, status = run_turbospec("spec/test_fixtures/syntax_error.rb")
    expect(status.exitstatus).to eq(1)
    expect(stdout).to include("0 examples, 0 failures, 1 error occurred outside of examples")
    expect(stdout).to include("SyntaxError")
  end

  it "handles Kernel.exit (not exit!)" do
    stdout, stderr, status = run_turbospec("-w 1 spec/test_fixtures/kernel_exit.rb", env: { 'FORCE_KERNEL_EXIT' => '1' })
    expect(status.exitstatus).to eq(1)
    # Kernel.exit actually exits the worker process, so it's treated as a crash
    expect(stdout).to include("1 example, 1 failure")
    expect(stdout).to include("Worker crashed while running this example")
    # The worker error shows SystemExit in stderr
    expect(stderr).to include("SystemExit")
  end

  it "handles socket file already exists" do
    require 'socket'
    require 'tmpdir'

    # Create a socket file at the expected location
    socket_path = File.join(Dir.tmpdir, "turbospec_#{Process.pid}.sock")

    # Pre-create the socket file
    File.open(socket_path, 'w') { |f| f.write("dummy") }

    begin
      stdout, stderr, status = run_turbospec("spec/test_fixtures/simple.rb")
      # Should either clean up the stale socket and succeed, or fail gracefully
      expect([0, 1]).to include(status.exitstatus)
      if status.exitstatus == 1
        expect(stdout + stderr).to include("Address already in use").or include("File exists")
      end
    ensure
      File.unlink(socket_path) if File.exist?(socket_path)
    end
  end

  it "stops on first failure with --fail-fast" do
    # Use only 1 worker to have deterministic behavior
    stdout, _stderr, status = run_turbospec("--fail-fast -w 1 spec/test_fixtures/many_failures.rb")
    expect(status.exitstatus).to eq(1)
    # Should stop after first failure
    expect(stdout).to match(/\d+ examples?, 1 failure/)
    # With 1 worker and fail-fast, should run exactly 1 example (the first failure)
    examples_run = stdout.match(/(\d+) examples?/)[1].to_i
    expect(examples_run).to eq(1)
  end

  it "runs only previously failed examples with --only-failures" do
    # First run: run all tests and record failures
    stdout1, _stderr1, status1 = run_turbospec("-w 1 spec/test_fixtures/many_failures.rb")
    expect(status1.exitstatus).to eq(1)
    expect(stdout1).to include("6 examples, 5 failures")

    # Second run: only run failures
    stdout2, _stderr2, status2 = run_turbospec("-w 1 --only-failures spec/test_fixtures/many_failures.rb")
    expect(status2.exitstatus).to eq(1)
    # Should only run the 5 failed examples, not all 6
    expect(stdout2).to include("5 examples, 5 failures")
  end

  it "combines --fail-fast and --only-failures" do
    # First run: run all tests and record failures
    stdout1, _stderr1, _status1 = run_turbospec("-w 1 spec/test_fixtures/many_failures.rb")
    expect(stdout1).to include("6 examples, 5 failures")

    # Second run: only run failures, stop on first failure
    stdout2, _stderr2, status2 = run_turbospec("-w 1 --fail-fast --only-failures spec/test_fixtures/many_failures.rb")
    expect(status2.exitstatus).to eq(1)
    # Should run only 1 example (first failure from the failures list)
    expect(stdout2).to match(/1 examples?, 1 failure/)
  end

  it "auto-tunes worker count to not exceed example count" do
    stdout, _stderr, status = run_turbospec("-w 100 spec/test_fixtures/simple.rb")
    expect(status.exitstatus).to eq(0)
    # simple.rb has 2 examples, so should only start 2 workers
    expect(stdout).to include("Master starting with 2 workers")
  end

  it "orders examples by runtime when --order=runtime is specified" do
    # First run: establish timing data
    _stdout1, _stderr1, status1 = run_turbospec("-w 1 spec/test_fixtures/timing_test.rb")
    expect(status1.exitstatus).to eq(0)

    # Second run: verify runtime ordering works (slowest first)
    # We can't easily verify the order directly, but we can ensure it doesn't error
    stdout2, _stderr2, status2 = run_turbospec("-w 1 --order=runtime spec/test_fixtures/timing_test.rb")
    expect(status2.exitstatus).to eq(0)
    expect(stdout2).to include("3 examples, 0 failures")
  end

  it "shows profiling information with --profile flag" do
    stdout, _stderr, status = run_turbospec("-w 1 --profile=3 spec/test_fixtures/timing_test.rb")
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("Top 3 slowest examples")
    expect(stdout).to include("seconds, ")
    expect(stdout).to include("% of total time")
    expect(stdout).to include("Timing Test")
  end

  it "distributes examples across shards with --shard flag" do
    # Use simple.rb which has 2 examples - split into 2 shards (1-based indexing)
    # Using simple.rb avoids timing data pollution from other tests using many_failures.rb
    stdout1, _stderr1, status1 = run_turbospec("-w 1 --shard=1/2 spec/test_fixtures/simple.rb")
    stdout2, _stderr2, status2 = run_turbospec("-w 1 --shard=2/2 spec/test_fixtures/simple.rb")

    # All shards should complete successfully (simple.rb has no failures)
    expect(status1.exitstatus).to eq(0)
    expect(status2.exitstatus).to eq(0)

    # Each shard should report its assignment
    expect(stdout1).to match(/Shard 1\/2: \d+ examples?/)
    expect(stdout2).to match(/Shard 2\/2: \d+ examples?/)

    # Extract example counts from each shard
    count1 = stdout1.match(/Shard 1\/2: (\d+) examples?/)[1].to_i
    count2 = stdout2.match(/Shard 2\/2: (\d+) examples?/)[1].to_i

    # Total should equal 2 (all examples covered, no overlap)
    expect(count1 + count2).to eq(2)
  end

  it "partitions disjointly and deterministically with --shard=hash:" do
    stdout1, _, status1 = run_turbospec("-w 1 --shard=hash:1/2 -f doc spec/test_fixtures/hash_sharding.rb")
    stdout2, _, status2 = run_turbospec("-w 1 --shard=hash:2/2 -f doc spec/test_fixtures/hash_sharding.rb")
    rerun1, _, _ = run_turbospec("-w 1 --shard=hash:1/2 -f doc spec/test_fixtures/hash_sharding.rb")

    expect(status1.exitstatus).to eq(0)
    expect(status2.exitstatus).to eq(0)
    expect(stdout1).to match(/Shard 1\/2 \(hash\): \d+ examples?/)

    examples1 = stdout1.scan(/hs example \d+/).uniq.sort
    examples2 = stdout2.scan(/hs example \d+/).uniq.sort

    # Disjoint, complete, and stable across runs — correctness must not
    # depend on timing data or run order.
    expect(examples1 & examples2).to be_empty
    expect((examples1 + examples2).size).to eq(20)
    expect(rerun1.scan(/hs example \d+/).uniq.sort).to eq(examples1)
  end

  it "writes only ran examples to --timings-out" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "runtimes-1.txt")
      stdout, _, status = run_turbospec("-w 1 --shard=hash:1/2 --timings-out #{out} spec/test_fixtures/hash_sharding.rb")

      expect(status.exitstatus).to eq(0)
      shard_count = stdout.match(/Shard 1\/2 \(hash\): (\d+) examples?/)[1].to_i
      lines = File.readlines(out)
      expect(lines.size).to eq(shard_count)
      expect(lines.size).to be < 20 # ran-only: the other shard's examples are absent
      expect(lines).to all(match(/\A\.\/spec\/test_fixtures\/hash_sharding\.rb\[1:\d+\] \| passed \| [\d.]+ seconds \|$/))
    end
  end

  it "merges multiple --timings files with later files winning" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "runtimes-1.txt"), <<~TIMINGS)
        ./spec/test_fixtures/timing_order.rb[1:1] | passed | 1.0 seconds |
        ./spec/test_fixtures/timing_order.rb[1:2] | passed | 2.0 seconds |
      TIMINGS
      File.write(File.join(dir, "runtimes-2.txt"), <<~TIMINGS)
        ./spec/test_fixtures/timing_order.rb[1:2] | passed | 0.5 seconds |
      TIMINGS

      stdout, _, status =
        run_turbospec("-w 1 --order runtime --timings '#{dir}/runtimes-*.txt' -f doc spec/test_fixtures/timing_order.rb")

      expect(status.exitstatus).to eq(0)
      one = stdout.index("timing example one")
      two = stdout.index("timing example two")
      three = stdout.index("timing example three")

      # one (1.0s) runs before two (2.0s overridden to 0.5s by the later
      # file) which runs before three (untimed). Without last-wins merging,
      # two would run first.
      expect(one).to be < two
      expect(two).to be < three
    end
  end

  it "handles multiple errors (test failure + after hook failure)" do
    stdout, stderr, status = run_turbospec("-w 1 spec/test_fixtures/multiple_errors.rb")
    expect(status.exitstatus).to eq(1)
    # Both examples should be reported as failures
    expect(stdout).to include("2 examples, 2 failures")
    # Should include both error messages
    expect(stdout).to include("Error in after hook")
    # Should not crash with serialization errors
    expect(stderr).not_to include("undefined method")
  end

  it "loads helper files via -r flag and runs hooks" do
    stdout, _stderr, status = run_turbospec("-w 1 -r ./spec/test_fixtures/require_helper.rb spec/test_fixtures/simple.rb")
    expect(status.exitstatus).to eq(0)
    # before_fork runs in master before spawning workers
    expect(stdout).to include("REQUIRE_HELPER: before_fork executed")
    # after_fork runs in each worker
    expect(stdout).to include("REQUIRE_HELPER: after_fork executed for worker 0")
  end

  it "kills hung examples after --timeout, reports them failed, and respawns the worker" do
    # -w 1 makes respawning load-bearing: without it the run would end with
    # zero workers and unran examples still in the queue.
    stdout, stderr, status = run_turbospec("-w 1 --timeout 2 spec/test_fixtures/hanging_example.rb")
    expect(status.exitstatus).to eq(1)
    expect(stdout).to include("6 examples, 1 failure")
    expect(stdout).to include("timeout")
    expect(stderr).to include("killing worker")
  end

  it "reports exceptions whose constructors require keyword arguments" do
    stdout, stderr, status = run_turbospec("-w 1 spec/test_fixtures/kwarg_exception.rb")
    expect(status.exitstatus).to eq(1)
    # Master must survive rehydrating an exception it can't construct directly
    expect(stderr).not_to include("wrong number of arguments")
    expect(stdout).to include("2 examples, 1 failure")
    expect(stdout).to include("KwargError")
    expect(stdout).to include("kwarg failure message")
  end

  it "preserves exception cause chain in failure output" do
    stdout, stderr, status = run_turbospec("-w 1 spec/test_fixtures/chained_exception.rb")
    expect(status.exitstatus).to eq(1)
    expect(stdout).to include("2 examples, 1 failure")
    # Should show the top-level error
    expect(stdout).to include("Top level error")
    # Should show the root cause (RSpec's formatter shows deepest cause, not intermediate ones)
    expect(stdout).to include("Caused by:")
    expect(stdout).to include("Root cause error")
    # Should not crash with serialization errors
    expect(stderr).not_to include("undefined method")
  end

  it "runs Rails app with database isolation across workers" do
    rails_app_path = File.expand_path('../fixtures/rails_app', __dir__)

    # Run turbospec from rails_app directory with its own bundle context
    Dir.chdir(rails_app_path) do
      # Set BUNDLE_GEMFILE to use rails_app's Gemfile, not the parent project's
      env = { 'BUNDLE_GEMFILE' => File.join(rails_app_path, 'Gemfile') }
      cmd = "bundle exec turbospec -w 3 -r spec/turbospec_helper.rb spec/database_isolation_spec.rb"
      stdout, stderr, status = Open3.capture3(env, cmd)

      expect(status.exitstatus).to eq(0)
      expect(stdout).to include("4 examples, 0 failures")

      # Extract all database names from the output
      database_names = stdout.scan(/using database: (.+)/).flatten
      expect(database_names.size).to eq(4)

      # Verify that we used at least 3 different databases (with 3 workers and 4 examples)
      # It's possible that one worker runs 2 examples, so we should have 3 unique databases
      unique_databases = database_names.uniq
      expect(unique_databases.size).to be >= 3

      # Verify database names follow the pattern test.sqlite3_N
      unique_databases.each do |db|
        expect(db).to match(/test\.sqlite3_\d+/)
      end

      # Should not have any ActiveRecord errors
      expect(stderr).not_to include("ActiveRecord")
      expect(stderr).not_to include("could not connect")
    end
  end

end
