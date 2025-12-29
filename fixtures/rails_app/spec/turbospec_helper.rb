# Turbospec configuration for Rails fixture app
Turbospec.configure do |config|
  config.before_fork do
    # Load Rails in the master process
    require 'rails_helper'
  end

  config.after_fork do |i|
    # Re-establish connection in the worker with the correct database
    ActiveRecord::TestDatabases.create_and_load_schema(i, env_name: ActiveRecord::ConnectionHandling::DEFAULT_ENV.call)
  end
end
