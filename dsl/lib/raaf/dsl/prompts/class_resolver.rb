# frozen_string_literal: true

require_relative "../prompts/prompt_resolver"

module RAAF
  module DSL
    module PromptResolvers
      ##
      # Resolver for Class-based prompt classes from RAAF::DSL
      #
      class ClassResolver < PromptResolver
        def initialize(**options)
          super(name: :class, **options)
        end

        ##
        # Check if the spec is a Phlex prompt class or instance
        #
        def can_resolve?(prompt_spec)
          case prompt_spec
          when Class
            # Check if it's a subclass of DSL prompt base
            defined?(RAAF::DSL::Prompts::Base) &&
              prompt_spec < RAAF::DSL::Prompts::Base
          when Hash
            # Check for class specification
            prompt_spec[:type] == :phlex ||
              (prompt_spec[:class] && can_resolve?(prompt_spec[:class]))
          else
            # Check if it's an instance of a DSL prompt
            defined?(RAAF::DSL::Prompts::Base) &&
              prompt_spec.is_a?(RAAF::DSL::Prompts::Base)
          end
        end

        ##
        # Resolve Phlex prompt to RAAF::Prompt
        #
        def resolve(prompt_spec, context = {})
          return nil unless can_resolve?(prompt_spec)

          
          prompt_instance = case prompt_spec
                            when Class
                              # Instantiate with context as keyword arguments
                              prompt_spec.new(**context)
                            when Hash
                              # Handle hash specification
                              klass = prompt_spec[:class]
                              params = prompt_spec[:params] || context
                              klass.new(**params)
                            else
                              # Already an instance
                              prompt_spec
                            end

          # Convert to RAAF::Prompt
          build_prompt(prompt_instance, context)
        rescue StandardError => e
          # Log detailed error information
          error_details = {
            prompt_class: prompt_spec.name,
            error_class: e.class.name,
            error_message: e.message,
            backtrace: e.backtrace.first(10)
          }
          
          # Log error if logger is available
          if defined?(RAAF::Logger) && self.class.included_modules.include?(RAAF::Logger)
            log_error("Failed to resolve prompt class", **error_details)
          end
          
          # Re-raise with full context and stack trace
          full_error_message = "Failed to resolve prompt class #{prompt_spec.name}: #{e.class.name} - #{e.message}\n" \
                              "This usually indicates an error in the prompt's system/user methods or missing required context.\n" \
                              "Original error: #{e.message}\n" \
                              "Full stack trace:\n#{e.backtrace.join("\n")}"
          
          raise RAAF::DSL::Error, full_error_message
        end

        private

        def build_prompt(prompt_instance, _context)
          # Build system and user messages
          system_content = prompt_instance.respond_to?(:system) ? prompt_instance.system : nil
          user_content = prompt_instance.respond_to?(:user) ? prompt_instance.user : nil

          # Get prompt ID and version if available
          prompt_id = if prompt_instance.respond_to?(:prompt_id)
                        prompt_instance.prompt_id
                      else
                        prompt_instance.class.name.split("::").last.downcase
                      end

          version = prompt_instance.respond_to?(:version) ? prompt_instance.version : "1.0"

          # Build messages array
          messages = []
          messages << { role: "system", content: system_content } if system_content
          messages << { role: "user", content: user_content } if user_content

          # Get schema if defined
          schema = if prompt_instance.respond_to?(:schema)
                     prompt_instance.schema
                   elsif prompt_instance.class.respond_to?(:schema)
                     prompt_instance.class.schema
                   end

          # Create the prompt
          Prompt.new(
            id: prompt_id,
            version: version,
            messages: messages,
            schema: schema,
            variables: extract_variables(prompt_instance)
          )
        end

        def extract_variables(prompt_instance)
          # Extract instance variables as prompt variables
          vars = {}

          prompt_instance.instance_variables.each do |var|
            key = var.to_s.delete_prefix("@").to_sym
            value = prompt_instance.instance_variable_get(var)

            # Skip internal variables
            next if %i[context options].include?(key)

            vars[key] = value
          end

          vars
        end
      end
    end
  end
end
