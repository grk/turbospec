RSpec.describe "Worker Exit Scenarios" do
  it "passes normally" do
    expect(1 + 1).to eq(2)
  end

  it "calls exit! which kills the worker process" do
    # This simulates a worker crash - exit! bypasses RSpec's exception handling
    if ENV['FORCE_WORKER_EXIT']
      Process.exit!(1)
    end
    expect(true).to be true
  end

  it "should not run if previous test killed the worker" do
    expect(true).to be true
  end
end
