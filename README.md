# Turbospec

A fast, pull-based parallel RSpec runner with minimal overhead.

## Features

- **Master-Worker Architecture**: A single master process manages the queue and aggregates results, while workers pull work items.
- **Example-Level Parallelism**: Distributes individual RSpec examples for optimal load balancing.
- **Zero Configuration**: Automatically detects and runs your specs in parallel.
- **ActiveRecord Support**: Built-in support for multiple test databases using `TEST_ENV_NUMBER`.

## Installation

Add this line to your application's Gemfile:

```ruby
group :development, :test do
  gem 'turbospec'
end
```

And then execute:

```bash
bundle install
```

## Usage

Simply run:

```bash
bundle exec turbospec
```

You can also pass RSpec arguments:

```bash
bundle exec turbospec spec/models --format documentation
```

### Options

| Option | Description |
|--------|-------------|
| `-w, --workers COUNT` | Number of worker processes (default: number of CPU cores) |
| `--fail-fast` | Stop the test suite on the first failure |
| `--only-failures` | Run only previously failed examples (requires `example_status_persistence_file_path` in RSpec config) |
| `--order ORDER` | Example ordering: `random` (default) or `runtime` (slowest first, for optimal parallelization) |
| `-p, --profile [COUNT]` | Show the slowest examples (default: 10) |
| `--shard=INDEX/TOTAL` | Run a specific shard of examples (1-based, e.g., `--shard=1/3` for first of 3 shards) |

All other options are passed through to RSpec.

## Limitations

- **No `before(:all)` / `after(:all)` hooks**: Because examples are distributed across workers individually, context-level hooks (`before(:all)`, `after(:all)`, `before(:context)`, `after(:context)`) are not supported. Use `before(:each)` / `after(:each)` instead, or `before(:suite)` / `after(:suite)` for one-time setup.
- **Examples run in isolation**: Each example may run in a different worker process. Avoid relying on shared state between examples.
- **Documentation formatter shows flat output**: Formatters like `--format documentation` won't display the nested group hierarchy correctly. This is a trade-off of example-level distribution: examples from the same group may run on different workers in any order, so group start/finish events aren't reported. The benefit is better load balancing—slow examples don't block a worker from picking up other work. If you need grouped output, consider using the default progress formatter and reviewing failures at the end.

## ActiveRecord Setup

Turbospec follows the convention established by `parallel_tests` and `flatware`. It sets the `TEST_ENV_NUMBER` environment variable for each worker:

- Worker 0: `TEST_ENV_NUMBER` is `""` (empty string)
- Worker 1: `TEST_ENV_NUMBER` is `"2"`
- Worker 2: `TEST_ENV_NUMBER` is `"3"`
- ... and so on.

### Database Configuration

Update your `config/database.yml` to use this environment variable:

```yaml
test:
  adapter: sqlite3
  database: storage/test<%= ENV['TEST_ENV_NUMBER'] %>.sqlite3
```

### Database Preparation

You need to create the databases for each worker before running tests:

```bash
# Example for 4 workers
bin/rails parallel:create[4]
bin/rails parallel:prepare[4]
```

### Faster Startup with ActiveRecord

By default, Rails boots for every worker process. You can optimize this by loading Rails once in the master process and then reconnecting in each forked worker. 

Create a `spec/turbospec_helper.rb` file in your project:

```ruby
# spec/turbospec_helper.rb

Turbospec.configure do |config|
  config.before_fork do
    # Load Rails in the master process
    require 'rails_helper'
  
    # Disconnect from the database before forking
    ActiveRecord::Base.connection_handler.clear_all_connections!
  end

  config.after_fork do |i|
    # Re-establish connection in the worker with the correct database
    ActiveRecord::TestDatabases.create_and_load_schema(i, env_name: ActiveRecord::ConnectionHandling::DEFAULT_ENV.call)
  end
end
```

Then run turbospec with the helper required:

```bash
bundle exec turbospec -r ./spec/turbospec_helper
```

## Architecture

Turbospec uses a pull-based model. The master process starts a UNIX socket server and forks worker processes. Workers connect to the master and request the next example to run. Once an example is finished, the worker sends the result back to the master as JSON and requests the next one.

This ensures that workers are always busy as long as there is work in the queue, regardless of how long individual examples take to run.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
