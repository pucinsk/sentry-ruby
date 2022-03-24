require "bundler/setup"
require "debug" if RUBY_VERSION.to_f >= 2.6
require "pry"
require "timecop"
require "simplecov"
require "rspec/retry"
require "fakeredis/rspec"

SimpleCov.start do
  project_name "sentry-ruby"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end

if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

require "sentry-ruby"

module Sentry
  module TestHelper
    DUMMY_DSN = 'http://12345:67890@sentry.localdomain/sentry/42'

    def setup_sentry_test(&block)
      raise "please make sure the SDK is initialized for testing" unless Sentry.initialized?
      copied_config = Sentry.configuration.dup
      # configure dummy DSN, so the events will not be sent to the actual service
      copied_config.dsn = DUMMY_DSN
      # set transport to DummyTransport, so we can easily intercept the captured events
      copied_config.transport.transport_class = Sentry::DummyTransport
      # make sure SDK allows sending under the current environment
      copied_config.enabled_environments << copied_config.environment

      # user can overwrite some of the configs, with a few exceptions like:
      # - capture_exception_frame_locals
      # - auto_session_tracking
      block.call(copied_config)

      test_client = Sentry::Client.new(copied_config)
      Sentry.get_current_hub.bind_client(test_client)
    end

    def teardown_sentry_test
      return unless Sentry.initialized?

      sentry_transport.events = []
      sentry_transport.envelopes = []
    end

    def sentry_transport
      Sentry.get_current_client.transport
    end

    def sentry_events
      sentry_transport.events
    end

    def sentry_envelopes
      sentry_transport.envelopes
    end

    def last_sentry_event
      sentry_events.last
    end
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.include(Sentry::TestHelper)

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :each do
    # Make sure we reset the env in case something leaks in
    ENV.delete('SENTRY_DSN')
    ENV.delete('SENTRY_CURRENT_ENV')
    ENV.delete('SENTRY_ENVIRONMENT')
    ENV.delete('SENTRY_RELEASE')
    ENV.delete('RAILS_ENV')
    ENV.delete('RACK_ENV')
  end

  config.before(:each, rack: true) do
    skip("skip rack related tests") unless defined?(Rack)
  end

  RSpec::Matchers.define :have_recorded_lost_event do |reason, type|
    match do |transport|
      expect(transport.discarded_events[[reason, type]]).to be > 0
    end
  end
end

def build_exception_with_cause(cause = "exception a")
  begin
    raise cause
  rescue
    raise "exception b"
  end
rescue RuntimeError => e
  e
end

def build_exception_with_two_causes
  begin
    begin
      raise "exception a"
    rescue
      raise "exception b"
    end
  rescue
    raise "exception c"
  end
rescue RuntimeError => e
  e
end

def build_exception_with_recursive_cause
  backtrace = []

  exception = double("Exception")
  allow(exception).to receive(:cause).and_return(exception)
  allow(exception).to receive(:message).and_return("example")
  allow(exception).to receive(:backtrace).and_return(backtrace)
  exception
end

def perform_basic_setup
  Sentry.init do |config|
    config.logger = Logger.new(nil)
    config.dsn = Sentry::TestHelper::DUMMY_DSN
    config.transport.transport_class = Sentry::DummyTransport
    # so the events will be sent synchronously for testing
    config.background_worker_threads = 0
    yield(config) if block_given?
  end
end
