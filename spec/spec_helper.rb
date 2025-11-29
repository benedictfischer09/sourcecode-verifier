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

  # Allow real connections to localhost for testing
  WebMock.disable_net_connect!(allow_localhost: true)
  
  config.before(:each) do
    WebMock.reset!
  end
end