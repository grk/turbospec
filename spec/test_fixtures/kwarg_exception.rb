class KwargError < StandardError
  def initialize(message:)
    super(message)
  end
end

RSpec.describe "kwarg exception" do
  it "fails with an exception whose constructor requires keywords" do
    raise KwargError.new(message: "kwarg failure message")
  end

  it "passes" do
    expect(1).to eq(1)
  end
end
