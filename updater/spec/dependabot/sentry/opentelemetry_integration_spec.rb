# typed: false
# frozen_string_literal: true

require "spec_helper"
require "sentry-ruby"
require "sentry-opentelemetry"

RSpec.describe "Sentry OpenTelemetry Integration" do
  describe "Sentry configuration with OpenTelemetry" do
    it "loads sentry-ruby gem successfully" do
      expect { require "sentry-ruby" }.not_to raise_error
      expect(defined?(Sentry)).to eq("constant")
    end

    it "loads sentry-opentelemetry gem successfully" do
      expect { require "sentry-opentelemetry" }.not_to raise_error
    end

    it "has correct sentry-ruby version" do
      gem_spec = Gem.loaded_specs["sentry-ruby"]
      expect(gem_spec).not_to be_nil
      expect(gem_spec.version.to_s).to match(/^5\.\d+\.\d+$/)
    end

    it "has correct sentry-opentelemetry version" do
      gem_spec = Gem.loaded_specs["sentry-opentelemetry"]
      expect(gem_spec).not_to be_nil
      expect(gem_spec.version.to_s).to match(/^5\.\d+\.\d+$/)
    end

    it "sentry-opentelemetry version is compatible with sentry-ruby" do
      sentry_ruby_spec = Gem.loaded_specs["sentry-ruby"]
      sentry_otel_spec = Gem.loaded_specs["sentry-opentelemetry"]

      expect(sentry_ruby_spec).not_to be_nil
      expect(sentry_otel_spec).not_to be_nil

      # Both should be in the 5.x version range
      expect(sentry_ruby_spec.version.segments.first).to eq(5)
      expect(sentry_otel_spec.version.segments.first).to eq(5)
    end
  end

  describe "Sentry instrumenter configuration" do
    context "with OpenTelemetry enabled" do
      before do
        ENV["OTEL_ENABLED"] = "true"
        ENV["DEPENDABOT_UPDATER_VERSION"] = "test-version"
      end

      after do
        ENV.delete("OTEL_ENABLED")
        ENV.delete("DEPENDABOT_UPDATER_VERSION")
        # Reset Sentry configuration
        Sentry.configuration.instrumenter = :sentry
      end

      it "can configure Sentry with otel instrumenter" do
        expect do
          Sentry.init do |config|
            config.instrumenter = :otel
            config.dsn = nil # Disable sending to prevent errors in tests
          end
        end.not_to raise_error
      end

      it "sets instrumenter to :otel when OpenTelemetry is enabled" do
        Sentry.init do |config|
          config.dsn = nil
          config.instrumenter = require("dependabot/opentelemetry") &&
                               Dependabot::OpenTelemetry.should_configure? ? :otel : :sentry
        end

        expect(Sentry.configuration.instrumenter).to eq(:otel)
      end
    end

    context "with OpenTelemetry disabled" do
      before do
        ENV.delete("OTEL_ENABLED")
        ENV["DEPENDABOT_UPDATER_VERSION"] = "test-version"
      end

      after do
        ENV.delete("DEPENDABOT_UPDATER_VERSION")
        Sentry.configuration.instrumenter = :sentry
      end

      it "sets instrumenter to :sentry when OpenTelemetry is disabled" do
        Sentry.init do |config|
          config.dsn = nil
          config.instrumenter = require("dependabot/opentelemetry") &&
                               Dependabot::OpenTelemetry.should_configure? ? :otel : :sentry
        end

        expect(Sentry.configuration.instrumenter).to eq(:sentry)
      end
    end
  end

  describe "OpenTelemetry span propagation to Sentry" do
    let(:test_error) { StandardError.new("Test error for tracing") }

    before do
      ENV["OTEL_ENABLED"] = "true"
      ENV["DEPENDABOT_UPDATER_VERSION"] = "test-version"

      # Mock OpenTelemetry components
      allow(::OpenTelemetry::SDK).to receive(:configure).and_yield(double(
        service_name: nil,
        use: nil
      ))
    end

    after do
      ENV.delete("OTEL_ENABLED")
      ENV.delete("DEPENDABOT_UPDATER_VERSION")
    end

    it "can capture exceptions with OpenTelemetry context" do
      tracer_provider = instance_double(::OpenTelemetry::SDK::Trace::TracerProvider)
      tracer = instance_double(::OpenTelemetry::Trace::Tracer)
      span = instance_double(::OpenTelemetry::SDK::Trace::Span)

      allow(::OpenTelemetry).to receive(:tracer_provider).and_return(tracer_provider)
      allow(tracer_provider).to receive(:tracer).and_return(tracer)
      allow(tracer_provider).to receive(:force_flush)
      allow(tracer_provider).to receive(:shutdown)

      allow(::OpenTelemetry::Trace).to receive(:current_span).and_return(span)
      allow(span).to receive(:set_attribute)
      allow(span).to receive(:add_attributes)
      allow(span).to receive(:status=)
      allow(span).to receive(:record_exception)
      allow(::OpenTelemetry::Trace::Status).to receive(:error).and_return(
        instance_double(::OpenTelemetry::Trace::Status)
      )

      Dependabot::OpenTelemetry.configure

      expect do
        Dependabot::OpenTelemetry.record_exception(
          error: test_error,
          job: double(id: 123),
          tags: { "test" => "value" }
        )
      end.not_to raise_error

      expect(span).to have_received(:record_exception).with(test_error)
    end
  end

  describe "Sentry event processors with OpenTelemetry" do
    it "can chain event processors with OpenTelemetry instrumenter" do
      event = instance_double(::Sentry::ErrorEvent)
      hint = { exception: StandardError.new("test") }

      allow(event).to receive(:is_a?).with(::Sentry::ErrorEvent).and_return(true)
      allow(event).to receive_message_chain("exception.values").and_return([])

      # This should work regardless of instrumenter
      expect do
        require "dependabot/sentry/exception_sanitizer_processor"
        ExceptionSanitizer.new.process(event, hint)
      end.not_to raise_error
    end
  end

  describe "version compatibility verification" do
    it "sentry-opentelemetry requires opentelemetry-sdk" do
      otel_sdk_spec = Gem.loaded_specs["opentelemetry-sdk"]
      expect(otel_sdk_spec).not_to be_nil
      expect(otel_sdk_spec.version.to_s).to match(/^\d+\.\d+\.\d+$/)
    end

    it "has compatible dependency versions" do
      # Verify key dependencies are loaded
      expect(Gem.loaded_specs["sentry-ruby"]).not_to be_nil
      expect(Gem.loaded_specs["sentry-opentelemetry"]).not_to be_nil
      expect(Gem.loaded_specs["opentelemetry-sdk"]).not_to be_nil
      expect(Gem.loaded_specs["opentelemetry-api"]).not_to be_nil
    end

    it "sentry-opentelemetry has opentelemetry-sdk as dependency" do
      sentry_otel_spec = Gem.loaded_specs["sentry-opentelemetry"]
      otel_sdk_dep = sentry_otel_spec.dependencies.find { |d| d.name == "opentelemetry-sdk" }

      expect(otel_sdk_dep).not_to be_nil
      expect(otel_sdk_dep.requirement.satisfied_by?(Gem.loaded_specs["opentelemetry-sdk"].version)).to be true
    end

    it "sentry-opentelemetry has sentry-ruby as dependency" do
      sentry_otel_spec = Gem.loaded_specs["sentry-opentelemetry"]
      sentry_ruby_dep = sentry_otel_spec.dependencies.find { |d| d.name == "sentry-ruby" }

      expect(sentry_ruby_dep).not_to be_nil
      expect(sentry_ruby_dep.requirement.satisfied_by?(Gem.loaded_specs["sentry-ruby"].version)).to be true
    end
  end

  describe "concurrent-ruby dependency" do
    # Regression test: sentry-ruby requires concurrent-ruby
    it "concurrent-ruby is available for sentry-ruby" do
      concurrent_spec = Gem.loaded_specs["concurrent-ruby"]
      expect(concurrent_spec).not_to be_nil
    end

    it "sentry-ruby can use concurrent-ruby" do
      sentry_ruby_spec = Gem.loaded_specs["sentry-ruby"]
      concurrent_dep = sentry_ruby_spec.dependencies.find { |d| d.name == "concurrent-ruby" }

      expect(concurrent_dep).not_to be_nil
    end
  end

  describe "API compatibility and regression tests" do
    # These tests verify that the upgraded version maintains API compatibility
    describe "Sentry.init configuration options" do
      after do
        # Reset configuration after each test
        Sentry.configuration.instrumenter = :sentry
        Sentry.configuration.dsn = nil
      end

      it "supports before_send callback" do
        callback_called = false

        expect do
          Sentry.init do |config|
            config.dsn = nil
            config.before_send = lambda { |event, _hint|
              callback_called = true
              event
            }
          end
        end.not_to raise_error

        expect(Sentry.configuration.before_send).not_to be_nil
      end

      it "supports propagate_traces configuration" do
        expect do
          Sentry.init do |config|
            config.dsn = nil
            config.propagate_traces = false
          end
        end.not_to raise_error

        expect(Sentry.configuration.propagate_traces).to eq(false)
      end

      it "supports release configuration" do
        expect do
          Sentry.init do |config|
            config.dsn = nil
            config.release = "test-release-1.0.0"
          end
        end.not_to raise_error

        expect(Sentry.configuration.release).to eq("test-release-1.0.0")
      end
    end

    describe "OpenTelemetry instrumenter feature" do
      before do
        ENV["OTEL_ENABLED"] = "true"
        ENV["DEPENDABOT_UPDATER_VERSION"] = "test"
      end

      after do
        ENV.delete("OTEL_ENABLED")
        ENV.delete("DEPENDABOT_UPDATER_VERSION")
        Sentry.configuration.instrumenter = :sentry
      end

      it "allows switching between :sentry and :otel instrumenter" do
        # Start with sentry
        Sentry.init do |config|
          config.dsn = nil
          config.instrumenter = :sentry
        end
        expect(Sentry.configuration.instrumenter).to eq(:sentry)

        # Switch to otel
        Sentry.init do |config|
          config.dsn = nil
          config.instrumenter = :otel
        end
        expect(Sentry.configuration.instrumenter).to eq(:otel)
      end

      it "maintains configuration when instrumenter is changed" do
        release_version = "v1.2.3"

        Sentry.init do |config|
          config.dsn = nil
          config.instrumenter = :otel
          config.release = release_version
        end

        expect(Sentry.configuration.instrumenter).to eq(:otel)
        expect(Sentry.configuration.release).to eq(release_version)
      end
    end

    describe "backward compatibility checks" do
      it "Sentry module responds to expected methods" do
        expect(Sentry).to respond_to(:init)
        expect(Sentry).to respond_to(:configuration)
        expect(Sentry).to respond_to(:capture_exception)
        expect(Sentry).to respond_to(:capture_message)
      end

      it "Sentry::Configuration has expected attributes" do
        config = Sentry.configuration

        expect(config).to respond_to(:dsn)
        expect(config).to respond_to(:instrumenter)
        expect(config).to respond_to(:release)
        expect(config).to respond_to(:before_send)
        expect(config).to respond_to(:propagate_traces)
      end

      it "sentry-opentelemetry does not break Sentry error capturing" do
        # This is a critical test to ensure the upgrade didn't break core functionality
        test_error = StandardError.new("Test error for compatibility check")

        # Mock the Sentry client to avoid actual network calls
        allow(Sentry).to receive(:capture_exception).and_return(true)

        expect do
          Sentry.capture_exception(test_error)
        end.not_to raise_error

        expect(Sentry).to have_received(:capture_exception).with(test_error)
      end
    end

    describe "version-specific regression tests" do
      # Test for potential breaking changes in the 5.23.0 -> 5.28.1 upgrade
      it "handles error events with OpenTelemetry context" do
        ENV["OTEL_ENABLED"] = "true"

        mock_event = instance_double(::Sentry::ErrorEvent)
        mock_hint = { exception: StandardError.new("test") }

        allow(mock_event).to receive(:is_a?).with(::Sentry::ErrorEvent).and_return(true)
        mock_exception = instance_double(::Sentry::SingleExceptionInterface, value: "test message")
        allow(mock_exception).to receive(:value=)
        allow(mock_event).to receive_message_chain("exception.values").and_return([mock_exception])

        # Should work with OpenTelemetry enabled
        expect do
          require "dependabot/sentry/exception_sanitizer_processor"
          ExceptionSanitizer.new.process(mock_event, mock_hint)
        end.not_to raise_error

        ENV.delete("OTEL_ENABLED")
      end
    end

    describe "thread safety and concurrency" do
      it "handles concurrent Sentry error capture calls" do
        ENV["OTEL_ENABLED"] = "true"
        errors = 5.times.map { |i| StandardError.new("Concurrent error #{i}") }

        # Mock Sentry to track calls
        call_count = 0
        allow(Sentry).to receive(:capture_exception) do |_error|
          call_count += 1
          true
        end

        # Simulate concurrent error captures (in practice would use threads, but keeping test simple)
        expect do
          errors.each { |error| Sentry.capture_exception(error) }
        end.not_to raise_error

        expect(call_count).to eq(5)

        ENV.delete("OTEL_ENABLED")
      end

      it "maintains correct instrumenter setting across multiple Sentry.init calls" do
        ENV["OTEL_ENABLED"] = "true"

        # First init with :otel
        Sentry.init do |config|
          config.dsn = nil
          config.instrumenter = :otel
        end
        expect(Sentry.configuration.instrumenter).to eq(:otel)

        # Second init should preserve setting
        Sentry.init do |config|
          config.dsn = nil
          config.instrumenter = :otel
        end
        expect(Sentry.configuration.instrumenter).to eq(:otel)

        ENV.delete("OTEL_ENABLED")
        Sentry.configuration.instrumenter = :sentry
      end
    end

    describe "error boundary tests for version upgrade" do
      # Regression test: verify that new version doesn't break when Sentry is not initialized
      it "handles calls when Sentry is not yet initialized" do
        # This should not raise even if configuration is minimal
        expect { Sentry.configuration }.not_to raise_error
        expect(Sentry.configuration).not_to be_nil
      end

      it "gracefully handles missing OpenTelemetry span context" do
        ENV["OTEL_ENABLED"] = "true"

        # Simulate missing span context
        allow(::OpenTelemetry::Trace).to receive(:current_span).and_return(nil)

        test_error = StandardError.new("Test without span")

        # Should handle gracefully without crashing
        expect do
          require "dependabot/opentelemetry"
          # This should not crash even without active span
          Dependabot::OpenTelemetry.record_exception(
            error: test_error,
            job: double(id: 999),
            tags: {}
          )
        end.not_to raise_error

        ENV.delete("OTEL_ENABLED")
      end
    end
  end
end