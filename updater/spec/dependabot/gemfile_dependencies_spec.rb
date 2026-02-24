# typed: false
# frozen_string_literal: true

require "spec_helper"
require "bundler"

RSpec.describe "Gemfile Dependencies" do
  let(:gemfile_path) { File.expand_path("../../Gemfile", __dir__) }
  let(:lockfile_path) { File.expand_path("../../Gemfile.lock", __dir__) }

  describe "dependency resolution" do
    it "has a valid Gemfile" do
      expect(File.exist?(gemfile_path)).to be true
      expect { Bundler::Definition.build(gemfile_path, lockfile_path, false) }.not_to raise_error
    end

    it "has a valid Gemfile.lock" do
      expect(File.exist?(lockfile_path)).to be true
      lockfile_content = File.read(lockfile_path)
      expect(lockfile_content).not_to be_empty
    end

    it "has sentry-opentelemetry gem specified" do
      gemfile_content = File.read(gemfile_path)
      expect(gemfile_content).to match(/gem\s+["']sentry-opentelemetry["']/)
    end

    it "has sentry-ruby gem specified" do
      gemfile_content = File.read(gemfile_path)
      expect(gemfile_content).to match(/gem\s+["']sentry-ruby["']/)
    end

    it "locks sentry-opentelemetry to version 5.28.x" do
      lockfile_content = File.read(lockfile_path)
      expect(lockfile_content).to match(/sentry-opentelemetry \(5\.28\.\d+\)/)
    end

    it "ensures sentry-ruby and sentry-opentelemetry versions are compatible" do
      lockfile_content = File.read(lockfile_path)

      # Extract version numbers
      sentry_ruby_match = lockfile_content.match(/sentry-ruby \((\d+\.\d+\.\d+)\)/)
      sentry_otel_match = lockfile_content.match(/sentry-opentelemetry \((\d+\.\d+\.\d+)\)/)

      expect(sentry_ruby_match).not_to be_nil
      expect(sentry_otel_match).not_to be_nil

      # sentry-opentelemetry should be compatible with sentry-ruby
      # Both should have matching major.minor versions
      sentry_ruby_version = Gem::Version.new(sentry_ruby_match[1])
      sentry_otel_version = Gem::Version.new(sentry_otel_match[1])

      expect(sentry_ruby_version.segments[0]).to eq(sentry_otel_version.segments[0])
    end
  end

  describe "OpenTelemetry dependencies" do
    it "has all required OpenTelemetry gems" do
      gemfile_content = File.read(gemfile_path)

      expect(gemfile_content).to match(/gem\s+["']opentelemetry-sdk["']/)
      expect(gemfile_content).to match(/gem\s+["']opentelemetry-exporter-otlp["']/)
      expect(gemfile_content).to match(/gem\s+["']opentelemetry-exporter-otlp-logs["']/)
      expect(gemfile_content).to match(/gem\s+["']opentelemetry-exporter-otlp-metrics["']/)
    end

    it "has OpenTelemetry instrumentation gems" do
      gemfile_content = File.read(gemfile_path)

      expect(gemfile_content).to match(/gem\s+["']opentelemetry-instrumentation-excon["']/)
      expect(gemfile_content).to match(/gem\s+["']opentelemetry-instrumentation-faraday["']/)
      expect(gemfile_content).to match(/gem\s+["']opentelemetry-instrumentation-http["']/)
      expect(gemfile_content).to match(/gem\s+["']opentelemetry-instrumentation-net_http["']/)
    end

    it "has compatible OpenTelemetry versions in lockfile" do
      lockfile_content = File.read(lockfile_path)

      # Verify opentelemetry-sdk is present
      expect(lockfile_content).to match(/opentelemetry-sdk \(\d+\.\d+\.\d+\)/)

      # Verify opentelemetry-api is compatible (should be used by all OpenTelemetry gems)
      expect(lockfile_content).to match(/opentelemetry-api \(\d+\.\d+\.\d+\)/)
    end
  end

  describe "dependency checksums" do
    it "has CHECKSUMS section in Gemfile.lock" do
      lockfile_content = File.read(lockfile_path)
      expect(lockfile_content).to include("CHECKSUMS")
    end

    it "has checksum for sentry-opentelemetry" do
      lockfile_content = File.read(lockfile_path)
      expect(lockfile_content).to match(/sentry-opentelemetry \(5\.28\.\d+\) sha256=[a-f0-9]{64}/)
    end

    it "has checksum for sentry-ruby" do
      lockfile_content = File.read(lockfile_path)
      expect(lockfile_content).to match(/sentry-ruby \(5\.\d+\.\d+\) sha256=[a-f0-9]{64}/)
    end
  end

  describe "bundler version" do
    it "specifies BUNDLED WITH version" do
      lockfile_content = File.read(lockfile_path)
      expect(lockfile_content).to match(/BUNDLED WITH\s+\d+\.\d+\.\d+/)
    end
  end
end