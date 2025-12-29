RSpec.describe "Multiple Errors" do
  after do
    raise "Error in after hook"
  end

  it "fails in the test and also in after hook" do
    expect(1).to eq(2)
  end

  it "passes but fails in after hook" do
    expect(1).to eq(1)
  end
end
