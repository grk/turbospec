RSpec.describe "Disallowed Hooks Spec" do
  before(:all) do
    puts "HOOK: before(:all)"
  end

  it "example 1" do
    expect(true).to be true
  end
end
