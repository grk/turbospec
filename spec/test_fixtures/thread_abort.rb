RSpec.describe "Thread with abort_on_exception" do
  it "spawns a thread that raises an exception" do
    thread = Thread.new do
      sleep 0.1
      raise "Thread explosion!"
    end
    thread.abort_on_exception = true

    # This should pass, but the thread will kill the process
    expect(true).to be true

    # Give the thread time to explode
    sleep 0.2
  end

  it "should not run because previous test killed the worker" do
    expect(true).to be true
  end
end
