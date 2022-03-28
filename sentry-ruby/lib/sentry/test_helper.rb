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
      copied_config.enabled_environments << copied_config.environment unless copied_config.enabled_environments.include?(copied_config.environment)
      # disble async event sending
      copied_config.background_worker_threads = 0

      # user can overwrite some of the configs, with a few exceptions like:
      # - capture_exception_frame_locals
      # - auto_session_tracking
      block&.call(copied_config)

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

    def extract_sentry_exceptions(event)
      if event.exception
        event.exception.instance_variable_get(:@values)
      else
        []
      end
    end
  end
end

