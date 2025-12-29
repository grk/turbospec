RSpec.describe "Slow Spec" do
  it "sleeps for 5 seconds" do
    sleep 5
    expect(1).to eq(1)
  end
end
