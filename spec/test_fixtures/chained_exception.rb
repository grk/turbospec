RSpec.describe "Chained Exception" do
  it "fails with a chained exception" do
    begin
      begin
        raise "Root cause error"
      rescue => e
        raise "Wrapper error"
      end
    rescue => e
      raise "Top level error"
    end
  end

  it "passes" do
    expect(true).to be true
  end
end
