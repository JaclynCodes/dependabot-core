# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/opentelemetry"

RSpec.describe Dependabot::OpenTelemetry do
  describe ".should_configure?" do
    context "when OTEL_ENABLED is true" do
      before { ENV["OTEL_ENABLED"] = "true" }
      after { ENV.delete("OTEL_ENABLED") }

      it "returns true" do
        expect(described_class.should_configure?).to be true
      end
    end

    context "when OTEL_ENABLED is not true" do
      before { ENV.delete("OTEL_ENABLED") }

      it "returns false" do
        expect(described_class.should_configure?).to be false
      end
    end

    context "when OTEL_ENABLED is false" do
      before { ENV["OTEL_ENABLED"] = "false" }
      after { ENV.delete("OTEL_ENABLED") }

      it "returns false" do
        expect(described_class.should_configure?).to be false
      end
    end
  end

  describe ".configure" do
    context "when OpenTelemetry is not enabled" do
      before { ENV.delete("OTEL_ENABLED") }

      it "does not configure OpenTelemetry" do
        expect(::OpenTelemetry::SDK).not_to receive(:configure)
        described_class.configure
      end
    end

    context "when OpenTelemetry is enabled" do
      before do
        ENV["OTEL_ENABLED"] = "true"
        # Reset OpenTelemetry state
        allow(::OpenTelemetry::SDK).to receive(:configure).and_yield(double(
          service_name: nil,
          use: nil
        ))
      end

      after { ENV.delete("OTEL_ENABLED") }

      it "configures OpenTelemetry SDK" do
        expect(::OpenTelemetry::SDK).to receive(:configure)
        described_class.configure
      end

      it "sets up the tracer" do
        tracer_provider = instance_double(::OpenTelemetry::SDK::Trace::TracerProvider)
        allow(::OpenTelemetry).to receive(:tracer_provider).and_return(tracer_provider)
        allow(tracer_provider).to receive(:tracer)

        described_class.configure

        expect(tracer_provider).to have_received(:tracer).with("dependabot", Dependabot::VERSION)
      end
    end
  end

  describe ".tracer" do
    it "returns a tracer with correct name and version" do
      tracer_provider = instance_double(::OpenTelemetry::SDK::Trace::TracerProvider)
      allow(::OpenTelemetry).to receive(:tracer_provider).and_return(tracer_provider)
      allow(tracer_provider).to receive(:tracer).and_return(instance_double(::OpenTelemetry::Trace::Tracer))

      tracer = described_class.tracer

      expect(tracer_provider).to have_received(:tracer).with("dependabot", Dependabot::VERSION)
      expect(tracer).to be_a(::OpenTelemetry::Trace::Tracer)
    end
  end

  describe ".shutdown" do
    context "when OpenTelemetry is not enabled" do
      before { ENV.delete("OTEL_ENABLED") }

      it "does not shutdown OpenTelemetry" do
        tracer_provider = instance_double(::OpenTelemetry::SDK::Trace::TracerProvider)
        allow(::OpenTelemetry).to receive(:tracer_provider).and_return(tracer_provider)
        allow(tracer_provider).to receive(:force_flush)
        allow(tracer_provider).to receive(:shutdown)

        described_class.shutdown

        expect(tracer_provider).not_to have_received(:force_flush)
        expect(tracer_provider).not_to have_received(:shutdown)
      end
    end

    context "when OpenTelemetry is enabled" do
      before { ENV["OTEL_ENABLED"] = "true" }
      after { ENV.delete("OTEL_ENABLED") }

      it "flushes and shuts down the tracer provider" do
        tracer_provider = instance_double(::OpenTelemetry::SDK::Trace::TracerProvider)
        allow(::OpenTelemetry).to receive(:tracer_provider).and_return(tracer_provider)
        allow(tracer_provider).to receive(:force_flush)
        allow(tracer_provider).to receive(:shutdown)

        described_class.shutdown

        expect(tracer_provider).to have_received(:force_flush)
        expect(tracer_provider).to have_received(:shutdown)
      end
    end
  end

  describe ".record_update_job_error" do
    let(:job_id) { 12345 }
    let(:error_type) { "dependency_file_not_found" }
    let(:error_details) { { "file_path" => "/path/to/file", "error_class" => "FileNotFound" } }
    let(:current_span) { instance_double(::OpenTelemetry::SDK::Trace::Span) }

    before do
      allow(::OpenTelemetry::Trace).to receive(:current_span).and_return(current_span)
      allow(current_span).to receive(:add_event)
    end

    it "records an error event on the current span" do
      described_class.record_update_job_error(
        job_id: job_id,
        error_type: error_type,
        error_details: error_details
      )

      expect(current_span).to have_received(:add_event).with(
        error_type,
        attributes: {
          "dependabot.job.id" => job_id,
          "dependabot.job.error_type" => error_type,
          "dependabot.job.error_details.file_path" => "/path/to/file",
          "dependabot.job.error_details.error_class" => "FileNotFound"
        }
      )
    end

    it "handles nil error_details" do
      described_class.record_update_job_error(
        job_id: job_id,
        error_type: error_type,
        error_details: nil
      )

      expect(current_span).to have_received(:add_event).with(
        error_type,
        attributes: {
          "dependabot.job.id" => job_id,
          "dependabot.job.error_type" => error_type
        }
      )
    end

    it "accepts string job_id" do
      described_class.record_update_job_error(
        job_id: "string-id",
        error_type: error_type,
        error_details: error_details
      )

      expect(current_span).to have_received(:add_event)
    end
  end

  describe ".record_update_job_warning" do
    let(:job_id) { 67890 }
    let(:warn_type) { "unknown_git_source" }
    let(:warn_title) { "Unknown git source" }
    let(:warn_description) { "The git source specified is not recognized" }
    let(:current_span) { instance_double(::OpenTelemetry::SDK::Trace::Span) }

    before do
      allow(::OpenTelemetry::Trace).to receive(:current_span).and_return(current_span)
      allow(current_span).to receive(:add_event)
    end

    it "records a warning event on the current span" do
      described_class.record_update_job_warning(
        job_id: job_id,
        warn_type: warn_type,
        warn_title: warn_title,
        warn_description: warn_description
      )

      expect(current_span).to have_received(:add_event).with(
        warn_type,
        attributes: {
          "dependabot.job.id" => job_id,
          "dependabot.job.warn_type" => warn_type,
          "dependabot.job.warn_title" => warn_title,
          "dependabot.job.warn_description" => warn_description
        }
      )
    end
  end

  describe ".record_exception" do
    let(:error) { StandardError.new("Something went wrong") }
    let(:job) { double(id: 123) }
    let(:tags) { { "custom_tag" => "custom_value" } }
    let(:current_span) { instance_double(::OpenTelemetry::SDK::Trace::Span) }

    before do
      allow(::OpenTelemetry::Trace).to receive(:current_span).and_return(current_span)
      allow(current_span).to receive(:set_attribute)
      allow(current_span).to receive(:add_attributes)
      allow(current_span).to receive(:status=)
      allow(current_span).to receive(:record_exception)
      allow(::OpenTelemetry::Trace::Status).to receive(:error).and_return(instance_double(::OpenTelemetry::Trace::Status))
    end

    it "records an exception on the current span" do
      described_class.record_exception(error: error, job: job, tags: tags)

      expect(current_span).to have_received(:set_attribute)
        .with("dependabot.job.id", "123")
      expect(current_span).to have_received(:add_attributes).with(tags)
      expect(current_span).to have_received(:record_exception).with(error)
    end

    it "sets error status with exception message" do
      described_class.record_exception(error: error, job: job, tags: tags)

      expect(::OpenTelemetry::Trace::Status).to have_received(:error)
        .with("Something went wrong")
    end

    it "handles nil job" do
      described_class.record_exception(error: error, job: nil, tags: tags)

      expect(current_span).not_to have_received(:set_attribute)
        .with("dependabot.job.id", anything)
      expect(current_span).to have_received(:record_exception).with(error)
    end

    it "handles empty tags" do
      described_class.record_exception(error: error, job: job, tags: {})

      expect(current_span).not_to have_received(:add_attributes)
      expect(current_span).to have_received(:record_exception).with(error)
    end
  end

  describe "Attributes" do
    it "defines all expected attribute constants" do
      expect(described_class::Attributes::JOB_ID).to eq("dependabot.job.id")
      expect(described_class::Attributes::WARN_TYPE).to eq("dependabot.job.warn_type")
      expect(described_class::Attributes::WARN_TITLE).to eq("dependabot.job.warn_title")
      expect(described_class::Attributes::WARN_DESCRIPTION).to eq("dependabot.job.warn_description")
      expect(described_class::Attributes::ERROR_TYPE).to eq("dependabot.job.error_type")
      expect(described_class::Attributes::ERROR_DETAILS).to eq("dependabot.job.error_details")
      expect(described_class::Attributes::METRIC).to eq("dependabot.metric")
      expect(described_class::Attributes::BASE_COMMIT_SHA).to eq("dependabot.base_commit_sha")
      expect(described_class::Attributes::DEPENDENCY_NAMES).to eq("dependabot.dependency_names")
      expect(described_class::Attributes::PR_CLOSE_REASON).to eq("dependabot.pr_close_reason")
    end
  end

  describe "edge cases and regression tests" do
    describe "error handling with missing spans" do
      let(:error) { StandardError.new("Test error") }

      it "handles recording exception when no active span exists" do
        # Simulate no active span scenario
        allow(::OpenTelemetry::Trace).to receive(:current_span).and_return(
          ::OpenTelemetry::Trace::Span::INVALID
        )

        # Should not raise an error even without active span
        expect do
          described_class.record_exception(error: error, job: nil, tags: {})
        end.not_to raise_error
      end
    end

    describe "multiple sequential error recordings" do
      let(:current_span) { instance_double(::OpenTelemetry::SDK::Trace::Span) }

      before do
        allow(::OpenTelemetry::Trace).to receive(:current_span).and_return(current_span)
        allow(current_span).to receive(:set_attribute)
        allow(current_span).to receive(:add_attributes)
        allow(current_span).to receive(:status=)
        allow(current_span).to receive(:record_exception)
        allow(current_span).to receive(:add_event)
        allow(::OpenTelemetry::Trace::Status).to receive(:error).and_return(
          instance_double(::OpenTelemetry::Trace::Status)
        )
      end

      it "can record multiple errors sequentially" do
        3.times do |i|
          described_class.record_update_job_error(
            job_id: i,
            error_type: "error_#{i}",
            error_details: { "index" => i }
          )
        end

        expect(current_span).to have_received(:add_event).exactly(3).times
      end

      it "can record mixed events (errors and warnings)" do
        described_class.record_update_job_error(
          job_id: 1,
          error_type: "test_error",
          error_details: nil
        )

        described_class.record_update_job_warning(
          job_id: 1,
          warn_type: "test_warning",
          warn_title: "Test",
          warn_description: "Description"
        )

        expect(current_span).to have_received(:add_event).exactly(2).times
      end
    end

    describe "attribute value types" do
      let(:current_span) { instance_double(::OpenTelemetry::SDK::Trace::Span) }

      before do
        allow(::OpenTelemetry::Trace).to receive(:current_span).and_return(current_span)
        allow(current_span).to receive(:add_event)
      end

      it "handles integer job_id" do
        described_class.record_update_job_error(
          job_id: 12345,
          error_type: "test",
          error_details: nil
        )

        expect(current_span).to have_received(:add_event).with(
          "test",
          attributes: hash_including("dependabot.job.id" => 12345)
        )
      end

      it "handles string job_id" do
        described_class.record_update_job_error(
          job_id: "job-abc-123",
          error_type: "test",
          error_details: nil
        )

        expect(current_span).to have_received(:add_event).with(
          "test",
          attributes: hash_including("dependabot.job.id" => "job-abc-123")
        )
      end

      it "handles symbol error_type" do
        described_class.record_update_job_error(
          job_id: 1,
          error_type: :dependency_file_not_found,
          error_details: nil
        )

        expect(current_span).to have_received(:add_event).with(
          :dependency_file_not_found,
          attributes: hash_including("dependabot.job.error_type" => :dependency_file_not_found)
        )
      end

      it "handles nested error_details with various types" do
        described_class.record_update_job_error(
          job_id: 1,
          error_type: "test",
          error_details: {
            "string_value" => "text",
            "integer_value" => 42,
            "boolean_value" => true,
            "nil_value" => nil
          }
        )

        expect(current_span).to have_received(:add_event).with(
          "test",
          attributes: hash_including(
            "dependabot.job.error_details.string_value" => "text",
            "dependabot.job.error_details.integer_value" => 42,
            "dependabot.job.error_details.boolean_value" => true,
            "dependabot.job.error_details.nil_value" => nil
          )
        )
      end
    end
  end
end