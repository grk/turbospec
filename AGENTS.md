# AGENTS

## Problem solving recipe

When working on a problem, follow the following pattern:

1. Understand the problem. Think about what the root cause is. Analyze possible solutions. If there are many valid solutions, propose them to the user.
2. Show the proposed solutions to the user and wait for acceptance to proceed.
3. If fixing a bug, make sure you have a failing test that reliably reproduces it before working on the resolution. Show that failing test to the user and wait for acceptance before proceeding.
4. If working on a feature, ask the user if the work should be test-first or code-first. Make sure it's covered by tests.

## Architecture

### Overview

Turbospec uses a master-worker architecture with Unix sockets for IPC (inter-process communication).

### Components

**Master Process (`lib/turbospec/master.rb`):**
- Creates a Unix domain socket server at `/tmp/turbospec_#{pid}.sock`
- Loads all RSpec examples once before forking (COW optimization)
- Forks N worker processes
- Maintains a queue of example indices to run
- Distributes work to workers via a pull-based model
- Aggregates results and reports to RSpec's reporter

**Worker Processes (`lib/turbospec/worker.rb`):**
- Each worker creates a client socket and connects to the master's server socket
- Inherits loaded examples from master via fork (copy-on-write)
- Requests work from master by sending `Protocol::READY`
- Receives work as `Protocol.work_command(index)` 
- Runs the example using `Runner.run_example(index, reporter)`
- Sends results back as JSON via `WorkerReporter`
- Continues requesting work until master responds with `Protocol::NONE`

**Runner (`lib/turbospec/runner.rb`):**
- Uses class instance variables (shared across fork boundary via COW)
- Loads all spec files and discovers examples
- Validates no `before(:all)` or `after(:all)` hooks are used
- Runs individual examples with proper RSpec group context

### Communication Protocol

The master and workers communicate using a simple text-based protocol:

1. Worker → Master: `"READY"` - requesting work
2. Master → Worker: `"WORK #{index}"` - here's an example to run
3. Worker → Master: JSON result - example completed with result
4. Master → Worker: `"NONE"` - no more work available
5. Worker → Master: `"DONE"` - worker shutting down

### Data Structures

**In Master (`run_loop`):**
- `sockets` - array of all socket connections (server + client sockets)
- `worker_to_example` - maps each worker's client socket to the example index it's currently running
- `@queue` - array of pending example indices to distribute
- `@examples` - all loaded RSpec examples (loaded before fork)

**Key Insight:** Each worker has its own client socket connection to the master. The variable `worker_to_example` maps socket objects (which represent worker connections) to example indices.

### Fork and Copy-On-Write (COW)

The architecture leverages Unix fork's copy-on-write behavior:

1. Master loads all examples into memory (class instance variables in Runner)
2. Master forks N worker processes
3. Workers inherit all loaded data without copying (COW)
4. Workers only read from the inherited data, so no memory duplication occurs
5. This makes startup fast and memory-efficient

### Environment Variables

Workers set `TEST_ENV_NUMBER` following parallel_tests convention:
- Worker 0: `TEST_ENV_NUMBER = ""`
- Worker 1: `TEST_ENV_NUMBER = "2"`
- Worker 2: `TEST_ENV_NUMBER = "3"`
- etc.

This allows databases and other resources to be isolated per worker.
