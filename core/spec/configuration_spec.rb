# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "tmpdir"

RSpec.describe RAAF::Configuration do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_path) { File.join(temp_dir, "config") }

  before do
    Dir.mkdir(config_path)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates configuration with default environment" do
      config = described_class.new(auto_load: false)

      expect(config.environment).to eq("development")
    end

    it "accepts custom environment" do
      config = described_class.new(environment: "production", auto_load: false)

      expect(config.environment).to eq("production")
    end

    it "reads environment from ENV variable" do
      allow(ENV).to receive(:[]).with("RAAF_ENVIRONMENT").and_return("test")

      config = described_class.new(auto_load: false)

      expect(config.environment).to eq("test")
    end

    it "accepts custom config paths" do
      custom_paths = ["/custom/path"]
      config = described_class.new(config_paths: custom_paths, auto_load: false)

      expect(config.config_paths).to eq(custom_paths)
    end

    it "auto-loads configuration by default" do
      config = described_class.new

      expect(config.config_data).not_to be_empty
      expect(config.get("environment")).to eq("development")
    end

    it "skips auto-loading when disabled" do
      config = described_class.new(auto_load: false)

      expect(config.config_data).to be_empty
    end
  end

  describe "#load_configuration" do
    let(:config) { described_class.new(config_paths: [config_path], auto_load: false) }

    it "loads default configuration" do
      config.load_configuration

      expect(config.get("environment")).to eq("development")
      expect(config.get("openai.api_base")).to eq("https://api.openai.com/v1")
      expect(config.get("agent.max_turns")).to eq(10)
    end

    it "loads YAML configuration files" do
      File.write(File.join(config_path, "openai_agents.yml"), <<~YAML)
        agent:
          max_turns: 20
        openai:
          timeout: 120
      YAML

      config.load_configuration

      expect(config.get("agent.max_turns")).to eq(20)
      expect(config.get("openai.timeout")).to eq(120)
    end

    it "loads JSON configuration files" do
      File.write(File.join(config_path, "openai_agents.json"), <<~JSON)
        {
          "agent": {
            "max_turns": 25
          },
          "logging": {
            "level": "debug"
          }
        }
      JSON

      config.load_configuration

      expect(config.get("agent.max_turns")).to eq(25)
      expect(config.get("logging.level")).to eq("debug")
    end

    it "loads environment-specific configuration" do
      config = described_class.new(environment: "production", config_paths: [config_path], auto_load: false)

      File.write(File.join(config_path, "openai_agents.production.yml"), <<~YAML)
        agent:
          max_turns: 50
        guardrails:
          content_safety:
            strict_mode: true
        openai:
          api_key: sk-test-key
      YAML

      config.load_configuration

      expect(config.get("agent.max_turns")).to eq(50)
      expect(config.get("guardrails.content_safety.strict_mode")).to be true
    end

    it "loads environment variables" do
      allow(ENV).to receive(:[]).with("RAAF_ENVIRONMENT").and_return(nil)
      allow(ENV).to receive(:key?).with("OPENAI_API_KEY").and_return(true)
      allow(ENV).to receive(:key?).with("RAAF_MAX_TURNS").and_return(true)
      allow(ENV).to receive(:key?).with("RAAF_LOG_LEVEL").and_return(true)
      allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("sk-test-key")
      allow(ENV).to receive(:fetch).with("RAAF_MAX_TURNS", nil).and_return("15")
      allow(ENV).to receive(:fetch).with("RAAF_LOG_LEVEL", nil).and_return("debug")

      # Mock all other ENV_MAPPINGS keys as not present
      RAAF::Configuration::ENV_MAPPINGS.each_key do |key|
        next if %w[OPENAI_API_KEY RAAF_MAX_TURNS RAAF_LOG_LEVEL].include?(key)

        allow(ENV).to receive(:key?).with(key).and_return(false)
      end

      # Mock ENV.each for custom prefixed variables
      allow(ENV).to receive(:each)

      config.load_configuration

      expect(config.get("openai.api_key")).to eq("sk-test-key")
      expect(config.get("agent.max_turns")).to eq(15)
      expect(config.get("logging.level")).to eq("debug")
    end

    it "loads custom RAAF_ prefixed environment variables" do
      allow(ENV).to receive(:[]).with("RAAF_ENVIRONMENT").and_return(nil)

      # Mock ENV_MAPPINGS lookups first
      RAAF::Configuration::ENV_MAPPINGS.each_key do |key|
        allow(ENV).to receive(:key?).with(key).and_return(false)
      end

      # Mock the custom environment variables
      allow(ENV).to receive(:each).and_yield("RAAF_CUSTOM_SETTING", "custom_value").and_yield(
        "RAAF_NESTED_SETTING", "nested_value"
      )

      config.load_configuration

      expect(config.get("custom.setting")).to eq("custom_value")
      expect(config.get("nested.setting")).to eq("nested_value")
    end

    it "merges configuration in correct order" do
      # Create base config file
      File.write(File.join(config_path, "openai_agents.yml"), <<~YAML)
        agent:
          max_turns: 20
        openai:
          timeout: 100
      YAML

      # Create environment-specific config file
      File.write(File.join(config_path, "openai_agents.test.yml"), <<~YAML)
        agent:
          max_turns: 30
        logging:
          level: debug
      YAML

      # Set environment variables
      allow(ENV).to receive(:key?).with("RAAF_MAX_TURNS").and_return(true)
      allow(ENV).to receive(:key?).with("OPENAI_API_KEY").and_return(true)
      allow(ENV).to receive(:fetch).with("RAAF_MAX_TURNS", nil).and_return("40")
      allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("sk-env-key")

      # Mock other ENV_MAPPINGS keys as not present
      RAAF::Configuration::ENV_MAPPINGS.each_key do |key|
        next if %w[RAAF_MAX_TURNS OPENAI_API_KEY].include?(key)

        allow(ENV).to receive(:key?).with(key).and_return(false)
      end

      # Mock ENV.each for custom prefixed variables
      allow(ENV).to receive(:each)

      config = described_class.new(environment: "test", config_paths: [config_path], auto_load: false)
      config.load_configuration

      # Environment variable should override file configs
      expect(config.get("agent.max_turns")).to eq(40)
      expect(config.get("openai.api_key")).to eq("sk-env-key")
      # File configs should override defaults
      expect(config.get("openai.timeout")).to eq(100)
      expect(config.get("logging.level")).to eq("debug")
    end

    it "handles missing configuration files gracefully" do
      expect { config.load_configuration }.not_to raise_error
    end

    it "warns about invalid configuration files" do
      File.write(File.join(config_path, "openai_agents.yml"), "invalid: yaml: content:")

      # Allow the config to call log_warn without raising errors
      allow(config).to receive(:log_warn)

      # Verify that log_warn is called with the expected message
      expect(config).to receive(:log_warn).with(a_string_matching(/Failed to load config file/), any_args)

      config.load_configuration
    end
  end

  describe "#get" do
    let(:config) { described_class.new(auto_load: false) }

    before do
      config.instance_variable_set(:@config_data, {
                                     openai: {
                                       api_key: "sk-test",
                                       timeout: 60
                                     },
                                     agent: {
                                       max_turns: 10
                                     }
                                   })
    end

    it "retrieves simple values" do
      expect(config.get("openai.api_key")).to eq("sk-test")
      expect(config.get("agent.max_turns")).to eq(10)
    end

    it "retrieves nested values" do
      expect(config.get("openai.timeout")).to eq(60)
    end

    it "returns default for missing keys" do
      expect(config.get("nonexistent.key", "default")).to eq("default")
      expect(config.get("openai.nonexistent", "fallback")).to eq("fallback")
    end

    it "returns nil for missing keys without default" do
      expect(config.get("nonexistent.key")).to be_nil
    end

    it "handles empty key paths" do
      expect(config.get("", "default")).to eq("default")
    end
  end

  describe "#set" do
    let(:config) { described_class.new(auto_load: false) }

    before do
      config.instance_variable_set(:@config_data, {})
    end

    it "sets simple values" do
      config.set("openai.api_key", "sk-new-key")

      expect(config.get("openai.api_key")).to eq("sk-new-key")
    end

    it "sets nested values" do
      config.set("openai.timeout", 120)
      config.set("openai.api_key", "sk-test")

      expect(config.get("openai.timeout")).to eq(120)
      expect(config.get("openai.api_key")).to eq("sk-test")
    end

    it "creates nested hash structure" do
      config.set("deep.nested.value", "test")

      expect(config.get("deep.nested.value")).to eq("test")
    end

    it "coerces string values" do
      config.set("boolean.true", "true")
      config.set("boolean.false", "false")
      config.set("number.integer", "42")
      config.set("number.float", "3.14")
      config.set("string.value", "hello")

      expect(config.get("boolean.true")).to be true
      expect(config.get("boolean.false")).to be false
      expect(config.get("number.integer")).to eq(42)
      expect(config.get("number.float")).to eq(3.14)
      expect(config.get("string.value")).to eq("hello")
    end

    it "notifies watchers on change" do
      notifications = []
      config.watch { |c| notifications << c.get("test.key") }

      config.set("test.key", "value1")
      config.set("test.key", "value2")

      expect(notifications).to eq(%w[value1 value2])
    end
  end

  describe "method-based access" do
    let(:config) { described_class.new }

    it "provides method access to configuration sections" do
      expect(config.openai).to be_a(RAAF::ConfigurationSection)
      expect(config.agent).to be_a(RAAF::ConfigurationSection)
    end

    it "allows chained method access" do
      expect(config.openai.api_base).to eq("https://api.openai.com/v1")
      expect(config.agent.max_turns).to eq(10)
      expect(config.guardrails.content_safety.enabled).to be true
    end

    it "raises NoMethodError for non-existent sections" do
      expect { config.nonexistent_section }.to raise_error(NoMethodError)
    end
  end

  describe "#merge!" do
    let(:config) { described_class.new }

    it "merges additional configuration" do
      config.merge!({
                      agent: { max_turns: 20 },
                      custom: { setting: "value" }
                    })

      expect(config.get("agent.max_turns")).to eq(20)
      expect(config.get("custom.setting")).to eq("value")
    end

    it "deep merges nested hashes" do
      config.merge!({
                      openai: {
                        timeout: 90,
                        custom_setting: "new"
                      }
                    })

      expect(config.get("openai.timeout")).to eq(90)
      expect(config.get("openai.api_base")).to eq("https://api.openai.com/v1") # preserved
      expect(config.get("openai.custom_setting")).to eq("new")
    end

    it "notifies watchers after merge" do
      notifications = []
      config.watch { |c| notifications << c.get("agent.max_turns") }

      config.merge!({ agent: { max_turns: 25 } })

      expect(notifications).to include(25)
    end
  end

  describe "#validate" do
    let(:config) { described_class.new }

    it "returns empty array for valid configuration" do
      errors = config.validate
      expect(errors).to be_empty
    end

    it "validates required API keys in production" do
      config = described_class.new(environment: "production", auto_load: false)
      config.instance_variable_set(:@config_data, RAAF::Configuration::DEFAULT_CONFIG.dup)

      errors = config.validate
      expect(errors).to include(/OpenAI API key is required/)
    end

    it "validates numeric values" do
      config.set("agent.max_turns", -1)

      errors = config.validate
      expect(errors).to include(/agent.max_turns must be positive/)
    end

    it "validates URLs" do
      config.set("openai.api_base", "invalid-url")

      errors = config.validate
      expect(errors).to include(/openai.api_base must be a valid URL/)
    end

    it "validates file paths" do
      config.set("logging.file", "/nonexistent/directory/file.log")

      errors = config.validate
      expect(errors).to include(/logging.file directory does not exist/)
    end
  end

  describe "environment checks" do
    it "correctly identifies development environment" do
      config = described_class.new(environment: "development", auto_load: false)

      expect(config.development?).to be true
      expect(config.production?).to be false
      expect(config.test?).to be false
    end

    it "correctly identifies production environment" do
      config = described_class.new(environment: "production", auto_load: false)

      expect(config.production?).to be true
      expect(config.development?).to be false
      expect(config.test?).to be false
    end

    it "correctly identifies test environment" do
      config = described_class.new(environment: "test", auto_load: false)

      expect(config.test?).to be true
      expect(config.development?).to be false
      expect(config.production?).to be false
    end
  end

  describe "#watch" do
    let(:config) { described_class.new }

    it "adds configuration watchers" do
      notifications = []
      config.watch { |_c| notifications << "notified" }

      config.set("test.key", "value")

      expect(notifications).to include("notified")
    end

    it "supports multiple watchers" do
      notifications1 = []
      notifications2 = []

      config.watch { |c| notifications1 << c.get("test.key") }
      config.watch { |c| notifications2 << c.get("test.key") }

      config.set("test.key", "value")

      expect(notifications1).to include("value")
      expect(notifications2).to include("value")
    end
  end

  describe "export methods" do
    let(:config) { described_class.new }

    describe "#to_h" do
      it "exports configuration as hash" do
        hash = config.to_h

        expect(hash).to be_a(Hash)
        expect(hash).to have_key(:openai)
        expect(hash).to have_key(:agent)
      end

      it "excludes sensitive data by default" do
        config.set("openai.api_key", "sk-secret")

        hash = config.to_h

        expect(hash.dig(:openai, :api_key)).to eq("[REDACTED]")
      end

      it "includes sensitive data when requested" do
        config.set("openai.api_key", "sk-secret")

        hash = config.to_h(include_sensitive: true)

        expect(hash.dig(:openai, :api_key)).to eq("sk-secret")
      end
    end

    describe "#to_yaml" do
      it "exports configuration as YAML" do
        yaml = config.to_yaml

        expect(yaml).to be_a(String)
        expect(yaml).to include("openai:")
        expect(yaml).to include("agent:")
      end
    end

    describe "#to_json" do
      it "exports configuration as JSON" do
        json = config.to_json

        expect(json).to be_a(String)
        parsed = JSON.parse(json)
        expect(parsed).to have_key("openai")
        expect(parsed).to have_key("agent")
      end
    end
  end

  describe "#save_to_file" do
    let(:config) { described_class.new }
    let(:temp_file) { Tempfile.new(["config", ".yml"]) }

    after do
      temp_file.unlink
    end

    it "saves configuration to YAML file" do
      config.save_to_file(temp_file.path, format: :yaml)

      content = File.read(temp_file.path)
      expect(content).to include("openai:")
      expect(content).to include("agent:")
    end

    it "saves configuration to JSON file" do
      json_file = Tempfile.new(["config", ".json"])

      begin
        config.save_to_file(json_file.path, format: :json)

        content = File.read(json_file.path)
        parsed = JSON.parse(content)
        expect(parsed).to have_key("openai")
        expect(parsed).to have_key("agent")
      ensure
        json_file.unlink
      end
    end

    it "raises error for unsupported format" do
      expect { config.save_to_file(temp_file.path, format: :xml) }.to raise_error(ArgumentError)
    end
  end

  describe "ConfigurationSection" do
    let(:config) { described_class.new }
    let(:section) { config.openai }

    it "provides method access to section values" do
      expect(section.api_base).to eq("https://api.openai.com/v1")
      expect(section.timeout).to eq(60)
    end

    it "returns nested sections" do
      tools_section = config.tools
      expect(tools_section.file_search).to be_a(RAAF::ConfigurationSection)
      expect(tools_section.file_search.max_results).to eq(10)
    end

    it "raises NoMethodError for non-existent keys" do
      expect { section.nonexistent_key }.to raise_error(NoMethodError)
    end

    it "converts to hash" do
      hash = section.to_h
      expect(hash).to be_a(Hash)
      expect(hash).to have_key(:api_base)
      expect(hash).to have_key(:timeout)
    end
  end

  describe "error handling" do
    it "raises ConfigurationError for validation failures in production" do
      config = described_class.new(environment: "production", auto_load: false)

      expect { config.send(:validate_configuration) }.to raise_error(RAAF::ConfigurationError)
    end

    it "warns about validation failures in development" do
      config = described_class.new(environment: "development", auto_load: false)
      config.set("agent.max_turns", -1)

      # Allow the config to call log_warn without raising errors
      allow(config).to receive(:log_warn)

      # Verify that log_warn is called with the expected message
      expect(config).to receive(:log_warn).with(a_string_matching(/Configuration warnings/), any_args)

      config.send(:validate_configuration)
    end
  end

  describe "private methods" do
    let(:config) { described_class.new(auto_load: false) }

    describe "#deep_merge" do
      it "merges nested hashes correctly" do
        hash1 = { a: { b: 1, c: 2 }, d: 3 }
        hash2 = { a: { b: 10, e: 4 }, f: 5 }

        result = config.send(:deep_merge, hash1, hash2)

        expect(result).to eq({
                               a: { b: 10, c: 2, e: 4 },
                               d: 3,
                               f: 5
                             })
      end
    end

    describe "#deep_dup" do
      it "creates deep copies of nested structures" do
        original = { a: { b: [1, 2, 3] } }
        copy = config.send(:deep_dup, original)

        copy[:a][:b] << 4

        expect(original[:a][:b]).to eq([1, 2, 3])
        expect(copy[:a][:b]).to eq([1, 2, 3, 4])
      end
    end

    describe "#sensitive_key?" do
      it "identifies sensitive keys" do
        expect(config.send(:sensitive_key?, "api_key")).to be true
        expect(config.send(:sensitive_key?, "password")).to be true
        expect(config.send(:sensitive_key?, "secret")).to be true
        expect(config.send(:sensitive_key?, "token")).to be true
        expect(config.send(:sensitive_key?, "regular_key")).to be false
      end
    end

    describe "#valid_url?" do
      it "validates URLs correctly" do
        expect(config.send(:valid_url?, "https://api.example.com")).to be true
        expect(config.send(:valid_url?, "http://localhost:3000")).to be true
        expect(config.send(:valid_url?, "invalid-url")).to be false
        expect(config.send(:valid_url?, "ftp://example.com")).to be false
      end
    end

    describe "#coerce_value" do
      it "coerces string values to appropriate types" do
        expect(config.send(:coerce_value, "true")).to be true
        expect(config.send(:coerce_value, "false")).to be false
        expect(config.send(:coerce_value, "42")).to eq(42)
        expect(config.send(:coerce_value, "3.14")).to eq(3.14)
        expect(config.send(:coerce_value, "string")).to eq("string")
      end
    end
  end
end
