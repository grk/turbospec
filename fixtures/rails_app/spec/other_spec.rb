require "rails_helper"

RSpec.describe "OtherSpec" do
  fixtures :asics

  it "works" do
    expect(asics(:high_power)).to be_a(Asic)
  end
end
