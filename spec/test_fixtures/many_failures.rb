RSpec.describe "Many Failures" do
  it "fails first" do
    expect(1).to eq(2)
  end

  it "fails second" do
    expect(2).to eq(3)
  end

  it "fails third" do
    expect(3).to eq(4)
  end

  it "fails fourth" do
    expect(4).to eq(5)
  end

  it "fails fifth" do
    expect(5).to eq(6)
  end

  it "passes" do
    expect(true).to be true
  end
end
