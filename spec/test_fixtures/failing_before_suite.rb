RSpec.configure do |config|
  config.before(:suite) do
    raise "Setup failed in before(:suite)"
  end
end

RSpec.describe "Should Never Run" do
  it "should not execute because before(:suite) failed" do
    expect(true).to be true
  end
end
