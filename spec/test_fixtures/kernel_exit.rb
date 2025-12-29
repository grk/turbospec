RSpec.describe "Kernel.exit" do
  it "calls exit (not exit!) which should be caught by RSpec" do
    if ENV['FORCE_KERNEL_EXIT']
      exit(1)
    end
    expect(true).to be true
  end

  it "should run normally" do
    expect(true).to be true
  end
end
