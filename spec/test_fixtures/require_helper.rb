Turbospec.configure do |config|
  config.before_fork do
    puts "REQUIRE_HELPER: before_fork executed"
  end

  config.after_fork do |worker_index|
    puts "REQUIRE_HELPER: after_fork executed for worker #{worker_index}"
  end
end
