RSpec.shared_examples "a shared example" do |value|
  it "works with shared examples (value: #{value})" do
    expect(value).to be_truthy
  end
end

RSpec.describe "Edge Cases" do
  it "is pending" do
    pending "not implemented"
    expect(false).to be true
  end

  it "is skipped", skip: "because I said so" do
    expect(false).to be true
  end

  it_behaves_like "a shared example", true
  it_behaves_like "a shared example", "yes"

  it "prints a lot of output" do
    100.times { puts "This is some output from a test that prints a lot." }
    expect(true).to be true
  end

  it "fails with a complex exception" do
    # Simulate a nested error
    begin
      begin
        raise "Inner Error"
      rescue => e
        raise "Outer Error: #{e.message}"
      end
    rescue => e
      raise e
    end
  end

  it "works normally" do
    expect(1+1).to eq(2)
  end

  # Special case for worker crash simulation if we want to test it
  if ENV['CRASH_WORKER']
    it "crashes the worker" do
      Process.exit!(1)
    end
  end
end
