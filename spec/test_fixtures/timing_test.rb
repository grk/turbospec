RSpec.describe "Timing Test" do
  it "fast test" do
    sleep 0.01
    expect(true).to be true
  end

  it "slow test" do
    sleep 0.1
    expect(true).to be true
  end

  it "medium test" do
    sleep 0.05
    expect(true).to be true
  end
end
