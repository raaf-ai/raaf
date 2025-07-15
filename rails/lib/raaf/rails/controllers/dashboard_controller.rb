# frozen_string_literal: true

module RubyAIAgentsFactory
  module Rails
    module Controllers
      ##
      # Dashboard controller for AI agent management
      #
      # Provides web-based dashboard for managing AI agents, monitoring
      # conversations, and viewing analytics.
      #
      class DashboardController < BaseController
        before_action :authenticate_user!
        before_action :set_current_user

        ##
        # Dashboard home page
        #
        # Shows overview of agents, recent conversations, and key metrics.
        #
        def index
          @agents = current_user_agents.limit(5)
          @recent_conversations = recent_conversations.limit(10)
          @stats = dashboard_stats
        end

        ##
        # Agents management page
        #
        # Shows all user agents with creation, editing, and deployment options.
        #
        def agents
          @agents = current_user_agents.page(params[:page]).per(20)
          @agent = AgentModel.new if params[:new]
        end

        ##
        # Conversations page
        #
        # Shows conversation history with filtering and search capabilities.
        #
        def conversations
          @conversations = filter_conversations(current_user_conversations)
                           .page(params[:page]).per(20)
          @agents = current_user_agents.select(:id, :name)
        end

        ##
        # Analytics page
        #
        # Shows detailed analytics including usage metrics, performance data,
        # and conversation insights.
        #
        def analytics
          @time_range = params[:time_range] || "7d"
          @analytics = build_analytics(@time_range)
        end

        private

        def set_current_user
          @current_user = current_user
        end

        def current_user_agents
          AgentModel.where(user: current_user)
        end

        def current_user_conversations
          ConversationModel.joins(:agent)
                          .where(agents: { user: current_user })
        end

        def recent_conversations
          current_user_conversations.order(created_at: :desc)
        end

        def dashboard_stats
          {
            agents_count: current_user_agents.count,
            conversations_count: current_user_conversations.count,
            messages_count: MessageModel.joins(conversation: :agent)
                                      .where(agents: { user: current_user })
                                      .count,
            total_tokens: calculate_total_tokens,
            active_agents: current_user_agents.where(status: "active").count,
            avg_response_time: calculate_avg_response_time
          }
        end

        def filter_conversations(conversations)
          conversations = conversations.where(agent_id: params[:agent_id]) if params[:agent_id].present?
          conversations = conversations.where("created_at >= ?", Time.parse(params[:start_date])) if params[:start_date].present?
          conversations = conversations.where("created_at <= ?", Time.parse(params[:end_date])) if params[:end_date].present?
          conversations = conversations.where("messages.content ILIKE ?", "%#{params[:search]}%").joins(:messages) if params[:search].present?
          conversations
        end

        def build_analytics(time_range)
          start_date = case time_range
                       when "1d"
                         1.day.ago
                       when "7d"
                         7.days.ago
                       when "30d"
                         30.days.ago
                       when "90d"
                         90.days.ago
                       else
                         7.days.ago
                       end

          conversations = current_user_conversations.where("created_at >= ?", start_date)
          messages = MessageModel.joins(conversation: :agent)
                                .where(agents: { user: current_user })
                                .where("messages.created_at >= ?", start_date)

          {
            conversations_over_time: conversations_over_time_data(conversations, start_date),
            messages_by_agent: messages_by_agent_data(messages),
            token_usage: token_usage_data(messages),
            response_times: response_time_data(messages),
            popular_agents: popular_agents_data(conversations),
            error_rates: error_rate_data(conversations)
          }
        end

        def conversations_over_time_data(conversations, start_date)
          conversations.group_by_day(:created_at, range: start_date..Time.current)
                      .count
        end

        def messages_by_agent_data(messages)
          messages.joins(conversation: :agent)
                  .group("agents.name")
                  .count
        end

        def token_usage_data(messages)
          messages.where.not(usage: nil)
                  .group_by_day(:created_at)
                  .sum("(usage->>'total_tokens')::int")
        end

        def response_time_data(messages)
          messages.where.not(metadata: nil)
                  .where("metadata->>'response_time' IS NOT NULL")
                  .group_by_day(:created_at)
                  .average("(metadata->>'response_time')::float")
        end

        def popular_agents_data(conversations)
          conversations.joins(:agent)
                      .group("agents.name")
                      .count
                      .sort_by { |_, count| -count }
                      .first(10)
        end

        def error_rate_data(conversations)
          total = conversations.count
          errors = conversations.where("metadata->>'error' IS NOT NULL").count
          
          {
            total: total,
            errors: errors,
            rate: total > 0 ? (errors.to_f / total * 100).round(2) : 0
          }
        end

        def calculate_total_tokens
          MessageModel.joins(conversation: :agent)
                     .where(agents: { user: current_user })
                     .where.not(usage: nil)
                     .sum("(usage->>'total_tokens')::int")
        end

        def calculate_avg_response_time
          MessageModel.joins(conversation: :agent)
                     .where(agents: { user: current_user })
                     .where("metadata->>'response_time' IS NOT NULL")
                     .average("(metadata->>'response_time')::float")
                     &.round(2)
        end
      end
    end
  end
end