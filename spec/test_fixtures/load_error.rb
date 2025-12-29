# This spec file has a load error - requiring a non-existent file
require 'this_file_does_not_exist'

RSpec.describe "Should Never Run" do
  it "should not execute because of load error" do
    expect(true).to be true
  end
end
