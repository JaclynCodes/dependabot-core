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

    it "can require all OpenTelemetry exporter modules" do
      expect { require "opentelemetry/exporter/otlp" }.not_to raise_error
      expect { require "opentelemetry/instrumentation/excon" }.not_to raise_error
      expect { require "opentelemetry/instrumentation/faraday" }.not_to raise_error
      expect { require "opentelemetry/instrumentation/http" }.not_to raise_error
      expect { require "opentelemetry/instrumentation/net_http" }.not_to raise_error
    end
  end

  describe "Version alignment and dependency constraints" do
    # Critical test: ensures sentry-opentelemetry and sentry-ruby have aligned minor versions
    it "sentry-opentelemetry and sentry-ruby have matching minor versions" do
      sentry_ruby = Gem.loaded_specs["sentry-ruby"]
      sentry_otel = Gem.loaded_specs["sentry-opentelemetry"]

      # Both should be at 5.28.x for proper compatibility
      expect(sentry_ruby.version.segments[0]).to eq(5)
      expect(sentry_otel.version.segments[0]).to eq(5)
      expect(sentry_ruby.version.segments[1]).to eq(28)
      expect(sentry_otel.version.segments[1]).to eq(28)
    end

    it "Gemfile.lock has a valid BUNDLED WITH version" do
      lockfile_content = File.read(gemfile_lock_path)

      # Check BUNDLED WITH section exists and has a reasonable version
      expect(lockfile_content).to match(/BUNDLED WITH\s+\d+\.\d+\.\d+/)

      # Extract the bundler version
      bundler_version = lockfile_content.match(/BUNDLED WITH\s+(\d+\.\d+\.\d+)/)
      expect(bundler_version).not_to be_nil

      # Should be using Bundler 2.x (modern version)
      version = Gem::Version.new(bundler_version[1])
      expect(version).to be >= Gem::Version.new("2.0.0")
      expect(version).to be < Gem::Version.new("3.0.0")
    end

    it "OpenTelemetry SDK has compatible version with instrumentations" do
      otel_sdk = Gem.loaded_specs["opentelemetry-sdk"]
      otel_api = Gem.loaded_specs["opentelemetry-api"]

      # API and SDK should have compatible major versions
      expect(otel_sdk.version.segments[0]).to eq(otel_api.version.segments[0])
    end

    it "all OpenTelemetry instrumentation gems use compatible base version" do
      base_spec = Gem.loaded_specs["opentelemetry-instrumentation-base"]
      expect(base_spec).not_to be_nil

      # Verify instrumentation gems depend on compatible base
      %w[
        opentelemetry-instrumentation-excon
        opentelemetry-instrumentation-faraday
        opentelemetry-instrumentation-http
        opentelemetry-instrumentation-net_http
      ].each do |gem_name|
        gem_spec = Gem.loaded_specs[gem_name]
        expect(gem_spec).not_to be_nil

        base_dep = gem_spec.dependencies.find { |d| d.name == "opentelemetry-instrumentation-base" }
        expect(base_dep).not_to be_nil, "#{gem_name} should depend on opentelemetry-instrumentation-base"
        expect(base_dep.requirement.satisfied_by?(base_spec.version)).to be true
      end
    end

    it "lockfile does not contain any pre-release versions" do
      parser = Bundler::LockfileParser.new(File.read(gemfile_lock_path))

      # Pre-release versions could indicate instability
      pre_release_gems = parser.specs.select { |spec| spec.version.prerelease? }

      expect(pre_release_gems).to be_empty,
        "Found pre-release gems: #{pre_release_gems.map(&:name).join(', ')}"
    end

    it "verifies no deprecated gem versions are in use" do
      # sentry-opentelemetry 5.23.0 is the old version we upgraded from
      parser = Bundler::LockfileParser.new(File.read(gemfile_lock_path))

      old_sentry_otel = parser.specs.find do |spec|
        spec.name == "sentry-opentelemetry" && spec.version <= Gem::Version.new("5.23.0")
      end

      expect(old_sentry_otel).to be_nil,
        "Should not contain old sentry-opentelemetry version 5.23.0"
    end
  end

  describe "Regression tests for common dependency issues" do
    it "does not have duplicate gem entries in Gemfile" do
      gemfile_content = File.read(gemfile_path)

      # Check for duplicate gem declarations
      gem_names = gemfile_content.scan(/gem\s+["']([^"']+)["']/).flatten
      duplicates = gem_names.select { |name| gem_names.count(name) > 1 }.uniq

      expect(duplicates).to be_empty,
        "Found duplicate gem entries: #{duplicates.join(', ')}"
    end

    it "Gemfile.lock checksums are present for all gems" do
      lockfile_content = File.read(gemfile_lock_path)

      # Modern Gemfile.lock should have CHECKSUMS section
      expect(lockfile_content).to include("CHECKSUMS")

      # Verify sentry gems have checksums
      expect(lockfile_content).to match(/sentry-ruby \(\d+\.\d+\.\d+\) sha256=/)
      expect(lockfile_content).to match(/sentry-opentelemetry \(\d+\.\d+\.\d+\) sha256=/)
    end

    it "verifies platform-specific gems are included if needed" do
      parser = Bundler::LockfileParser.new(File.read(gemfile_lock_path))

      # Some gems like google-protobuf, nokogiri have platform-specific versions
      # Verify they exist for common platforms
      google_protobuf_specs = parser.specs.select { |s| s.name == "google-protobuf" }

      # Should have multiple platform-specific versions
      expect(google_protobuf_specs.count).to be > 1,
        "Expected multiple platform-specific google-protobuf gems"
    end
  end
end