# frozen_string_literal: true

RSpec.describe RAAF::Rails::Helpers::AgentHelper do
  # Create a test class that includes the helper
  let(:helper_class) do
    Class.new do
      include RAAF::Rails::Helpers::AgentHelper

      # Mock Rails helper methods
      def link_to(text, path, options = {})
        "<a href='#{path}' class='#{options[:class]}'>#{text}</a>"
      end

      def content_tag(tag, content_or_options = nil, options = {}, &block)
        # Handle Rails-style content_tag where second arg can be options if block given
        if block_given?
          options = content_or_options || {}
          content = block.call
        else
          content = content_or_options
        end

        class_attr = options[:class] ? " class='#{options[:class]}'" : ""
        "<#{tag}#{class_attr}>#{content}</#{tag}>"
      end

      def tag(name, options = {})
        "<#{name} class='#{options[:class]}' />"
      end

      def simple_format(text)
        "<p>#{text}</p>"
      end

      def blank?
        false
      end
    end
  end

  let(:helper) { helper_class.new }

  describe "#agent_status_badge" do
    it "returns a span with status class for deployed agents" do
      result = helper.agent_status_badge("deployed")
      expect(result).to include("<span")
      expect(result).to include("status-deployed")
      expect(result).to include("Deployed")
    end

    it "returns a span with status class for draft agents" do
      result = helper.agent_status_badge("draft")
      expect(result).to include("<span")
      expect(result).to include("status-draft")
      expect(result).to include("Draft")
    end

    it "returns a span with status class for error agents" do
      result = helper.agent_status_badge("error")
      expect(result).to include("<span")
      expect(result).to include("status-error")
      expect(result).to include("Error")
    end

    it "capitalizes the status text" do
      result = helper.agent_status_badge("active")
      expect(result).to include("Active")
    end
  end

  describe "#format_agent_response" do
    it "formats a simple text response" do
      response = { content: "Hello, world!" }
      result = helper.format_agent_response(response)
      expect(result).to include("agent-response")
      expect(result).to include("Hello, world!")
    end

    it "handles responses with metadata" do
      response = {
        content: "Response text",
        metadata: { model: "gpt-4", tokens: 10 }
      }
      result = helper.format_agent_response(response)
      expect(result).to include("Response text")
      expect(result).to include("agent-response")
    end

    it "handles nil responses" do
      result = helper.format_agent_response(nil)
      expect(result).to include("agent-response")
    end

    it "handles string responses" do
      result = helper.format_agent_response("Simple string")
      expect(result).to include("Simple string")
      expect(result).to include("agent-response")
    end
  end

  describe "#agent_model_options" do
    it "returns an array of model options" do
      options = helper.agent_model_options
      expect(options).to be_an(Array)
      expect(options).to include(%w[GPT-4o gpt-4o])
      expect(options).to include(["GPT-4 Turbo", "gpt-4-turbo"])
      expect(options).to include(["GPT-3.5 Turbo", "gpt-3.5-turbo"])
    end
  end

  describe "#agent_conversation_path" do
    it "generates the correct path for agent conversation" do
      agent = double(id: 123)
      path = helper.agent_conversation_path(agent)
      expect(path).to eq("/agents/123/chat")
    end

    it "handles agent with string id" do
      agent = double(id: "abc123")
      path = helper.agent_conversation_path(agent)
      expect(path).to eq("/agents/abc123/chat")
    end
  end

  describe "#agent_deploy_button" do
    it "creates a deploy button for draft agents" do
      agent = double(id: 1, status: "draft")
      button = helper.agent_deploy_button(agent)
      expect(button).to include("href='/agents/1/deploy'")
      expect(button).to include("btn-primary")
      expect(button).to include("Deploy Agent")
    end

    it "creates an undeploy button for deployed agents" do
      agent = double(id: 2, status: "deployed")
      button = helper.agent_deploy_button(agent)
      expect(button).to include("href='/agents/2/undeploy'")
      expect(button).to include("btn-danger")
      expect(button).to include("Undeploy Agent")
    end

    it "returns nil for error status" do
      agent = double(id: 3, status: "error")
      button = helper.agent_deploy_button(agent)
      expect(button).to be_nil
    end
  end

  describe "#format_agent_tools" do
    it "formats an array of tools" do
      tools = %w[web_search calculator weather]
      result = helper.format_agent_tools(tools)
      expect(result).to include("agent-tools")
      expect(result).to include("Web Search")
      expect(result).to include("Calculator")
      expect(result).to include("Weather")
    end

    it "handles empty tools array" do
      result = helper.format_agent_tools([])
      expect(result).to include("agent-tools")
      expect(result).to include("No tools configured")
    end

    it "handles nil tools" do
      result = helper.format_agent_tools(nil)
      expect(result).to include("agent-tools")
      expect(result).to include("No tools configured")
    end

    it "handles tools with underscores" do
      tools = %w[get_weather search_web]
      result = helper.format_agent_tools(tools)
      expect(result).to include("Get Weather")
      expect(result).to include("Search Web")
    end
  end

  describe "#render_agent_metrics" do
    it "renders metrics for an agent" do
      agent = double(
        total_conversations: 42,
        success_rate: 95.5,
        avg_response_time: 1.234
      )

      metrics = helper.render_agent_metrics(agent)
      expect(metrics).to include("agent-metrics")
      expect(metrics).to include("42")
      expect(metrics).to include("95.5%")
      expect(metrics).to include("1.23s")
    end
  end
end
