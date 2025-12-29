RSpec.configure do |config|
  config.before(:suite) do
    puts "HOOK: before(:suite)"
    $stdout.flush
  end
  
  config.after(:suite) do
    puts "HOOK: after(:suite)"
    $stdout.flush
  end
end

RSpec.describe "Suite Hooks Spec" do
  it "example 1" do
    expect(true).to be true
  end
end
