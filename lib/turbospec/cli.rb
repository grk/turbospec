require 'optparse'
require 'etc'

module Turbospec
  class CLI
    def run(argv)
      # Add standard directories to load path, similar to how 'rspec' command does
      $LOAD_PATH.unshift(Dir.pwd) unless $LOAD_PATH.include?(Dir.pwd)
      $LOAD_PATH.unshift(File.join(Dir.pwd, "spec")) if File.directory?("spec") && !$LOAD_PATH.include?(File.join(Dir.pwd, "spec"))
      $LOAD_PATH.unshift(File.join(Dir.pwd, "lib")) if File.directory?("lib") && !$LOAD_PATH.include?(File.join(Dir.pwd, "lib"))

      options = { workers: Etc.nprocessors, fail_fast: false, only_failures: false, order: nil, profile: nil, shard: nil }

      # Manual parsing to preserve order of remaining arguments for RSpec.
      # OptionParser's rescue-retry loop can scramble flags and their values.
      rspec_args = []
      i = 0
      while i < argv.size
        arg = argv[i]
        case arg
        when "-w", "--workers"
          i += 1
          options[:workers] = argv[i].to_i
        when /\A--workers=(.*)\z/
          options[:workers] = $1.to_i
        when "--fail-fast"
          options[:fail_fast] = true
        when "--only-failures"
          options[:only_failures] = true
        when "--order"
          i += 1
          options[:order] = argv[i]
        when /\A--order=(.*)\z/
          options[:order] = $1
        when "-p", "--profile"
          i += 1
          options[:profile] = argv[i].to_i
        when /\A--profile=(.*)\z/
          options[:profile] = $1.to_i
        when /\A--profile\z/
          options[:profile] = 10  # Default to top 10
        when /\A--shard=(\d+)\/(\d+)\z/
          # Convert 1-based input to 0-based internal index
          options[:shard] = { index: $1.to_i - 1, total: $2.to_i }
        when "-h", "--help"
          puts "Usage: prspec [options] [rspec-options]"
          puts "    -w, --workers COUNT              Number of workers"
          puts "        --fail-fast                  Stop suite on first failure"
          puts "        --only-failures              Run only previously failed examples"
          puts "        --order ORDER                Example ordering: random (default) or runtime"
          puts "    -p, --profile [COUNT]            Show slowest examples (default: 10)"
          puts "        --shard=INDEX/TOTAL          Run shard INDEX of TOTAL (e.g., --shard=1/3)"
          puts "    -h, --help                       Prints this help"
          exit
        else
          rspec_args << arg
        end
        i += 1
      end

      require_relative "master"
      require_relative "runner"
      success = Master.new(options, rspec_args).run
      exit(success ? 0 : 1)
    end
  end
end
