RSpec.configure do |config|
  config.after(:suite) do
    raise "Cleanup failed in after(:suite)"
  end
end

RSpec.describe "Runs But Cleanup Fails" do
  it "runs successfully" do
    expect(true).to be true
  end

  it "also runs successfully" do
    expect(1 + 1).to eq(2)
  end
end
