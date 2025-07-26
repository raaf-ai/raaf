# frozen_string_literal: true

module RAAF
  module DSL
    module Debugging
      # Provides debugging capabilities for inspecting prompts
      #
      # This class helps developers debug prompt generation by displaying
      # the actual prompts sent to the AI after all variable substitutions
      # and template processing. It's essential for verifying that prompts
      # are being constructed correctly with the expected context.
      #
      # @example Basic usage
      #   inspector = PromptInspector.new
      #   inspector.inspect_prompts(agent_instance)
      #
      # @example With custom logger
      #   inspector = PromptInspector.new(logger: my_logger)
      #   inspector.inspect_prompts(agent)
      #
      # @example In debugging workflow
      #   debugger = SwarmDebugger.new(enabled: true)
      #   prompt_inspector = PromptInspector.new
      #
      #   debugger.debug_agent_execution(agent, context) do
      #     prompt_inspector.inspect_prompts(agent)
      #     agent.run
      #   end
      #
      # @since 0.1.0
      class PromptInspector
        # @return [Logger] The logger instance used for output
        attr_reader :logger

        # Initialize a new prompt inspector
        #
        # @param logger [Logger] Logger instance for output (defaults to Rails.logger)
        # @example
        #   inspector = PromptInspector.new(logger: custom_logger)
        def initialize(logger: Rails.logger)
          @logger = logger
        end

        # Display formatted prompts and context for debugging
        #
        # Inspects the agent's prompt configuration and displays the actual
        # prompts that will be sent to the AI, including system and user
        # prompts with all variables substituted. Handles errors gracefully
        # when prompts cannot be rendered.
        #
        # @param agent_instance [Object] The agent instance whose prompts to inspect
        # @return [void]
        # @example
        #   inspector.inspect_prompts(my_agent)
        def inspect_prompts(agent_instance)
          return unless agent_instance.respond_to?(:debug_enabled) && agent_instance.debug_enabled

          logger.info "   📝 PROMPT INSPECTION:"
          logger.info "   #{'=' * 80}"

          begin
            # Try to get and display actual prompts with substituted values
            if agent_instance.class.respond_to?(:prompt_class) && agent_instance.class.prompt_class
              prompt_klass = agent_instance.class.prompt_class

              logger.info "   📝 PROMPTS:"
              logger.info "   🔧 Prompt Class: #{prompt_klass.name}"

              # Try to get the actual prompts using DSL internal methods
              display_actual_prompts(prompt_klass, agent_instance)
            else
              logger.info "   ⚠️ No prompt class defined for #{agent_instance.class.name}"
              logger.debug "   Available class methods: #{agent_instance.class.methods.grep(/prompt/).join(', ')}"
            end
          rescue StandardError => e
            logger.info "   ⚠️ Prompt debug error: #{e.class.name}: #{e.message}"
            logger.debug "   Stack: #{e.backtrace.first(3).join(', ')}"
          end

          logger.info "   #{'=' * 80}"
        end

        private

        def display_actual_prompts(prompt_klass, agent_instance)
          # Try to manually instantiate the prompt class to show actual content
          # Create a basic instance with proper context variables
          context_variables = if agent_instance.respond_to?(:context_variables)
                                agent_instance.context_variables.to_h
                              else
                                {}
                              end
          processing_params = { num_prospects: 5 }
          class_name = agent_instance.class.name || "UnknownAgent"

          prompt_context = context_variables.merge({
                                                     processing_params: processing_params,
                                                     agent_name: class_name.demodulize,
                                                     context_variables: agent_instance.context_variables
                                                   })

          prompt_instance = prompt_klass.new(**prompt_context)

          display_system_prompt(prompt_instance)
          display_user_prompt(prompt_instance)
        rescue StandardError => e
          logger.info "   ⚠️ Could not instantiate prompt class: #{e.message}"
          logger.info "   📋 Prompt class: #{prompt_klass.name}"
          logger.info "   📝 Available methods: #{prompt_klass.instance_methods(false).join(', ')}"
        end

        def display_system_prompt(prompt_instance)
          return unless prompt_instance.respond_to?(:system)

          logger.info "   #{'-' * 60}"
          logger.info "   🔧 SYSTEM PROMPT (with substitutions):"
          begin
            system_prompt = prompt_instance.system
            format_and_log_prompt(system_prompt, "   │ ")
          rescue StandardError => e
            logger.info "   │ ⚠️ Could not render system prompt: #{e.message}"
          end
        end

        def display_user_prompt(prompt_instance)
          return unless prompt_instance.respond_to?(:user)

          logger.info "   #{'-' * 60}"
          logger.info "   👤 USER PROMPT (with substitutions):"
          begin
            user_prompt = prompt_instance.user
            format_and_log_prompt(user_prompt, "   │ ")
          rescue StandardError => e
            logger.info "   │ ⚠️ Could not render user prompt: #{e.message}"
          end
        end

        def format_and_log_prompt(prompt_text, prefix)
          return unless prompt_text

          # Clean and format the prompt text
          lines = prompt_text.strip.split("\n")
          lines.first(20).each do |line| # Show more lines for full context
            # Keep full lines for debugging
            logger.info "#{prefix}#{line}"
          end

          logger.info "#{prefix}... (#{lines.length - 20} more lines)" if lines.length > 20
        end
      end
    end
  end
end
