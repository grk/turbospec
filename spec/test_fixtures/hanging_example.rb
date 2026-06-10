RSpec.describe "hanging example" do
  it "hangs" do
    sleep 60
  end

  5.times do |i|
    it "passes #{i}" do
      expect(true).to be(true)
    end
  end
end
