# frozen_string_literal: true

require "json"

module RAAF
  module Rails
    module Helpers
      ##
      # Helper methods for agent-related views and controllers
      #
      # This module provides a comprehensive set of helper methods for
      # displaying agent information, formatting responses, and building
      # agent-related UI components. It's automatically included in
      # Rails controllers and views.
      #
      # @example Using in views
      #   <%= agent_status_badge(@agent) %>
      #   <%= format_agent_response(@response) %>
      #   <%= render_agent_metrics(@agent) %>
      #
      # @example Using in controllers
      #   class AgentsController < ApplicationController
      #     include RAAF::Rails::Helpers::AgentHelper
      #
      #     def show
      #       @agent = find_agent(params[:id])
      #       @metrics = calculate_agent_metrics(@agent)
      #     end
      #   end
      #
      module AgentHelper
        # Helper method to render agent responses in views
        def render_agent_response(response)
          return "" if response.nil? || (response.respond_to?(:empty?) && response.empty?)

          case response
          when String
            simple_format(response)
          when Hash
            content_tag(:pre, JSON.pretty_generate(response), class: "agent-response")
          else
            content_tag(:div, response.to_s, class: "agent-response")
          end
        end

        # Helper method to format agent status
        def agent_status_badge(status)
          css_class = case status.to_s.downcase
                      when "running", "in_progress"
                        "badge badge-info status-#{status.to_s.downcase}"
                      when "completed", "success"
                        "badge badge-success status-#{status.to_s.downcase}"
                      when "failed", "error"
                        "badge badge-danger status-#{status.to_s.downcase}"
                      when "deployed"
                        "badge badge-secondary status-deployed"
                      when "draft"
                        "badge badge-secondary status-draft"
                      else
                        "badge badge-secondary status-#{status.to_s.downcase}"
                      end

          content_tag(:span, status.to_s.humanize, class: css_class)
        end

        # Helper method to check if RAAF is available
        def raaf_available?
          defined?(RAAF) && RAAF.respond_to?(:version)
        end

        # Format agent response with metadata
        def format_agent_response(response)
          if response.nil?
            content_tag(:div, "", class: "agent-response")
          elsif response.is_a?(String)
            content_tag(:div, simple_format(response), class: "agent-response")
          elsif response.is_a?(Hash)
            content = response[:content] || response["content"] || response.to_s
            content_tag(:div, content, class: "agent-response")
          else
            content_tag(:div, response.to_s, class: "agent-response")
          end
        end

        # Generate conversation path for an agent
        def agent_conversation_path(agent)
          "/agents/#{agent.id}/chat"
        end

        # Return available model options for agents
        def agent_model_options
          [
            ["GPT-4o", "gpt-4o"],
            ["GPT-4 Turbo", "gpt-4-turbo"],
            ["GPT-3.5 Turbo", "gpt-3.5-turbo"],
            ["Claude 3 Opus", "claude-3-opus"],
            ["Claude 3 Sonnet", "claude-3-sonnet"]
          ]
        end

        # Format list of agent tools
        def format_agent_tools(tools)
          return content_tag(:div, "No tools configured", class: "agent-tools") if tools.blank?

          tool_items = tools.map do |tool|
            formatted_tool = tool.to_s.gsub("_", " ").split.map(&:capitalize).join(" ")
            content_tag(:span, formatted_tool, class: "tool-badge")
          end.join(" ")

          content_tag(:div, tool_items, class: "agent-tools")
        end

        # Generate deploy/undeploy button for agent
        def agent_deploy_button(agent)
          case agent.status
          when "draft"
            link_to("Deploy Agent", "/agents/#{agent.id}/deploy", class: "btn btn-primary")
          when "deployed"
            link_to("Undeploy Agent", "/agents/#{agent.id}/undeploy", class: "btn btn-danger")
          else
            nil
          end
        end

        # Render agent metrics
        def render_agent_metrics(agent)
          content_tag(:div, class: "agent-metrics") do
            safe_join([
                        content_tag(:div, "Conversations: #{agent.total_conversations}"),
                        content_tag(:div, "Success Rate: #{agent.success_rate}%"),
                        content_tag(:div, "Avg Response Time: #{agent.avg_response_time.round(2)}s")
                      ])
          end
        end

        private

        # Fallback for safe_join if not available
        def safe_join(array, sep = nil)
          return array.join(sep || "") unless respond_to?(:raw)

          # Use ActionView's safe_join if available
          if defined?(ActionView::Helpers::OutputSafetyHelper)
            super
          else
            # Safely join without using raw
            array.map { |item| ERB::Util.html_escape(item) }.join(sep || "")
          end
        end

        # Fallback for simple_format if not available (in controllers)
        def simple_format(text)
          return text unless respond_to?(:content_tag)

          content_tag(:p, text)
        end
      end
    end
  end
end
