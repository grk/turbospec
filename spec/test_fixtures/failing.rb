RSpec.describe "Failing Spec" do
  it "fails" do
    expect(1).to eq(2)
  end

  it "passes" do
    expect(1).to eq(1)
  end
end
