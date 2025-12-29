require "rspec/core"

module Turbospec
  class Runner
    def self.load_examples(args)
      # Configure RSpec
      options = RSpec::Core::ConfigurationOptions.new(args)
      options.configure(RSpec.configuration)

      if RSpec.configuration.files_to_run.empty?
        RSpec.configuration.files_or_directories_to_run = [RSpec.configuration.default_path]
      end

      # Load files
      RSpec.configuration.load_spec_files
      RSpec.world.announce_filters

      # If there's an error loading spec files, exit immediately.
      if RSpec.world.wants_to_quit
        exit(RSpec.configuration.failure_exit_code)
      end

      # Validate that no before/after(:all) hooks are used.
      # We check the hooks repository directly since RSpec doesn't provide a public API for this.
      RSpec.world.ordered_example_groups.each do |group|
        group.descendants.each do |descendant|
          hooks = descendant.hooks
          before_context = hooks.instance_variable_get(:@before_context_hooks)
          after_context = hooks.instance_variable_get(:@after_context_hooks)

          has_context_hooks = (before_context && before_context.items_and_filters.any?) ||
                              (after_context && after_context.items_and_filters.any?)

          if has_context_hooks
            raise "turbospec does not support before/after(:all) or before/after(:context) hooks.\n" \
                  "Use before(:each)/after(:each) for per-example setup, or " \
                  "before(:suite)/after(:suite) for one-time setup.\n" \
                  "Found in #{descendant.description} at #{descendant.metadata[:file_path]}"
          end
        end
      end

      # Discover examples from all groups and their descendants
      all_groups = RSpec.world.ordered_example_groups.flat_map { |g| [g, *g.descendants] }
      @examples = all_groups.flat_map(&:filtered_examples).uniq

      # Prepare base filtering hash once (all groups -> empty).
      # This avoids rebuilding it on every run_example call.
      @base_filtered = {}
      RSpec.world.all_example_groups.each { |g| @base_filtered[g] = [] }

      # Cache original filtered state for restoration after each example run.
      @original_filtered = RSpec.world.filtered_examples.dup

      # Precompute root groups for each example to avoid repeated lookups.
      @root_groups = @examples.map do |ex|
        group = ex.example_group
        group.parent_groups.last || group
      end

      @examples
    end

    def self.examples
      @examples
    end

    def self.run_example(index, reporter)
      example = @examples[index]
      group = example.example_group

      # We use RSpec's own group.run to ensure all setup logic (including
      # fixtures and around hooks) is correctly triggered for the example.
      #
      # FIX: We must run the ROOT example group, not the immediate one.
      # RSpec-Rails depends on execution starting from the top-level group
      # to correctly set up helper modules and context.
      #
      # CRITICAL: We must strictly filter the entire RSpec.world to only
      # run THIS specific example. If we don't, sibling groups/examples
      # in the root_group hierarchy will also run, causing an explosion
      # of test execution (N^2 behavior).

      begin
        # Use precomputed base_filtered (shallow dup is safe since we
        # overwrite the one entry we care about).
        new_filtered = @base_filtered.dup
        new_filtered[group] = [example]

        RSpec.world.filtered_examples.replace(new_filtered)
        @root_groups[index].run(reporter)
      ensure
        RSpec.world.filtered_examples.replace(@original_filtered)
      end
    end
  end
end
