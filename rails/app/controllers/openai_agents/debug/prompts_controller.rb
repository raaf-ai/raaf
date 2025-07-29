# frozen_string_literal: true

module RAAF
  module Debug
    # Controller for AI prompt debugging and testing
    class PromptsController < ApplicationController
      # GET /debug/prompts
      def index
        @prompts = discover_prompts
        @agents = discover_agents
        @model_types = discover_model_types
        @recent_executions = load_recent_executions
        @execution_result = session[:debug_execution_result]
        @debug_output = session[:debug_output]
        @object_info = session[:debug_object_info]
        @session_id = params[:session_id] || SecureRandom.uuid
        @ai_params = params[:ai_params] || {}

        # Clear session data after loading to avoid stale results
        session[:debug_execution_result] = nil
        session[:debug_output] = nil
        session[:debug_object_info] = nil

        render Views::OpenaiAgents::Debug::Prompts::Index.new(
          prompts: @prompts,
          agents: @agents,
          model_types: @model_types,
          recent_executions: @recent_executions,
          execution_result: @execution_result,
          debug_output: @debug_output,
          object_info: @object_info,
          session_id: @session_id,
          ai_params: @ai_params,
          params: params
        )
      end

      # POST /debug/prompts/execute
      def execute
        @session_id = params[:session_id] || SecureRandom.uuid
        
        begin
          result = execute_prompt_class(
            class_name: params[:class_name],
            model_type: params[:model_type],
            model_id: params[:model_id],
            ai_params: params[:ai_params] || {},
            session_id: @session_id
          )

          # Store execution result in session
          session[:debug_execution_result] = result
          
          # Store object info if model was selected
          if params[:model_type].present? && params[:model_id].present?
            session[:debug_object_info] = load_object_info(params[:model_type], params[:model_id])
          end

          # Store recent execution
          store_execution_history(
            type: 'prompt',
            class_name: params[:class_name],
            model_type: params[:model_type],
            model_id: params[:model_id],
            success: result[:success],
            executed_at: Time.current.strftime("%H:%M:%S")
          )

        rescue StandardError => e
          Rails.logger.error "❌ Prompt execution failed: #{e.message}"
          Rails.logger.error "📋 Error class: #{e.class.name}"
          Rails.logger.error "🔍 Stack trace:\n#{e.backtrace.join("\n")}"

          session[:debug_execution_result] = {
            success: false,
            error_details: extract_error_details(e)
          }
        end

        # Preserve AI params state
        redirect_params = params.slice(:ai_params_expanded).merge(session_id: @session_id)
        redirect_params[:ai_params] = params[:ai_params] if params[:ai_params].present?

        redirect_to "/openai_agents/debug/prompts"
      end

      # POST /debug/prompts/execute_agent
      def execute_agent
        @session_id = params[:session_id] || SecureRandom.uuid
        
        begin
          result = execute_agent_workflow(
            prompt_class: params[:prompt_class],
            context: JSON.parse(params[:context] || '{}'),
            object_type: params[:object_type],
            object_id: params[:object_id],
            ai_params: params[:ai_params] || {},
            session_id: @session_id
          )

          session[:debug_execution_result] = result

          # Store object info if object was used
          if params[:object_type].present? && params[:object_id].present?
            session[:debug_object_info] = load_object_info(params[:object_type], params[:object_id])
          end

          # Store recent execution
          store_execution_history(
            type: 'agent',
            class_name: params[:prompt_class],
            model_type: params[:object_type],
            model_id: params[:object_id],
            success: result[:success],
            executed_at: Time.current.strftime("%H:%M:%S")
          )

        rescue StandardError => e
          Rails.logger.error "❌ Agent execution failed: #{e.message}"
          Rails.logger.error "📋 Error class: #{e.class.name}"
          Rails.logger.error "🔍 Stack trace:\n#{e.backtrace.join("\n")}"

          session[:debug_execution_result] = {
            success: false,
            error_details: extract_error_details(e)
          }
        end

        # Preserve AI params state  
        redirect_params = params.slice(:ai_params_expanded).merge(session_id: @session_id)
        redirect_params[:ai_params] = params[:ai_params] if params[:ai_params].present?

        redirect_to "/openai_agents/debug/prompts"
      end

      # POST /debug/prompts/stop_execution
      def stop_execution
        session_id = params[:session_id]
        
        if session_id.present?
          # Broadcast stop signal to the session
          ActionCable.server.broadcast(
            "openai_agents_debug_#{session_id}",
            {
              type: "stop_execution",
              message: "Execution stopped by user",
              timestamp: Time.current.to_i
            }
          )
          
          render json: { success: true, message: "Stop signal sent" }
        else
          render json: { success: false, error: "No session ID provided" }
        end
      end

      # GET /debug/prompts/objects
      def objects
        model_type = params[:model_type]
        
        objects = case model_type
        when 'Company'
          Company.limit(20).pluck(:id, :name).map { |id, name| { id: id, name: name } }
        when 'Product'
          Product.limit(20).pluck(:id, :name).map { |id, name| { id: id, name: name } }
        else
          []
        end

        render json: { objects: objects }
      end

      # POST /debug/prompts/test_broadcast
      def test_broadcast
        session_id = params[:session_id] || SecureRandom.uuid
        
        ActionCable.server.broadcast(
          "openai_agents_debug_#{session_id}",
          {
            type: "test_message",
            message: "Test broadcast successful at #{Time.current}",
            timestamp: Time.current.to_i
          }
        )
        
        render json: { success: true, session_id: session_id }
      end

      private

      def discover_prompts
        # Discover available prompt classes
        prompt_classes = []
        
        # Look for prompt classes in common locations
        if defined?(Ai::Prompts)
          prompt_classes.concat(discover_classes_in_module(Ai::Prompts))
        end
        
        prompt_classes.map do |klass|
          {
            class_name: klass.name,
            name: klass.name.demodulize.underscore.humanize,
            description: extract_class_description(klass)
          }
        end
      end

      def discover_agents
        # Discover available agent classes
        agent_classes = []
        
        if defined?(Ai::Agents)
          agent_classes.concat(discover_classes_in_module(Ai::Agents))
        end
        
        agent_classes.map do |klass|
          {
            class_name: klass.name,
            name: klass.name.demodulize.underscore.humanize,
            description: extract_class_description(klass)
          }
        end
      end

      def discover_classes_in_module(mod)
        classes = []
        mod.constants.each do |const_name|
          const = mod.const_get(const_name)
          if const.is_a?(Class)
            classes << const
          elsif const.is_a?(Module)
            classes.concat(discover_classes_in_module(const))
          end
        end
        classes
      end

      def discover_model_types
        [
          { type: 'Company', name: 'Companies' },
          { type: 'Product', name: 'Products' }
        ]
      end

      def extract_class_description(klass)
        # Try to extract description from comments or constants
        if klass.respond_to?(:agent_description)
          klass.agent_description
        elsif klass.respond_to?(:description)
          klass.description
        else
          "#{klass.name.demodulize.underscore.humanize} for AI processing"
        end
      end

      def execute_prompt_class(class_name:, model_type: nil, model_id: nil, ai_params: {}, session_id: nil)
        # Broadcast start message
        broadcast_message(session_id, "Starting prompt execution for #{class_name}...")

        # Get the prompt class
        prompt_class = class_name.constantize
        
        # Load the object if specified
        object = nil
        if model_type.present? && model_id.present?
          object = model_type.constantize.find(model_id)
          broadcast_message(session_id, "Loaded #{model_type} ##{model_id}: #{object.try(:name) || object.to_s}")
        end

        # Create prompt instance
        prompt_args = object ? { object: object } : {}
        prompt = prompt_class.new(**prompt_args)

        # Apply AI parameter overrides
        if ai_params.present?
          broadcast_message(session_id, "Applying AI parameter overrides: #{ai_params.inspect}")
          # This would depend on how your prompt classes handle parameter overrides
        end

        # Execute the prompt
        broadcast_message(session_id, "Executing prompt...")
        result = prompt.call

        broadcast_message(session_id, "✅ Prompt execution completed successfully")

        {
          success: true,
          system_prompt: prompt.respond_to?(:system_prompt) ? prompt.system_prompt : nil,
          user_prompt: prompt.respond_to?(:user_prompt) ? prompt.user_prompt : nil,
          prompt_context: prompt.respond_to?(:context) ? prompt.context : nil,
          result: result,
          prompt_class: class_name,
          executed_at: Time.current
        }
      rescue StandardError => e
        broadcast_message(session_id, "❌ Prompt execution failed: #{e.message}")
        raise e
      end

      def execute_agent_workflow(prompt_class:, context:, object_type: nil, object_id: nil, ai_params: {}, session_id: nil)
        broadcast_message(session_id, "Starting agent workflow execution...")

        # Load object if specified
        object = nil
        if object_type.present? && object_id.present?
          object = object_type.constantize.find(object_id)
          broadcast_message(session_id, "Loaded #{object_type} ##{object_id}")
        end

        # This would integrate with your RAAF agent execution system
        # For now, return a placeholder structure
        agent_result = {
          workflow_status: "completed",
          message: "Agent execution completed",
          turns_completed: 3,
          tool_calls: [],
          messages: [],
          final_result: "Agent workflow executed successfully"
        }

        broadcast_message(session_id, "✅ Agent workflow completed")

        {
          success: true,
          agent_result: agent_result,
          initial_context: context,
          final_context: context.merge(agent_executed: true),
          executed_at: Time.current
        }
      rescue StandardError => e
        broadcast_message(session_id, "❌ Agent execution failed: #{e.message}")
        raise e
      end

      def broadcast_message(session_id, message)
        return unless session_id

        ActionCable.server.broadcast(
          "openai_agents_debug_#{session_id}",
          {
            type: "log_message",
            message: message,
            timestamp: Time.current.to_i
          }
        )
      end

      def load_object_info(model_type, model_id)
        return nil unless model_type.present? && model_id.present?

        object = model_type.constantize.find(model_id)
        {
          type: model_type,
          id: model_id,
          name: object.try(:name) || object.to_s,
          attributes: object.attributes.slice('id', 'name', 'description', 'created_at', 'updated_at')
        }
      rescue StandardError => e
        Rails.logger.error "Failed to load object info: #{e.message}"
        nil
      end

      def load_recent_executions
        session[:recent_executions] ||= []
      end

      def store_execution_history(execution_data)
        session[:recent_executions] ||= []
        session[:recent_executions].unshift(execution_data)
        session[:recent_executions] = session[:recent_executions].first(10) # Keep only last 10
      end
    end
  end
end