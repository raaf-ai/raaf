# frozen_string_literal: true

module RAAF
  module Rails
    module Helpers
      # AgentHelper provides Rails view and controller helper methods for RAAF agents
      module AgentHelper
        # Placeholder methods for RAAF agent integration
        # These methods can be extended as needed for Rails integration
        
        # Helper method to render agent responses in views
        def render_agent_response(response)
          return "" unless response.present?
          
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
                       "badge badge-info"
                     when "completed", "success"
                       "badge badge-success"
                     when "failed", "error"
                       "badge badge-danger"
                     else
                       "badge badge-secondary"
                     end
          
          content_tag(:span, status.to_s.humanize, class: css_class)
        end
        
        # Helper method to check if RAAF is available
        def raaf_available?
          defined?(RAAF) && RAAF.respond_to?(:version)
        end
        
        private
        
        # Fallback for simple_format if not available (in controllers)
        def simple_format(text)
          return text unless respond_to?(:content_tag)
          content_tag(:p, text)
        end
      end
    end
  end
end