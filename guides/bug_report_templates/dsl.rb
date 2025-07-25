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

RSpec.describe "RAAF DSL Bug Report" do
  it "builds basic agents with DSL" do
    agent = RAAF::DSL::AgentBuilder.build do
      name "TestAgent"
      instructions "You are a helpful test agent"
      model "gpt-4o-mini"
    end
    
    expect(agent.name).to eq("TestAgent")
    expect(agent.model).to eq("gpt-4o-mini")
    expect(agent.instructions).to include("helpful test agent")
  end

  it "builds agents with tools using DSL" do
    agent = RAAF::DSL::AgentBuilder.build do
      name "ToolAgent"
      instructions "You have access to tools"
      model "gpt-4o-mini"
      
      tool :get_time do
        Time.now.to_s
      end
      
      tool :add_numbers do |a:, b:|
        a + b
      end
    end
    
    expect(agent.tools).to have_key(:get_time)
    expect(agent.tools).to have_key(:add_numbers)
  end

  it "integrates external tools with DSL" do
    def external_weather_tool(location:)
      "Weather in #{location}: sunny, 22°C"
    end

    agent = RAAF::DSL::AgentBuilder.build do
      name "WeatherAgent"
      instructions "You can get weather information"
      model "gpt-4o-mini"
      
      tool :get_weather, &method(:external_weather_tool)
    end
    
    expect(agent.tools).to have_key(:get_weather)
    
    # Test tool execution
    result = external_weather_tool(location: "Tokyo")
    expect(result).to include("Tokyo")
    expect(result).to include("sunny")
  end

  it "supports preset capabilities in DSL" do
    agent = RAAF::DSL::AgentBuilder.build do
      name "PresetAgent"
      instructions "Agent with preset capabilities"
      model "gpt-4o-mini"
      
      # Test preset usage (these might not exist yet)
      # use_web_search
      # use_file_operations
      # use_code_interpreter
    end
    
    expect(agent.name).to eq("PresetAgent")
  end

  it "resolves prompts with parameter validation" do
    # Test Ruby prompt class
    class TestPrompt < RAAF::DSL::Prompts::Base
      requires :topic
      optional :tone, default: "friendly"
      
      def system
        "You are a #{@tone} assistant specializing in #{@topic}."
      end
      
      def user
        "Please help with questions about #{@topic}."
      end
    end

    prompt = TestPrompt.new(topic: "Ruby programming", tone: "professional")
    
    expect(prompt.system).to include("professional assistant")
    expect(prompt.system).to include("Ruby programming")
    expect(prompt.user).to include("Ruby programming")
  end

  it "builds environment-specific configurations" do
    config = RAAF::DSL::ConfigurationBuilder.build do
      environment :development do
        model "gpt-4o-mini"
        temperature 0.3
        max_tokens 1000
      end
      
      environment :production do
        model "gpt-4o"
        temperature 0.1
        max_tokens 2000
      end
    end
    
    dev_config = config.for_environment(:development)
    prod_config = config.for_environment(:production)
    
    expect(dev_config[:model]).to eq("gpt-4o-mini")
    expect(prod_config[:model]).to eq("gpt-4o")
  end

  it "builds multi-agent workflows" do
    workflow = RAAF::DSL::WorkflowBuilder.build do
      name "TestWorkflow"
      
      agent :research do
        name "Researcher"
        instructions "Research topics thoroughly"
        model "gpt-4o"
      end
      
      agent :writer do
        name "Writer"
        instructions "Write compelling content"
        model "gpt-4o"
      end
      
      handoff from: :research, to: :writer
    end
    
    expect(workflow.name).to eq("TestWorkflow")
    expect(workflow.agents).to have_key(:research)
    expect(workflow.agents).to have_key(:writer)
  end

  # Add your specific test case here that demonstrates the bug
  it "reproduces your specific DSL bug case" do
    # Replace this with your specific test case that demonstrates the DSL bug
    expect(true).to be true # Replace this with your actual test case
  end
end