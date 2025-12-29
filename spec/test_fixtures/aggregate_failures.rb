RSpec.describe "Aggregate Failures" do
  it "has multiple failures in aggregate_failures block", :aggregate_failures do
    expect(1).to eq(2)
    expect("foo").to eq("bar")
    expect([1, 2, 3]).to include(4)
  end

  it "passes normally" do
    expect(1).to eq(1)
  end
end
