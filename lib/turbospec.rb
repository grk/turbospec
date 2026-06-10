module Turbospec
  class Configuration
    attr_accessor :before_fork_hook, :after_fork_hook

    # When true, before/after(:context) hooks don't abort the run; they
    # execute once per example (via group.run) instead of once per group.
    # Safe only for idempotent hooks, e.g. rubocop's CopHelper plugin setup.
    attr_accessor :allow_context_hooks

    def before_fork(&block)
      @before_fork_hook = block
    end

    def after_fork(&block)
      @after_fork_hook = block
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield configuration
  end

  class Error < StandardError; end
end
