module Turbospec
  class Configuration
    attr_accessor :before_fork_hook, :after_fork_hook

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
