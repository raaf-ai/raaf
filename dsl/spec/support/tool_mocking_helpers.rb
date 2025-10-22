# frozen_string_literal: true

# RSpec helpers for mocking tool resolution in tests
#
# These helpers make it easy to mock tool resolution in tests without
# needing to define actual tool classes. This is particularly useful
# for testing agent behavior in isolation.
#
# @example Basic usage in RSpec
#   RSpec.describe MyAgent do
#     include ToolMockingHelpers
#
#     before do
#       mock_tool_resolution(:web_search, MockWebSearchTool)
#     end
#
#     it "uses mocked tool" do
#       agent = MyAgent.new
#       # Tool will resolve to MockWebSearchTool
#     end
#   end
#
module ToolMockingHelpers
  # Mock a tool resolution in the ToolRegistry
  #
  # @param tool_name [Symbol, String] The tool identifier to mock
  # @param tool_class [Class] The mock tool class to return
  # @param options [Hash] Additional options for the mock
  # @option options [Boolean] :with_suggestions Include suggestions in error response
  # @option options [Array<String>] :searched_namespaces Namespaces to report as searched
  #
  # @example Mock successful resolution
  #   mock_tool_resolution(:tavily_search, MockTavilyTool)
  #
  # @example Mock failed resolution with suggestions
  #   mock_tool_resolution(:unknown_tool, nil,
  #     with_suggestions: ["Did you mean: :web_search?"])
  #
  def mock_tool_resolution(tool_name, tool_class, options = {})
    if tool_class
      # Mock successful resolution
      allow(RAAF::ToolRegistry).to receive(:resolve)
        .with(tool_name)
        .and_return(tool_class)

      allow(RAAF::ToolRegistry).to receive(:resolve_with_details)
        .with(tool_name)
        .and_return({
          success: true,
          tool_class: tool_class,
          identifier: tool_name,
          searched_namespaces: options[:searched_namespaces] || [],
          suggestions: []
        })
    else
      # Mock failed resolution
      allow(RAAF::ToolRegistry).to receive(:resolve)
        .with(tool_name)
        .and_return(nil)

      allow(RAAF::ToolRegistry).to receive(:resolve_with_details)
        .with(tool_name)
        .and_return({
          success: false,
          tool_class: nil,
          identifier: tool_name,
          searched_namespaces: options[:searched_namespaces] || ["Ai::Tools", "RAAF::Tools"],
          suggestions: options[:with_suggestions] || []
        })
    end
  end

  # Mock multiple tool resolutions at once
  #
  # @param tools_hash [Hash] Map of tool names to tool classes
  #
  # @example
  #   mock_tools(
  #     web_search: MockWebSearchTool,
  #     calculator: MockCalculatorTool,
  #     weather: MockWeatherTool
  #   )
  #
  def mock_tools(tools_hash)
    tools_hash.each do |tool_name, tool_class|
      mock_tool_resolution(tool_name, tool_class)
    end
  end

  # Stub the entire ToolRegistry to return specific tools
  #
  # This is useful when you want to control all tool resolution
  # in a test and ensure no real tools are loaded.
  #
  # @param registry_stub [Hash] Complete registry stub
  #
  # @example
  #   stub_tool_registry(
  #     web_search: MockWebSearchTool,
  #     calculator: MockCalculatorTool
  #   )
  #
  def stub_tool_registry(registry_stub = {})
    allow(RAAF::ToolRegistry).to receive(:resolve) do |identifier|
      registry_stub[identifier.to_sym]
    end

    allow(RAAF::ToolRegistry).to receive(:resolve_with_details) do |identifier|
      tool_class = registry_stub[identifier.to_sym]
      {
        success: !tool_class.nil?,
        tool_class: tool_class,
        identifier: identifier,
        searched_namespaces: ["Ai::Tools", "RAAF::Tools"],
        suggestions: tool_class.nil? ? generate_mock_suggestions(identifier, registry_stub.keys) : []
      }
    end

    # Also stub the list method
    allow(RAAF::ToolRegistry).to receive(:list).and_return(registry_stub.keys)
    allow(RAAF::ToolRegistry).to receive(:registered?) do |name|
      registry_stub.key?(name.to_sym)
    end
  end

  # Create a mock tool class with predefined behavior
  #
  # @param name [String] Name for the mock tool class
  # @param response [Hash, Proc] Response to return from call method
  # @yield Block to define custom methods on the tool class
  #
  # @example Simple mock tool
  #   tool = create_mock_tool("WebSearch", { results: ["result1", "result2"] })
  #
  # @example Mock tool with dynamic response
  #   tool = create_mock_tool("Calculator") do |expression:|
  #     { result: eval(expression) }
  #   end
  #
  # @example Mock tool with custom methods
  #   tool = create_mock_tool("CustomTool") do
  #     def validate_params(params)
  #       params.key?(:required_field)
  #     end
  #   end
  #
  def create_mock_tool(name, response = nil, &block)
    Class.new do
      define_singleton_method(:name) { "Mock#{name}Tool" }

      if response.is_a?(Proc)
        define_method(:call, &response)
      elsif response
        define_method(:call) do |**_args|
          response
        end
      elsif block_given?
        class_eval(&block)
      else
        define_method(:call) do |**args|
          { mock_response: true, args: args }
        end
      end

      # Add common tool interface methods
      def initialize(**_options)
        # Mock tools can accept options
      end

      def to_s
        self.class.name
      end
    end
  end

  # Create a test fixture tool with standard behavior
  #
  # @param type [Symbol] Type of fixture (:search, :calculator, :weather, etc.)
  # @return [Class] A mock tool class with appropriate behavior
  #
  # @example
  #   search_tool = create_fixture_tool(:search)
  #   calc_tool = create_fixture_tool(:calculator)
  #
  def create_fixture_tool(type)
    case type
    when :search
      create_mock_tool("Search") do |query:|
        {
          results: [
            { title: "Result 1 for #{query}", url: "https://example.com/1" },
            { title: "Result 2 for #{query}", url: "https://example.com/2" }
          ],
          total: 2
        }
      end
    when :calculator
      create_mock_tool("Calculator") do |expression:|
        # Safe evaluation for testing
        { result: expression.length * 10 } # Mock calculation
      end
    when :weather
      create_mock_tool("Weather") do |location:|
        {
          location: location,
          temperature: 72,
          conditions: "sunny",
          forecast: "Clear skies"
        }
      end
    when :file
      create_mock_tool("File") do |path:, content: nil|
        if content
          { success: true, action: "write", path: path }
        else
          { success: true, action: "read", path: path, content: "Mock file content" }
        end
      end
    else
      create_mock_tool(type.to_s.capitalize)
    end
  end

  # Verify that a tool was resolved with specific parameters
  #
  # @param tool_name [Symbol] The tool that should have been resolved
  # @param times [Integer] Number of times it should have been resolved
  #
  # @example
  #   expect_tool_resolution(:web_search)
  #   expect_tool_resolution(:calculator, times: 2)
  #
  def expect_tool_resolution(tool_name, times: 1)
    if times == 1
      expect(RAAF::ToolRegistry).to have_received(:resolve).with(tool_name).once
    else
      expect(RAAF::ToolRegistry).to have_received(:resolve).with(tool_name).exactly(times).times
    end
  end

  # Clear all tool mocks and restore original behavior
  #
  # This is useful in after hooks to ensure clean state between tests.
  #
  # @example
  #   after do
  #     clear_tool_mocks!
  #   end
  #
  def clear_tool_mocks!
    RSpec::Mocks.space.proxy_for(RAAF::ToolRegistry)&.reset if defined?(RAAF::ToolRegistry)
  end

  # Test helper to simulate tool loading in different orders
  #
  # @param loading_order [Array<Symbol>] Order to simulate loading
  # @yield Block to execute with simulated loading order
  #
  # @example
  #   with_tool_loading_order([:tool_b, :tool_a]) do
  #     agent = MyAgent.new
  #     # Tools loaded in specified order
  #   end
  #
  def with_tool_loading_order(loading_order)
    original_resolve = RAAF::ToolRegistry.method(:resolve)

    resolution_count = 0
    allow(RAAF::ToolRegistry).to receive(:resolve) do |identifier|
      if loading_order.include?(identifier.to_sym)
        resolution_count += 1
        # Simulate delayed loading based on position
        sleep(0.001 * loading_order.index(identifier.to_sym))
      end
      original_resolve.call(identifier)
    end

    yield
  ensure
    clear_tool_mocks!
  end

  private

  # Generate mock suggestions for failed tool resolution
  def generate_mock_suggestions(identifier, available_tools)
    return [] if available_tools.empty?

    # Find similar tool names
    similar = available_tools.select do |tool|
      tool.to_s.include?(identifier.to_s[0..2]) ||
        identifier.to_s.include?(tool.to_s[0..2])
    end.first(3)

    similar.map { |tool| "Did you mean: :#{tool}?" }
  end
end

# Shared RSpec examples for tool behavior
RSpec.shared_examples "a mockable tool" do
  it "responds to call method" do
    expect(subject).to respond_to(:call)
  end

  it "accepts keyword arguments" do
    expect { subject.call(test: "value") }.not_to raise_error
  end

  it "returns a hash response" do
    result = subject.call(test: "value")
    expect(result).to be_a(Hash)
  end
end

RSpec.shared_examples "tool resolution behavior" do |tool_name|
  it "resolves the tool successfully" do
    expect(RAAF::ToolRegistry.resolve(tool_name)).not_to be_nil
  end

  it "returns detailed resolution information" do
    result = RAAF::ToolRegistry.resolve_with_details(tool_name)
    expect(result[:success]).to be true
    expect(result[:tool_class]).not_to be_nil
  end
end

# Configure RSpec to include helpers
RSpec.configure do |config|
  config.include ToolMockingHelpers

  # Automatically clear tool mocks after each test
  config.after(:each) do
    clear_tool_mocks! if respond_to?(:clear_tool_mocks!)
  end
end