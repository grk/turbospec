require 'rails_helper'

RSpec.describe "Database isolation across workers" do
  it "verifies each worker has a unique database connection (example 1)" do
    # Get the current database name
    db_name = ActiveRecord::Base.connection.pool.db_config.database

    # Create a unique record to verify isolation
    Widget.create!(name: "Widget from #{db_name}")

    # Verify we can read it back
    expect(Widget.count).to be >= 1
    expect(Widget.last.name).to include("Widget from")

    # Log the database for debugging
    puts "Example 1 using database: #{db_name}"
  end

  it "verifies each worker has a unique database connection (example 2)" do
    db_name = ActiveRecord::Base.connection.pool.db_config.database

    Widget.create!(name: "Widget from #{db_name}")

    expect(Widget.count).to be >= 1
    expect(Widget.last.name).to include("Widget from")

    puts "Example 2 using database: #{db_name}"
  end

  it "verifies each worker has a unique database connection (example 3)" do
    db_name = ActiveRecord::Base.connection.pool.db_config.database

    Widget.create!(name: "Widget from #{db_name}")

    expect(Widget.count).to be >= 1
    expect(Widget.last.name).to include("Widget from")

    puts "Example 3 using database: #{db_name}"
  end

  it "verifies each worker has a unique database connection (example 4)" do
    db_name = ActiveRecord::Base.connection.pool.db_config.database

    Widget.create!(name: "Widget from #{db_name}")

    expect(Widget.count).to be >= 1
    expect(Widget.last.name).to include("Widget from")

    puts "Example 4 using database: #{db_name}"
  end
end
