Turbospec.configure do |config|
  config.after_fork do |worker_index|
    puts "Custom Worker Hook: index=#{worker_index} TEST_ENV_NUMBER=#{ENV['TEST_ENV_NUMBER']}"
  end
end
