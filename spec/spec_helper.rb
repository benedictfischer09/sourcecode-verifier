require 'bundler/setup'
require 'sourcecode_verifier'
require 'webmock/rspec'
require 'tmpdir'

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Disable colorization during tests
  config.before(:suite) do
    SourcecodeVerifier::Colorizer.enabled = false
  end

  # Configure test tags
  config.filter_run_excluding :integration unless ENV['INTEGRATION_TESTS'] == 'true'
  
  # Allow real connections to localhost for testing
  WebMock.disable_net_connect!(allow_localhost: true)
  
  config.before(:each) do
    WebMock.reset!
  end
  
  # For integration tests, allow real network connections
  config.before(:each, :integration) do
    WebMock.allow_net_connect!
  end
  
  config.after(:each, :integration) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end