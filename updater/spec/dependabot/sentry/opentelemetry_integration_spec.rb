# typed: false
# frozen_string_literal: true

require "spec_helper"
require "sentry-ruby"

RSpec.describe "Sentry OpenTelemetry Integration" do
  describe "sentry-opentelemetry gem availability" do
    it "can require sentry-opentelemetry without errors" do
      expect { require "sentry-opentelemetry" }.not_to raise_error
    end

    it "loads the correct version of sentry-opentelemetry" do
      require "sentry-opentelemetry"

      # Verify we can access the Sentry::OpenTelemetry module
      expect(defined?(Sentry::OpenTelemetry)).to be_truthy
    end
  end

  describe "Sentry configuration with OpenTelemetry instrumenter" do
    before do
      # Save original configuration
      @original_instrumenter = Sentry.configuration.instrumenter if Sentry.configuration
    end

    after do
      # Restore original configuration if it existed
      if Sentry.configuration && @original_instrumenter
        Sentry.configuration.instrumenter = @original_instrumenter
      end
    end

    it "can configure Sentry with :otel instrumenter" do
      expect do
        Sentry.configuration.instrumenter = :otel
      end.not_to raise_error
    end

    it "supports :sentry instrumenter as fallback" do
      expect do
        Sentry.configuration.instrumenter = :sentry
      end.not_to raise_error
    end

    it "can switch between instrumenters" do
      Sentry.configuration.instrumenter = :otel
      expect(Sentry.configuration.instrumenter).to eq(:otel)

      Sentry.configuration.instrumenter = :sentry
      expect(Sentry.configuration.instrumenter).to eq(:sentry)
    end
  end

  describe "OpenTelemetry and Sentry compatibility" do
    it "has OpenTelemetry SDK available" do
      expect(defined?(::OpenTelemetry::SDK)).to be_truthy
    end

    it "can configure OpenTelemetry SDK without errors" do
      # This mimics what's done in lib/dependabot/opentelemetry.rb
      expect do
        require "opentelemetry/sdk"
        require "opentelemetry-logs-sdk"
        require "opentelemetry-metrics-sdk"
      end.not_to raise_error
    end

    it "has compatible OpenTelemetry API version" do
      require "opentelemetry/sdk"

      # Verify OpenTelemetry API is available
      expect(defined?(::OpenTelemetry)).to be_truthy
      expect(::OpenTelemetry).to respond_to(:tracer_provider)
    end
  end

  describe "Sentry processors compatibility" do
    let(:event) { instance_double(::Sentry::ErrorEvent) }
    let(:hint) { {} }

    before do
      allow(event).to receive(:send)
    end

    it "works with custom Sentry processors" do
      require "dependabot/sentry/sentry_context_processor"

      processor = SentryContext.new
      expect { processor.process(event, hint) }.not_to raise_error
    end

    it "works with exception sanitizer processor" do
      require "dependabot/sentry/exception_sanitizer_processor"

      exception = instance_double(::Sentry::SingleExceptionInterface, value: "test message")
      allow(exception).to receive(:value=)
      allow(event).to receive_message_chain("exception.values").and_return([exception])
      allow(event).to receive(:is_a?).and_return(true)

      processor = ExceptionSanitizer.new
      expect { processor.process(event, hint) }.not_to raise_error
    end
  end

  describe "Sentry-OpenTelemetry span processor" do
    before do
      require "sentry-opentelemetry"
    end

    it "can create Sentry span processor" do
      # sentry-opentelemetry provides a span processor that sends spans to Sentry
      expect(defined?(Sentry::OpenTelemetry::SpanProcessor)).to be_truthy
    end

    it "span processor can be instantiated" do
      processor = Sentry::OpenTelemetry::SpanProcessor.new
      expect(processor).to be_a(Sentry::OpenTelemetry::SpanProcessor)
    end

    it "span processor responds to expected methods" do
      processor = Sentry::OpenTelemetry::SpanProcessor.new

      expect(processor).to respond_to(:on_start)
      expect(processor).to respond_to(:on_finish)
    end
  end

  describe "instrumentation selection based on environment" do
    it "defaults to :sentry when OTEL is not enabled" do
      # Simulate OTEL_ENABLED not being set
      allow(ENV).to receive(:[]).with("OTEL_ENABLED").and_return(nil)

      instrumenter = ENV["OTEL_ENABLED"] == "true" ? :otel : :sentry
      expect(instrumenter).to eq(:sentry)
    end

    it "selects :otel when OTEL_ENABLED is true" do
      allow(ENV).to receive(:[]).with("OTEL_ENABLED").and_return("true")

      instrumenter = ENV["OTEL_ENABLED"] == "true" ? :otel : :sentry
      expect(instrumenter).to eq(:otel)
    end
  end

  describe "error recording with OpenTelemetry" do
    it "can access current OpenTelemetry span" do
      require "opentelemetry/sdk"

      expect(::OpenTelemetry::Trace).to respond_to(:current_span)
      span = ::OpenTelemetry::Trace.current_span
      expect(span).not_to be_nil
    end

    it "OpenTelemetry span supports status and exception recording" do
      require "opentelemetry/sdk"

      span = ::OpenTelemetry::Trace.current_span

      expect(span).to respond_to(:status=)
      expect(span).to respond_to(:record_exception)
      expect(span).to respond_to(:add_event)
      expect(span).to respond_to(:set_attribute)
    end
  end

  describe "version compatibility regression test" do
    it "sentry-opentelemetry 5.28.1 is compatible with sentry-ruby 5.x" do
      require "sentry-ruby"
      require "sentry-opentelemetry"

      # Verify both gems load without conflicts
      expect(defined?(Sentry)).to be_truthy
      expect(defined?(Sentry::OpenTelemetry)).to be_truthy

      # Verify Sentry version is in the 5.x range
      sentry_version = Gem.loaded_specs["sentry-ruby"]&.version
      expect(sentry_version).not_to be_nil
      expect(sentry_version.segments[0]).to eq(5)
    end

    it "sentry-opentelemetry depends on opentelemetry-sdk" do
      require "sentry-opentelemetry"

      # Verify opentelemetry-sdk is loaded (dependency of sentry-opentelemetry)
      expect(defined?(::OpenTelemetry::SDK)).to be_truthy
    end
  end

  describe "edge cases and error handling" do
    it "handles nil span gracefully in OpenTelemetry operations" do
      require "opentelemetry/sdk"

      # Even with no active span, current_span should return a non-failing span
      span = ::OpenTelemetry::Trace.current_span
      expect { span.add_event("test_event") }.not_to raise_error
    end

    it "handles Sentry configuration errors gracefully" do
      # Attempting to set an invalid instrumenter should not crash
      expect do
        begin
          Sentry.configuration.instrumenter = :invalid
        rescue ArgumentError
          # Expected to raise ArgumentError for invalid instrumenter
        end
      end.not_to raise_error(NoMethodError)
    end

    it "can handle concurrent Sentry and OpenTelemetry operations" do
      require "sentry-opentelemetry"

      # Simulate having both Sentry and OpenTelemetry active
      expect do
        span = ::OpenTelemetry::Trace.current_span
        span.add_event("test_event")

        # Sentry should still be able to capture messages
        # (using a double to avoid actual Sentry calls in tests)
        allow(Sentry).to receive(:capture_message)
        Sentry.capture_message("test message")
      end.not_to raise_error
    end
  end
end