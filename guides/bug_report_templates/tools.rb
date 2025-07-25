# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "raaf"
  gem "rspec"
  # If you want to test against edge RAAF replace the raaf line with this:
  # gem "raaf", github: "enterprisemodules/raaf", branch: "main"
end

require "raaf"
require "rspec/autorun"

RSpec.describe "RAAF Tools Bug Report" do
  it "defines custom tools" do
    # Example tool that might have a bug
    def calculate_sum(a:, b:)
      a + b
    end

    agent = RAAF::Agent.new(
      name: "MathAgent",
      instructions: "You can calculate sums using the provided tool",
      model: "gpt-4o-mini"
    )
    
    agent.add_tool(method(:calculate_sum))
    
    expect(agent.tools).to have_key(:calculate_sum)
    
    # Test tool execution directly if needed
    result = calculate_sum(a: 2, b: 3)
    expect(result).to eq(5)
  end

  it "handles tool errors" do
    def divide_numbers(dividend:, divisor:)
      raise ArgumentError, "Cannot divide by zero" if divisor == 0
      dividend / divisor
    end

    agent = RAAF::Agent.new(
      name: "MathAgent",
      instructions: "You can divide numbers using the provided tool",
      model: "gpt-4o-mini"
    )
    
    agent.add_tool(method(:divide_numbers))
    
    # Test error handling
    expect { divide_numbers(dividend: 10, divisor: 0) }.to raise_error(ArgumentError)
  end

  it "handles complex return values" do
    def get_user_info(user_id:)
      {
        id: user_id,
        name: "Test User",
        email: "test@example.com",
        roles: ["user", "tester"],
        created_at: Time.now
      }
    end

    agent = RAAF::Agent.new(
      name: "UserAgent",
      instructions: "You can get user information using the provided tool",
      model: "gpt-4o-mini"
    )
    
    agent.add_tool(method(:get_user_info))
    
    result = get_user_info(user_id: 123)
    expect(result[:id]).to eq(123)
    expect(result).to be_a(Hash)
    expect(result[:roles]).to include("user")
  end

  it "supports class-based tools" do
    class WeatherTool
      def initialize(api_key = "test_key")
        @api_key = api_key
      end

      def get_weather(location:)
        # Mock weather data for testing
        {
          location: location,
          temperature: 22,
          conditions: "sunny",
          api_key_used: @api_key
        }
      end
    end

    weather_tool = WeatherTool.new
    agent = RAAF::Agent.new(
      name: "WeatherAgent",
      instructions: "You can get weather information using the provided tool",
      model: "gpt-4o-mini"
    )
    
    agent.add_tool(weather_tool.method(:get_weather))
    
    result = weather_tool.get_weather(location: "Tokyo")
    expect(result[:location]).to eq("Tokyo")
    expect(result[:api_key_used]).to eq("test_key")
  end

  # Add your specific test case here that demonstrates the bug
  it "reproduces your specific tool bug case" do
    # Replace this with your specific test case that demonstrates the tool bug
    # Include relevant setup, the action that causes the bug, and expectations
    expect(true).to be true # Replace this with your actual test case
  end
end