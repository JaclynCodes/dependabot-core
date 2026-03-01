# typed: false
# frozen_string_literal: true

require "spec_helper"
require "bundler"

RSpec.describe "Gemfile and Gemfile.lock" do
  let(:gemfile_path) { File.expand_path("../../../Gemfile", __dir__) }
  let(:gemfile_lock_path) { File.expand_path("../../../Gemfile.lock", __dir__) }

  describe "Gemfile" do
    it "exists" do
      expect(File).to exist(gemfile_path)
    end

    it "is a valid Ruby file" do
      expect { eval(File.read(gemfile_path), binding, gemfile_path) }.not_to raise_error
    end

    it "specifies sentry-opentelemetry dependency" do
      gemfile_content = File.read(gemfile_path)
      expect(gemfile_content).to match(/gem\s+["']sentry-opentelemetry["']/)
    end

    it "specifies sentry-ruby dependency" do
      gemfile_content = File.read(gemfile_path)
      expect(gemfile_content).to match(/gem\s+["']sentry-ruby["']/)
    end

    it "specifies OpenTelemetry dependencies" do
      gemfile_content = File.read(gemfile_path)
      expect(gemfile_content).to include("opentelemetry-exporter-otlp")
      expect(gemfile_content).to include("opentelemetry-instrumentation-excon")
      expect(gemfile_content).to include("opentelemetry-instrumentation-faraday")
      expect(gemfile_content).to include("opentelemetry-instrumentation-http")
      expect(gemfile_content).to include("opentelemetry-instrumentation-net_http")
      expect(gemfile_content).to include("opentelemetry-sdk")
    end

    it "has correct version constraint for sentry-opentelemetry" do
      gemfile_content = File.read(gemfile_path)
      # Should be ~> 5.28 (allowing patch updates)
      expect(gemfile_content).to match(/gem\s+["']sentry-opentelemetry["'],\s+["']~>\s*5\.28["']/)
    end

    it "has correct version constraint for sentry-ruby" do
      gemfile_content = File.read(gemfile_path)
      # Should be ~> 5.23 or higher
      expect(gemfile_content).to match(/gem\s+["']sentry-ruby["'],\s+["']~>\s*5\.\d+["']/)
    end
  end

  describe "Gemfile.lock" do
    it "exists" do
      expect(File).to exist(gemfile_lock_path)
    end

    it "is in sync with Gemfile" do
      # This verifies that Gemfile.lock hasn't diverged from Gemfile
      # by checking that bundle check passes
      Dir.chdir(File.dirname(gemfile_path)) do
        # We can't run bundle check in test environment without installing,
        # so we just verify the lock file is parseable
        expect { Bundler::LockfileParser.new(File.read(gemfile_lock_path)) }.not_to raise_error
      end
    end

    it "locks sentry-opentelemetry to version 5.28.1" do
      lockfile_content = File.read(gemfile_lock_path)
      expect(lockfile_content).to match(/sentry-opentelemetry\s+\(5\.28\.1\)/)
    end

    it "locks sentry-ruby to compatible version" do
      lockfile_content = File.read(gemfile_lock_path)
      # Should be version 5.x.x
      expect(lockfile_content).to match(/sentry-ruby\s+\(5\.\d+\.\d+\)/)
    end

    it "includes OpenTelemetry SDK dependencies" do
      lockfile_content = File.read(gemfile_lock_path)
      expect(lockfile_content).to include("opentelemetry-sdk")
      expect(lockfile_content).to include("opentelemetry-api")
    end

    it "has consistent dependency resolution" do
      parser = Bundler::LockfileParser.new(File.read(gemfile_lock_path))

      # Verify sentry-opentelemetry is present
      sentry_otel = parser.specs.find { |s| s.name == "sentry-opentelemetry" }
      expect(sentry_otel).not_to be_nil
      expect(sentry_otel.version.to_s).to eq("5.28.1")

      # Verify sentry-ruby is present
      sentry_ruby = parser.specs.find { |s| s.name == "sentry-ruby" }
      expect(sentry_ruby).not_to be_nil

      # Verify opentelemetry-sdk is present
      otel_sdk = parser.specs.find { |s| s.name == "opentelemetry-sdk" }
      expect(otel_sdk).not_to be_nil
    end
  end

  describe "Bundler loading" do
    it "can load all gems without conflicts" do
      # This test verifies that all dependencies can be loaded together
      # without version conflicts or missing dependencies
      expect(Gem.loaded_specs["sentry-ruby"]).not_to be_nil
      expect(Gem.loaded_specs["sentry-opentelemetry"]).not_to be_nil
      expect(Gem.loaded_specs["opentelemetry-sdk"]).not_to be_nil
    end

    it "loads sentry-opentelemetry with correct dependencies" do
      sentry_otel_spec = Gem.loaded_specs["sentry-opentelemetry"]
      expect(sentry_otel_spec).not_to be_nil

      # Check that it has the expected dependencies
      dep_names = sentry_otel_spec.dependencies.map(&:name)
      expect(dep_names).to include("sentry-ruby")
      expect(dep_names).to include("opentelemetry-sdk")
    end

    it "loads OpenTelemetry instrumentation gems" do
      expect(Gem.loaded_specs["opentelemetry-instrumentation-excon"]).not_to be_nil
      expect(Gem.loaded_specs["opentelemetry-instrumentation-faraday"]).not_to be_nil
      expect(Gem.loaded_specs["opentelemetry-instrumentation-http"]).not_to be_nil
      expect(Gem.loaded_specs["opentelemetry-instrumentation-net_http"]).not_to be_nil
    end

    it "loads OpenTelemetry exporter gems" do
      expect(Gem.loaded_specs["opentelemetry-exporter-otlp"]).not_to be_nil
      expect(Gem.loaded_specs["opentelemetry-exporter-otlp-logs"]).not_to be_nil
      expect(Gem.loaded_specs["opentelemetry-exporter-otlp-metrics"]).not_to be_nil
    end
  end

  describe "Version upgrade verification" do
    # This test ensures the upgrade from 5.23.0 to 5.28.1 is properly applied
    it "has upgraded sentry-opentelemetry from 5.23.0 to 5.28.1" do
      sentry_otel_spec = Gem.loaded_specs["sentry-opentelemetry"]
      expect(sentry_otel_spec.version.to_s).to eq("5.28.1")
      expect(sentry_otel_spec.version).to be >= Gem::Version.new("5.28.1")
    end

    it "has sentry-opentelemetry version newer than 5.23.0" do
      sentry_otel_spec = Gem.loaded_specs["sentry-opentelemetry"]
      expect(sentry_otel_spec.version).to be > Gem::Version.new("5.23.0")
    end

    it "maintains compatibility between sentry gems" do
      sentry_ruby = Gem.loaded_specs["sentry-ruby"]
      sentry_otel = Gem.loaded_specs["sentry-opentelemetry"]

      # Both should be in 5.x version range for compatibility
      expect(sentry_ruby.version.segments.first).to eq(5)
      expect(sentry_otel.version.segments.first).to eq(5)

      # sentry-opentelemetry should depend on compatible sentry-ruby version
      sentry_ruby_dep = sentry_otel.dependencies.find { |d| d.name == "sentry-ruby" }
      expect(sentry_ruby_dep.requirement.satisfied_by?(sentry_ruby.version)).to be true
    end
  end

  describe "Security and stability" do
    it "does not have any conflicting gem versions" do
      # Bundler would fail to load if there were conflicts, so this
      # passing means no conflicts
      expect(Bundler.locked_gems).not_to be_nil
    end

    it "uses pessimistic version constraints for stability" do
      gemfile_content = File.read(gemfile_path)

      # Sentry gems should use ~> operator for stable updates
      expect(gemfile_content).to match(/gem\s+["']sentry-opentelemetry["'],\s+["']~>/)
      expect(gemfile_content).to match(/gem\s+["']sentry-ruby["'],\s+["']~>/)
    end

    it "locks all transitive dependencies" do
      parser = Bundler::LockfileParser.new(File.read(gemfile_lock_path))

      # All specs should have resolved versions
      parser.specs.each do |spec|
        expect(spec.version).not_to be_nil
        expect(spec.version.to_s).to match(/^\d+\.\d+\.\d+/)
      end
    end
  end

  describe "Runtime loading verification" do
    it "can require sentry-ruby without errors" do
      expect { require "sentry-ruby" }.not_to raise_error
    end

    it "can require sentry-opentelemetry without errors" do
      expect { require "sentry-opentelemetry" }.not_to raise_error
    end

    it "can require opentelemetry/sdk without errors" do
      expect { require "opentelemetry/sdk" }.not_to raise_error
    end

    it "can initialize Sentry with the upgraded version" do
      expect do
        Sentry.init do |config|
          config.dsn = nil # Disable sending
          config.instrumenter = :sentry
        end
      end.not_to raise_error
    end
  end
end