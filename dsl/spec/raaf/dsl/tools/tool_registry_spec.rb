# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Tools::ToolRegistry do
  # Test tool classes
  class TestTool
    def call
      "test tool result"
    end
  end

  class TestAgent
    def execute
      "test agent result"
    end
  end

  class TestWeatherTool
    def call(location:)
      "Weather in #{location}: sunny"
    end
  end

  class TestCalculatorTool
    def call(expression:)
      "Result: #{expression}"
    end
  end

  # Invalid tool class for testing
  class InvalidTool
    # No call or execute method
  end

  before do
    # Clear registry before each test
    described_class.clear!

    # Register default namespaces that might be expected
    described_class.register_namespace("RAAF::DSL::Tools")
    described_class.register_namespace("RAAF::Tools")
    described_class.register_namespace("Ai::Tools")
  end

  describe ".register" do
    it "registers a tool with a symbol name" do
      result = described_class.register(:test, TestTool)
      expect(result).to eq(:test)
      expect(described_class.get(:test)).to eq(TestTool)
    end

    it "registers a tool with a string name" do
      described_class.register("test", TestTool)
      expect(described_class.get(:test)).to eq(TestTool)
    end

    it "registers tool with options" do
      described_class.register(:weather, TestWeatherTool,
                              aliases: [:forecast, :clima],
                              enabled: true,
                              namespace: "Weather::Tools",
                              metadata: { version: "1.0" })

      expect(described_class.get(:weather)).to eq(TestWeatherTool)
      expect(described_class.get(:forecast)).to eq(TestWeatherTool)
      expect(described_class.get(:clima)).to eq(TestWeatherTool)
    end

    it "tracks registration statistics" do
      initial_stats = described_class.statistics
      described_class.register(:test, TestTool)

      new_stats = described_class.statistics
      expect(new_stats[:registered_tools]).to eq(initial_stats[:registered_tools] + 1)
    end

    it "auto-registers the tool's namespace" do
      described_class.register(:test, TestTool)

      # Should have inferred and registered the Global namespace
      expect(described_class.namespaces).to include("Global")
    end

    it "infers namespace from tool class" do
      described_class.register(:test, TestTool)

      tool_info = described_class.tool_info
      expect(tool_info[:test][:namespace]).to eq("Global")
    end
  end

  describe ".get" do
    before do
      described_class.register(:test, TestTool)
      described_class.register(:weather, TestWeatherTool, aliases: [:forecast])
    end

    it "retrieves registered tool by symbol" do
      expect(described_class.get(:test)).to eq(TestTool)
    end

    it "retrieves registered tool by string" do
      expect(described_class.get("test")).to eq(TestTool)
    end

    it "retrieves tool by alias" do
      expect(described_class.get(:forecast)).to eq(TestWeatherTool)
    end

    it "tracks lookup statistics" do
      initial_lookups = described_class.statistics[:lookups]
      described_class.get(:test)

      expect(described_class.statistics[:lookups]).to eq(initial_lookups + 1)
      expect(described_class.statistics[:cache_hits]).to eq(initial_lookups + 1)
    end

    context "when tool not found" do
      it "raises ToolNotFoundError in strict mode" do
        expect { described_class.get(:nonexistent) }
          .to raise_error(RAAF::DSL::Tools::ToolRegistry::ToolNotFoundError) do |error|
            expect(error.tool_name).to eq(:nonexistent)
            expect(error.message).to include("Tool 'nonexistent' not found")
            expect(error.message).to include("Available tools:")
          end
      end

      it "returns nil in non-strict mode" do
        expect(described_class.get(:nonexistent, strict: false)).to be_nil
      end

      it "provides suggestions for similar names" do
        # Mock levenshtein to be available for this test
        allow(Object.const_defined?(:LEVENSHTEIN_AVAILABLE)).to receive(:nil?).and_return(false)
        stub_const('LEVENSHTEIN_AVAILABLE', true)

        # Mock the Levenshtein module
        levenshtein_module = double('Levenshtein')
        allow(levenshtein_module).to receive(:distance).with("tset", "test").and_return(1)
        allow(levenshtein_module).to receive(:distance).with("tset", "weather").and_return(7)
        stub_const('Levenshtein', levenshtein_module)

        expect { described_class.get(:tset) }
          .to raise_error(RAAF::DSL::Tools::ToolRegistry::ToolNotFoundError) do |error|
            expect(error.suggestions).to include(:test)
          end
      end

      it "handles fallback matching when levenshtein unavailable" do
        # Mock levenshtein as unavailable
        stub_const('LEVENSHTEIN_AVAILABLE', false)

        expect { described_class.get(:tes) }
          .to raise_error(RAAF::DSL::Tools::ToolRegistry::ToolNotFoundError) do |error|
            expect(error.suggestions).to include(:test)
          end
      end
    end
  end

  describe ".registered?" do
    before do
      described_class.register(:test, TestTool)
    end

    it "returns true for registered tools" do
      expect(described_class.registered?(:test)).to be true
    end

    it "returns false for unregistered tools" do
      expect(described_class.registered?(:nonexistent)).to be false
    end

    it "handles string names" do
      expect(described_class.registered?("test")).to be true
    end
  end

  describe ".register_namespace" do
    it "registers a namespace" do
      described_class.register_namespace("Custom::Tools")
      expect(described_class.namespaces).to include("Custom::Tools")
    end

    it "handles nil namespace gracefully" do
      expect { described_class.register_namespace(nil) }.not_to raise_error
    end

    it "converts namespace to string" do
      module_name = double("module")
      allow(module_name).to receive(:to_s).and_return("MockModule")

      described_class.register_namespace(module_name)
      expect(described_class.namespaces).to include("MockModule")
    end
  end

  describe ".auto_discover_tools" do
    # Create a mock namespace module for testing
    module TestNamespace
      class DiscoverableTool
        def call
          "discovered"
        end
      end

      class NotATool
        # No call or execute method
      end

      class DiscoverableAgent
        def execute
          "agent discovered"
        end
      end
    end

    before do
      # Stub constantize to return our test namespace
      allow("TestNamespace").to receive(:constantize).and_return(TestNamespace)
      described_class.register_namespace("TestNamespace")
    end

    it "discovers tools in registered namespaces" do
      # Mock the constantize method to return our test namespace
      allow_any_instance_of(String).to receive(:constantize) do |str|
        case str
        when "TestNamespace"
          TestNamespace
        else
          raise NameError, "uninitialized constant #{str}"
        end
      end

      count = described_class.auto_discover_tools

      expect(count).to be > 0
      expect(described_class.registered?(:discoverable)).to be true
    end

    it "handles force re-discovery" do
      allow_any_instance_of(String).to receive(:constantize) do |str|
        case str
        when "TestNamespace"
          TestNamespace
        else
          raise NameError, "uninitialized constant #{str}"
        end
      end

      # First discovery
      first_count = described_class.auto_discover_tools

      # Second discovery without force (should use cache)
      second_count = described_class.auto_discover_tools
      expect(second_count).to eq(0)  # From cache

      # Force re-discovery
      third_count = described_class.auto_discover_tools(force: true)
      expect(third_count).to eq(first_count)
    end

    it "handles missing namespaces gracefully" do
      described_class.register_namespace("NonExistent::Namespace")
      expect { described_class.auto_discover_tools }.not_to raise_error
    end
  end

  describe ".names" do
    it "returns empty array when no tools registered" do
      expect(described_class.names).to eq([])
    end

    it "returns sorted list of tool names" do
      described_class.register(:zebra, TestTool)
      described_class.register(:alpha, TestWeatherTool)
      described_class.register(:beta, TestCalculatorTool)

      expect(described_class.names).to eq([:alpha, :beta, :zebra])
    end
  end

  describe ".available_tools" do
    it "returns tool names as strings" do
      described_class.register(:test, TestTool)
      described_class.register(:weather, TestWeatherTool)

      available = described_class.available_tools
      expect(available).to be_an(Array)
      expect(available).to include("test", "weather")
    end
  end

  describe ".tool_info" do
    before do
      described_class.register(:test, TestTool,
                              enabled: true,
                              aliases: [:testing])
    end

    it "returns detailed tool information" do
      info = described_class.tool_info

      expect(info[:test]).to include(
        class_name: "TestTool",
        namespace: "Global",
        enabled: true,
        registered_at: kind_of(Time)
      )
    end

    it "filters by namespace" do
      described_class.register(:other, TestWeatherTool, namespace: "Weather")

      weather_info = described_class.tool_info(namespace: "Weather")
      expect(weather_info.keys).to eq([:other])

      global_info = described_class.tool_info(namespace: "Global")
      expect(global_info.keys).to include(:test)
      expect(global_info.keys).not_to include(:other)
    end

    it "handles tools with aliases" do
      info = described_class.tool_info
      aliases = info[:test][:aliases]

      expect(aliases).to include(:test, :testing)
    end
  end

  describe ".clear!" do
    it "clears all registered tools and caches" do
      described_class.register(:test, TestTool)
      expect(described_class.names).not_to be_empty

      described_class.clear!
      expect(described_class.names).to be_empty
      expect(described_class.statistics[:registered_tools]).to eq(0)
    end
  end

  describe ".statistics" do
    it "provides comprehensive statistics" do
      stats = described_class.statistics

      expect(stats).to include(
        :registered_tools,
        :registered_namespaces,
        :lookups,
        :cache_hits,
        :discoveries,
        :not_found,
        :cache_hit_ratio
      )
    end

    it "calculates cache hit ratio correctly" do
      described_class.register(:test, TestTool)

      # Make some lookups
      3.times { described_class.get(:test) }
      2.times { described_class.get(:nonexistent, strict: false) }

      stats = described_class.statistics
      expect(stats[:cache_hit_ratio]).to eq(0.6)  # 3 hits out of 5 lookups
    end

    it "handles zero lookups for cache hit ratio" do
      stats = described_class.statistics
      expect(stats[:cache_hit_ratio]).to eq(0.0)
    end
  end

  describe ".validate_tool_class!" do
    it "validates tool classes with call method" do
      expect { described_class.validate_tool_class!(TestTool) }.not_to raise_error
    end

    it "validates tool classes with execute method" do
      expect { described_class.validate_tool_class!(TestAgent) }.not_to raise_error
    end

    it "raises error for non-class objects" do
      expect { described_class.validate_tool_class!("not a class") }
        .to raise_error(ArgumentError, /Tool must be a class/)
    end

    it "raises error for classes without required methods" do
      expect { described_class.validate_tool_class!(InvalidTool) }
        .to raise_error(ArgumentError, /must implement #call or #execute method/)
    end
  end

  describe ".suggest_similar_tools" do
    before do
      described_class.register(:weather, TestWeatherTool)
      described_class.register(:calculator, TestCalculatorTool)
      described_class.register(:test, TestTool)
    end

    context "with levenshtein available" do
      before do
        stub_const('LEVENSHTEIN_AVAILABLE', true)

        # Mock Levenshtein distance calculations
        levenshtein_module = double('Levenshtein')
        allow(levenshtein_module).to receive(:distance) do |str1, str2|
          # Simple mock implementation
          if str1 == "wheather"
            case str2
            when "weather" then 1
            when "calculator" then 8
            when "test" then 7
            else 10
            end
          else
            str1.length + str2.length
          end
        end
        stub_const('Levenshtein', levenshtein_module)
      end

      it "suggests tools with low edit distance" do
        suggestions = described_class.suggest_similar_tools(:wheather)
        expect(suggestions).to include(:weather)
        expect(suggestions).not_to include(:calculator)  # Distance too high
      end

      it "limits number of suggestions" do
        suggestions = described_class.suggest_similar_tools(:sometypo, max_suggestions: 1)
        expect(suggestions.length).to be <= 1
      end

      it "filters out suggestions with high distance" do
        suggestions = described_class.suggest_similar_tools(:completelydifferent)
        expect(suggestions).to be_empty
      end
    end

    context "without levenshtein" do
      before do
        stub_const('LEVENSHTEIN_AVAILABLE', false)
      end

      it "uses fallback string matching" do
        suggestions = described_class.suggest_similar_tools(:calc)
        expect(suggestions).to include(:calculator)
      end

      it "handles partial matches" do
        suggestions = described_class.suggest_similar_tools(:weath)
        expect(suggestions).to include(:weather)
      end

      it "limits suggestions in fallback mode" do
        suggestions = described_class.suggest_similar_tools(:e, max_suggestions: 2)
        expect(suggestions.length).to be <= 2
      end
    end
  end

  describe "ToolNotFoundError" do
    let(:error) { RAAF::DSL::Tools::ToolRegistry::ToolNotFoundError.new(:missing, [:suggestion1, :suggestion2]) }

    it "includes tool name and suggestions" do
      expect(error.tool_name).to eq(:missing)
      expect(error.suggestions).to eq([:suggestion1, :suggestion2])
    end

    it "formats helpful error message" do
      expect(error.message).to include("Tool 'missing' not found")
      expect(error.message).to include("Did you mean: :suggestion1, :suggestion2?")
      expect(error.message).to include("Available tools:")
    end

    it "handles empty suggestions" do
      error_no_suggestions = RAAF::DSL::Tools::ToolRegistry::ToolNotFoundError.new(:missing, [])
      expect(error_no_suggestions.message).not_to include("Did you mean")
    end
  end

  describe "private methods" do
    describe "class name generation" do
      it "generates appropriate class name variants" do
        variants = described_class.send(:generate_class_name_variants, :weather)
        expect(variants).to include("WeatherTool", "Weather", "WeatherAgent", "WeatherService")
      end

      it "handles underscore names" do
        variants = described_class.send(:generate_class_name_variants, :weather_forecast)
        expect(variants).to include("WeatherForecastTool", "WeatherForecast")
      end
    end

    describe "tool class detection" do
      it "identifies classes with call method" do
        expect(described_class.send(:tool_class?, TestTool)).to be true
      end

      it "identifies classes with execute method" do
        expect(described_class.send(:tool_class?, TestAgent)).to be true
      end

      it "rejects classes without required methods" do
        expect(described_class.send(:tool_class?, InvalidTool)).to be false
      end

      it "rejects non-class objects" do
        expect(described_class.send(:tool_class?, "not a class")).to be false
      end
    end

    describe "namespace inference" do
      it "infers namespace from class name" do
        tool_class = double("tool_class")
        allow(tool_class).to receive(:name).and_return("RAAF::DSL::Tools::SomeTool")

        namespace = described_class.send(:infer_namespace, tool_class)
        expect(namespace).to eq("RAAF::DSL::Tools")
      end

      it "handles global classes" do
        tool_class = double("tool_class")
        allow(tool_class).to receive(:name).and_return("GlobalTool")

        namespace = described_class.send(:infer_namespace, tool_class)
        expect(namespace).to eq("Global")
      end

      it "handles classes with no name" do
        tool_class = double("tool_class")
        allow(tool_class).to receive(:name).and_return(nil)

        namespace = described_class.send(:infer_namespace, tool_class)
        expect(namespace).to eq("Global")
      end
    end
  end

  describe "thread safety" do
    it "handles concurrent registrations" do
      threads = 10.times.map do |i|
        Thread.new do
          tool_class = Class.new do
            def call
              "result #{i}"
            end
          end
          described_class.register("tool_#{i}".to_sym, tool_class)
        end
      end

      threads.each(&:join)

      expect(described_class.statistics[:registered_tools]).to eq(10)
      expect(described_class.names.length).to eq(10)
    end

    it "handles concurrent lookups" do
      described_class.register(:test, TestTool)

      threads = 50.times.map do
        Thread.new do
          described_class.get(:test)
        end
      end

      results = threads.map(&:value)
      expect(results).to all(eq(TestTool))
    end
  end

  describe "edge cases" do
    it "handles empty registry gracefully" do
      expect(described_class.names).to eq([])
      expect(described_class.available_tools).to eq([])
      expect(described_class.tool_info).to eq({})
      expect(described_class.suggest_similar_tools(:anything)).to eq([])
    end

    it "handles duplicate registrations" do
      described_class.register(:test, TestTool)
      described_class.register(:test, TestWeatherTool)  # Overwrite

      expect(described_class.get(:test)).to eq(TestWeatherTool)
    end

    it "handles symbol/string conversions consistently" do
      described_class.register("test", TestTool)

      expect(described_class.get(:test)).to eq(TestTool)
      expect(described_class.get("test")).to eq(TestTool)
      expect(described_class.registered?(:test)).to be true
      expect(described_class.registered?("test")).to be true
    end
  end

  describe "integration scenarios" do
    it "supports complete tool lifecycle" do
      # Register tool with options
      described_class.register(:weather, TestWeatherTool,
                              aliases: [:forecast],
                              enabled: true,
                              namespace: "Weather::Tools")

      # Verify registration
      expect(described_class.registered?(:weather)).to be true
      expect(described_class.registered?(:forecast)).to be true

      # Get tool and verify it works
      tool_class = described_class.get(:weather)
      tool_instance = tool_class.new
      result = tool_instance.call(location: "Tokyo")
      expect(result).to eq("Weather in Tokyo: sunny")

      # Check tool info
      info = described_class.tool_info[:weather]
      expect(info[:class_name]).to eq("TestWeatherTool")
      expect(info[:namespace]).to eq("Weather::Tools")

      # Verify statistics
      stats = described_class.statistics
      expect(stats[:registered_tools]).to eq(1)
      expect(stats[:lookups]).to eq(1)
    end

    it "handles namespace auto-discovery workflow" do
      # Register namespace
      described_class.register_namespace("CustomTools")

      # Auto-discover should handle missing namespace gracefully
      expect { described_class.auto_discover_tools }.not_to raise_error

      # Verify namespace is tracked
      expect(described_class.namespaces).to include("CustomTools")
    end
  end
end