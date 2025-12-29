RSpec.describe "Syntax Error" do
  it "has invalid syntax" do
    # Missing end keyword - this will cause syntax error when loading
    def broken_method
      puts "This method is missing its end
  end
end
