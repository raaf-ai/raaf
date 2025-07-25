# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe RAAF::DSL::Config, :with_temp_files do
  let(:test_config) do
    {
      "defaults" => {
        "global" => {
          "model" => "gpt-4o",
          "max_turns" => 3,
          "temperature" => 0.7,
          "timeout" => 120
        }
      },
      "development" => {
        "global" => {
          "model" => "gpt-4o-mini",
          "max_turns" => 2,
          "temperature" => 0.3
        }
      },
      "test" => {
        "global" => {
          "model" => "gpt-4o-mini",
          "max_turns" => 1,
          "timeout" => 30
        }
      },
      "production" => {
        "global" => {
          "model" => "gpt-4o",
          "max_turns" => 5,
          "temperature" => 0.7
        },
        "agents" => {
          "content_analysis_agent" => {
            "max_turns" => 3,
            "temperature" => 0.5
          },
          "test_agent" => {
            "model" => "gpt-3.5-turbo",
            "max_turns" => 4
          }
        }
      }
    }
  end

  before do
    # Reset config state before each test
    described_class.instance_variable_set(:@config, nil)
    described_class.instance_variable_set(:@environment_configs, {})
  end

  describe "class methods" do
    describe ".for_agent" do
      context "with configuration file" do
        it "returns configuration for a specific agent" do
          with_config_file(test_config) do
            config = described_class.for_agent("content_analysis_agent", environment: "production")

            expect(config["model"]).to eq("gpt-4o")
            expect(config["max_turns"]).to eq(3)
            expect(config["temperature"]).to eq(0.5)
          end
        end

        it "falls back to global configuration" do
          with_config_file(test_config) do
            config = described_class.for_agent("unknown_agent", environment: "development")

            expect(config["model"]).to eq("gpt-4o-mini")
            expect(config["max_turns"]).to eq(2)
            expect(config["temperature"]).to eq(0.3)
          end
        end

        it "normalizes agent names" do
          with_config_file(test_config) do
            config = described_class.for_agent("ContentAnalysisAgent", environment: "production")

            expect(config["max_turns"]).to eq(3)
            expect(config["temperature"]).to eq(0.5)
          end
        end

        it "returns indifferent access hash" do
          with_config_file(test_config) do
            config = described_class.for_agent("test_agent", environment: "production")

            expect(config[:model]).to eq("gpt-3.5-turbo")
            expect(config["model"]).to eq("gpt-3.5-turbo")
          end
        end

        it "merges global and agent-specific config" do
          with_config_file(test_config) do
            config = described_class.for_agent("test_agent", environment: "production")

            # Agent-specific override
            expect(config["model"]).to eq("gpt-3.5-turbo")
            expect(config["max_turns"]).to eq(4)

            # Inherited from global
            expect(config["temperature"]).to eq(0.7)
          end
        end
      end

      context "without configuration file" do
        it "returns empty hash when no config file exists" do
          config = described_class.for_agent("any_agent")
          expect(config).to eq({})
        end
      end
    end

    describe ".global" do
      it "returns global configuration for environment" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          config = described_class.global(environment: "development")

          expect(config["model"]).to eq("gpt-4o-mini")
          expect(config["max_turns"]).to eq(2)
          expect(config["temperature"]).to eq(0.3)
        end
      end

      it "uses current environment by default" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }
          mock_rails_env("test")
          allow(Rails).to receive(:env).and_return("test") if defined?(Rails)

          config = described_class.global

          expect(config["model"]).to eq("gpt-4o-mini")
          expect(config["max_turns"]).to eq(1)
        end
      end
    end

    describe ".max_turns_for" do
      it "returns agent-specific max_turns" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          max_turns = described_class.max_turns_for("content_analysis_agent", environment: "production")
          expect(max_turns).to eq(3)
        end
      end

      it "falls back to global max_turns" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          max_turns = described_class.max_turns_for("unknown_agent", environment: "development")
          expect(max_turns).to eq(2)
        end
      end

      it "falls back to default max_turns" do
        max_turns = described_class.max_turns_for("unknown_agent", environment: "unknown")
        expect(max_turns).to eq(3) # Default from RAAF::DSL.configuration
      end
    end

    describe ".model_for" do
      it "returns agent-specific model" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          model = described_class.model_for("test_agent", environment: "production")
          expect(model).to eq("gpt-3.5-turbo")
        end
      end

      it "falls back to global model" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          model = described_class.model_for("unknown_agent", environment: "development")
          expect(model).to eq("gpt-4o-mini")
        end
      end

      it "falls back to default model" do
        model = described_class.model_for("unknown_agent", environment: "unknown")
        expect(model).to eq("gpt-4o") # Default from RAAF::DSL.configuration
      end
    end

    describe ".temperature_for" do
      it "returns agent-specific temperature" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          temperature = described_class.temperature_for("content_analysis_agent", environment: "production")
          expect(temperature).to eq(0.5)
        end
      end

      it "falls back to global temperature" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          temperature = described_class.temperature_for("unknown_agent", environment: "development")
          expect(temperature).to eq(0.3)
        end
      end

      it "falls back to default temperature" do
        temperature = described_class.temperature_for("unknown_agent", environment: "unknown")
        expect(temperature).to eq(0.7) # Default from RAAF::DSL.configuration
      end
    end

    describe ".timeout_for" do
      it "returns configured timeout" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          timeout = described_class.timeout_for("any_agent", environment: "test")
          expect(timeout).to eq(30)
        end
      end

      it "returns default timeout when not configured" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          timeout = described_class.timeout_for("any_agent", environment: "development")
          expect(timeout).to eq(120) # Default timeout
        end
      end
    end

    describe ".all_agents" do
      it "returns all agent configurations" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          agents = described_class.all_agents(environment: "production")

          expect(agents).to have_key("content_analysis_agent")
          expect(agents).to have_key("test_agent")
          expect(agents["content_analysis_agent"]["max_turns"]).to eq(3)
        end
      end

      it "returns empty hash when no agents configured" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          agents = described_class.all_agents(environment: "development")
          expect(agents).to eq({})
        end
      end
    end

    describe ".agent_configured?" do
      it "returns true for configured agent" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          expect(described_class.agent_configured?("content_analysis_agent", environment: "production")).to be true
        end
      end

      it "returns false for unconfigured agent" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          expect(described_class.agent_configured?("unknown_agent", environment: "production")).to be false
        end
      end

      it "normalizes agent names for checking" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          expect(described_class.agent_configured?("ContentAnalysisAgent", environment: "production")).to be true
        end
      end
    end

    describe ".reload!" do
      it "clears cached configuration" do
        # Load initial config
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }
          described_class.for_agent("test_agent")
        end

        # Reload should clear cache
        described_class.reload!

        expect(described_class.instance_variable_get(:@config)).to be_nil
        expect(described_class.instance_variable_get(:@environment_configs)).to eq({})
      end
    end

    describe ".raw_config" do
      it "returns the raw configuration hash" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          raw = described_class.raw_config
          expect(raw).to eq(test_config)
        end
      end

      it "caches the raw configuration" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          raw1 = described_class.raw_config
          raw2 = described_class.raw_config
          expect(raw1).to be(raw2)
        end
      end
    end
  end

  describe "private methods" do
    describe "environment detection" do
      context "with Rails defined" do
        it "uses Rails.env" do
          # Mock Rails directly in the test
          rails_mock = double("Rails")
          allow(rails_mock).to receive_messages(env: "production", respond_to?: false) # Default response
          allow(rails_mock).to receive(:respond_to?).with(:env).and_return(true)
          allow(rails_mock).to receive(:respond_to?).with(:root).and_return(false)
          allow(rails_mock).to receive(:respond_to?).with(:logger).and_return(false)
          stub_const("Rails", rails_mock)

          config = described_class.global
          # Should attempt to load production config
          expect(config).to be_a(Hash)
        end
      end

      context "without Rails" do
        before do
          hide_const("Rails")
        end

        it "uses RAILS_ENV environment variable" do
          allow(ENV).to receive(:[]).with("RAILS_ENV").and_return("staging")
          allow(ENV).to receive(:[]).with("RACK_ENV").and_return("test")

          # RAILS_ENV takes precedence
          expect(described_class.send(:current_environment)).to eq("staging")
        end

        it "falls back to RACK_ENV" do
          allow(ENV).to receive(:[]).with("RAILS_ENV").and_return(nil)
          allow(ENV).to receive(:[]).with("RACK_ENV").and_return("production")

          expect(described_class.send(:current_environment)).to eq("production")
        end

        it "defaults to development" do
          allow(ENV).to receive(:[]).with("RAILS_ENV").and_return(nil)
          allow(ENV).to receive(:[]).with("RACK_ENV").and_return(nil)

          expect(described_class.send(:current_environment)).to eq("development")
        end
      end
    end

    describe "configuration loading" do
      context "with Rails" do
        it "uses Rails.root for config path" do
          # Mock Rails directly in the test
          rails_mock = double("Rails")
          allow(rails_mock).to receive_messages(root: Pathname.new(temp_dir), respond_to?: false) # Default response
          allow(rails_mock).to receive(:respond_to?).with(:root).and_return(true)
          allow(rails_mock).to receive(:respond_to?).with(:env).and_return(false)
          allow(rails_mock).to receive(:respond_to?).with(:logger).and_return(false)
          stub_const("Rails", rails_mock)

          config_path = File.join(temp_dir, "config", "ai_agents.yml")
          FileUtils.mkdir_p(File.dirname(config_path))
          File.write(config_path, test_config.to_yaml)

          config = described_class.global
          expect(config).not_to be_empty
        end
      end

      context "without Rails" do
        before do
          hide_const("Rails")
        end

        it "uses configured config file path" do
          config_path = create_test_config_file(test_config)
          RAAF::DSL.configure { |c| c.config_file = config_path }

          config = described_class.global
          expect(config).not_to be_empty
        end
      end

      context "with missing config file" do
        it "returns empty configuration" do
          RAAF::DSL.configure { |c| c.config_file = "nonexistent.yml" }

          config = described_class.global
          expect(config).to eq({})
        end

        it "logs warning when Rails logger is available" do
          # Mock Rails directly in the test
          logger = double("Logger")
          rails_mock = double("Rails")
          allow(rails_mock).to receive_messages(logger: logger, respond_to?: false) # Default response
          allow(rails_mock).to receive(:respond_to?).with(:logger).and_return(true)
          allow(rails_mock).to receive(:respond_to?).with(:env).and_return(false)
          allow(rails_mock).to receive(:respond_to?).with(:root).and_return(false)
          allow(logger).to receive(:warn)
          stub_const("Rails", rails_mock)

          RAAF::DSL.configure { |c| c.config_file = "nonexistent.yml" }
          described_class.global

          expect(logger).to have_received(:warn).with(/configuration file not found/)
        end
      end

      context "with invalid YAML" do
        it "returns empty configuration" do
          invalid_config_path = create_invalid_yaml_file
          RAAF::DSL.configure { |c| c.config_file = invalid_config_path }

          config = described_class.global
          expect(config).to eq({})
        end

        it "logs error when Rails logger is available" do
          # Mock Rails directly in the test
          logger = double("Logger")
          rails_mock = double("Rails")
          allow(rails_mock).to receive_messages(logger: logger, respond_to?: false) # Default response
          allow(rails_mock).to receive(:respond_to?).with(:logger).and_return(true)
          allow(rails_mock).to receive(:respond_to?).with(:env).and_return(false)
          allow(rails_mock).to receive(:respond_to?).with(:root).and_return(false)
          allow(logger).to receive(:error)
          stub_const("Rails", rails_mock)

          invalid_config_path = create_invalid_yaml_file
          RAAF::DSL.configure { |c| c.config_file = invalid_config_path }
          described_class.global

          expect(logger).to have_received(:error).with(/Invalid YAML/)
        end
      end

      context "with file read errors" do
        it "handles file permission errors gracefully" do
          config_path = create_test_config_file(test_config)

          # Mock file read error
          allow(YAML).to receive(:load_file).and_raise(Errno::EACCES, "Permission denied")

          RAAF::DSL.configure { |c| c.config_file = config_path }

          expect { described_class.global }.not_to raise_error
        end
      end
    end

    describe "agent name normalization" do
      it "converts CamelCase to snake_case" do
        normalized = described_class.send(:normalize_agent_name, "MarketResearchAgent")
        expect(normalized).to eq("market_research_agent")
      end

      it "handles already normalized names" do
        normalized = described_class.send(:normalize_agent_name, "market_research_agent")
        expect(normalized).to eq("market_research_agent")
      end

      it "handles symbols" do
        normalized = described_class.send(:normalize_agent_name, :MarketResearchAgent)
        expect(normalized).to eq("market_research_agent")
      end

      it "handles complex namespace names" do
        normalized = described_class.send(:normalize_agent_name, "Content::DocumentAnalysis")
        expect(normalized).to eq("content/document_analysis")
      end
    end
  end

  describe "instance methods" do
    describe "#initialize" do
      it "sets the environment" do
        instance = described_class.new(environment: "production")
        expect(instance.instance_variable_get(:@environment)).to eq("production")
      end

      it "uses current environment by default" do
        mock_rails_env("staging")
        # Also mock Rails.env if Rails is defined
        allow(Rails).to receive(:env).and_return("staging") if defined?(Rails)
        instance = described_class.new
        expect(instance.instance_variable_get(:@environment)).to eq("staging")
      end
    end

    describe "#for_agent" do
      it "delegates to class method with instance environment" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          config_instance = described_class.new(environment: "test")
          config = config_instance.for_agent("test_agent")
          expect(config["max_turns"]).to eq(1) # test environment value
        end
      end
    end

    describe "#global" do
      it "delegates to class method with instance environment" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          config_instance = described_class.new(environment: "test")
          config = config_instance.global
          expect(config["model"]).to eq("gpt-4o-mini") # test environment value
        end
      end
    end

    describe "#max_turns_for" do
      it "delegates to class method with instance environment" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          config_instance = described_class.new(environment: "test")
          max_turns = config_instance.max_turns_for("any_agent")
          expect(max_turns).to eq(1) # test environment value
        end
      end
    end

    describe "#model_for" do
      it "delegates to class method with instance environment" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          config_instance = described_class.new(environment: "test")
          model = config_instance.model_for("any_agent")
          expect(model).to eq("gpt-4o-mini") # test environment value
        end
      end
    end

    describe "#temperature_for" do
      it "delegates to class method with instance environment" do
        with_config_file(test_config) do |config_path|
          RAAF::DSL.configure { |c| c.config_file = config_path }

          config_instance = described_class.new(environment: "test")
          temperature = config_instance.temperature_for("any_agent")
          expect(temperature).to eq(0.7) # default value, test doesn't override
        end
      end
    end
  end

  describe "thread safety" do
    it "handles concurrent access safely" do
      with_config_file(test_config) do |config_path|
        RAAF::DSL.configure { |c| c.config_file = config_path }

        results = []
        threads = 10.times.map do |i|
          Thread.new do
            results[i] = described_class.for_agent("test_agent", environment: "production")
          end
        end

        threads.each(&:join)

        # All threads should get the same result
        expect(results.uniq.length).to eq(1)
        expect(results.first["model"]).to eq("gpt-3.5-turbo")
      end
    end
  end

  describe "configuration caching" do
    it "caches environment configurations" do
      with_config_file(test_config) do |config_path|
        RAAF::DSL.configure { |c| c.config_file = config_path }

        # First call should load and cache
        config1 = described_class.send(:environment_config, "production")

        # Second call should use cache
        config2 = described_class.send(:environment_config, "production")

        expect(config1).to be(config2)
      end
    end

    it "handles missing environment gracefully" do
      with_config_file(test_config) do |config_path|
        RAAF::DSL.configure { |c| c.config_file = config_path }

        config = described_class.send(:environment_config, "nonexistent")
        expect(config).to eq(test_config["defaults"])
      end
    end

    it "merges with defaults when environment config is incomplete" do
      incomplete_config = {
        "defaults" => {
          "global" => { "model" => "gpt-4o", "max_turns" => 3 }
        },
        "production" => {
          "global" => { "model" => "gpt-4o-turbo" }
        }
      }

      with_config_file(incomplete_config) do |config_path|
        RAAF::DSL.configure { |c| c.config_file = config_path }

        config = described_class.send(:environment_config, "production")
        expect(config["global"]["model"]).to eq("gpt-4o-turbo")
        expect(config["global"]["max_turns"]).to eq(3) # From defaults
      end
    end
  end
end
