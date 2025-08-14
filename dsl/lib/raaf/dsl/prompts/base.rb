# frozen_string_literal: true

module RAAF
  module DSL
    module Prompts
      # Variable contract validation error
      #
      # Raised when prompt classes violate their variable contracts, such as:
      # - Missing required variables
      # - Context paths that don't exist
      # - Invalid variable declarations
      #
      # @since 0.1.0
      class VariableContractError < StandardError; end

      # Base class for AI prompts with Phlex-inspired design and variable contracts
      #
      # This class provides a structured, type-safe way to build AI prompts using heredocs
      # for natural text writing with Ruby interpolation support. It includes a powerful
      # variable contract system that validates inputs and provides clear error messages.
      #
      # Key features:
      # - Phlex-inspired API for building prompts
      # - Variable contract validation with required/optional variables
      # - Context path mapping for extracting values from nested data structures
      # - Multiple validation modes (strict, warn, lenient)
      # - Automatic memoization of context-mapped values
      # - Support for default values and fallbacks
      #
      # @abstract Subclasses must implement {#system} and {#user} methods
      #
      # @example Basic prompt with variable contracts
      #   class CompanyEnrichment < RAAF::DSL::Prompts::Base
      #     requires :company_name, :attributes
      #     optional :research_depth
      #     contract_mode :strict
      #
      #     def initialize(**kwargs)
      #       super
      #       @company = kwargs[:company]
      #       @attributes = kwargs[:attributes]
      #     end
      #
      #     def system
      #       <<~SYSTEM
      #         You are an AI assistant specializing in company data enrichment.
      #
      #         Your role is to research #{@company.name} and fill in these attributes:
      #         #{@attributes.map { |a| "- #{a}" }.join("\n")}
      #       SYSTEM
      #     end
      #
      #     def user
      #       <<~USER
      #         Research and enrich data for #{@company.name}.
      #         Current website: #{@company.website}
      #         Research depth: #{research_depth || 'standard'}
      #       USER
      #     end
      #   end
      #
      # @example Context path mapping
      #   class DocumentAnalysis < RAAF::DSL::Prompts::Base
      #     requires_from_context :document_name, path: [:document, :name]
      #     optional_from_context :analysis_type, path: [:processing_params, :analysis_type], default: "standard"
      #
      #     def system
      #       <<~SYSTEM
      #         You are a document analysis specialist.
      #         Document: #{document_name}
      #         Analysis type: #{analysis_type}
      #       SYSTEM
      #     end
      #
      #     def user
      #       "Please analyze the document using #{analysis_type} analysis."
      #     end
      #   end
      #
      # @example Usage with agents
      #   # In agent DSL configuration
      #   class MyAgent < RAAF::DSL::Agents::Base
      #     include RAAF::DSL::AgentDsl
      #
      #     agent_name "DocumentProcessor"
      #     prompt_class DocumentAnalysis
      #   end
      #
      # @see RAAF::DSL::AgentDsl For integration with agents
      # @since 0.1.0
      #
      class Base
        include RAAF::Logger

        # Sets up variable contract configuration for subclasses
        #
        # This callback ensures each subclass gets its own independent variable
        # contract configuration, preventing configuration leakage between classes.
        #
        # @param subclass [Class] The inheriting subclass
        # @api private
        #
        def self.inherited(subclass)
          super
          subclass.instance_variable_set(:@_required_variables, [])
          subclass.instance_variable_set(:@_optional_variables, [])
          subclass.instance_variable_set(:@_context_mappings, {})
          subclass.instance_variable_set(:@_contract_mode, :warn)
          subclass.instance_variable_set(:@_schema_config, {})
        end

        # @api private
        def self._required_variables
          @_required_variables ||= []
        end

        class << self
          # @api private
          attr_writer :_required_variables
        end

        # @api private
        def self._optional_variables
          @_optional_variables ||= []
        end

        class << self
          # @api private
          attr_writer :_optional_variables
        end

        # @api private
        def self._contract_mode
          @_contract_mode ||= :warn
        end

        class << self
          # @api private
          attr_writer :_contract_mode
        end

        # @api private
        def self._context_mappings
          @_context_mappings ||= {}
        end

        class << self
          # @api private
          attr_writer :_context_mappings
        end

        # @api private
        def self._schema_config
          @_schema_config ||= {}
        end

        class << self
          # @api private
          attr_writer :_schema_config
        end

        # Contract DSL methods
        def self.required(*variables, path: nil, default: nil)
          if path
            # Path-based usage: required :var, path: [:path], default: "value"
            raise ArgumentError, "Can only specify one variable when using path" if variables.length != 1
            raise ArgumentError, "Cannot specify default value for required variables" unless default.nil?

            variable_name = variables.first.to_sym
            self._required_variables = (_required_variables + [variable_name]).uniq

            _context_mappings[variable_name] = {
              path: path,
              default: nil,
              required: true
            }
          else
            # Direct usage: required :var1, :var2
            self._required_variables = (_required_variables + variables.map(&:to_sym)).uniq
          end
        end

        def self.optional(*variables, path: nil, default: nil)
          if path
            # Path-based usage: optional :var, path: [:path], default: "value"
            raise ArgumentError, "Can only specify one variable when using path" if variables.length != 1

            variable_name = variables.first.to_sym
            self._optional_variables = (_optional_variables + [variable_name]).uniq

            _context_mappings[variable_name] = {
              path: path,
              default: default,
              required: false
            }
          else
            # Direct usage: optional :var1, :var2
            self._optional_variables = (_optional_variables + variables.map(&:to_sym)).uniq
          end
        end

        def self.contract_mode(mode)
          unless %i[strict warn lenient].include?(mode)
            raise ArgumentError, "Contract mode must be :strict, :warn, or :lenient"
          end

          self._contract_mode = mode
        end

        # Configure response schema using the same DSL as agents
        #
        # This method allows prompt classes to define JSON schemas using the same
        # Complex Nested Schema DSL that's available in agent classes. The schema
        # can be used by agents for structured output validation.
        #
        # @param block [Proc] Block defining the schema structure
        # @return [Hash] The schema configuration hash
        #
        # @example Basic schema definition
        #   class MyPrompt < RAAF::DSL::Prompts::Base
        #     schema do
        #       field :name, type: :string, required: true
        #       field :age, type: :integer, range: 0..120
        #     end
        #   end
        #
        # @example Complex nested schema
        #   class CompanyAnalysis < RAAF::DSL::Prompts::Base
        #     schema do
        #       field :companies, type: :array, required: true do
        #         field :name, type: :string, required: true
        #         field :score, type: :integer, range: 0..100, required: true
        #         field :details, type: :object do
        #           field :industry, type: :string
        #           field :location, type: :string
        #         end
        #       end
        #       field :summary, type: :string, required: true
        #     end
        #   end
        #
        def self.schema(&block)
          if block_given?
            # Import SchemaBuilder from RAAF::DSL::Agent module
            schema_builder_class = const_get("::RAAF::DSL::Agent::SchemaBuilder")
            schema_builder = schema_builder_class.new
            schema_builder.instance_eval(&block)
            self._schema_config = schema_builder.build
          else
            _schema_config
          end
        end

        # Get the schema configuration for this prompt class
        #
        # @return [Hash] The JSON schema hash, or empty hash if no schema defined
        def self.get_schema
          _schema_config
        end

        # Check if this prompt class has a schema defined
        #
        # @return [Boolean] true if schema is defined, false otherwise
        def self.has_schema?
          !_schema_config.empty?
        end

        # Get all declared variables (required + optional)
        def self.declared_variables
          (_required_variables + _optional_variables).uniq
        end

        def initialize(**kwargs)
          @context = kwargs
          @context_variables = kwargs[:context_variables] if kwargs[:context_variables]
        end

        # Access to the stored context
        attr_reader :context
        attr_reader :context_variables

        # System prompt - override in subclasses
        def system
          raise NotImplementedError, "Subclasses must implement #system"
        end

        # User prompt - override in subclasses
        def user
          raise NotImplementedError, "Subclasses must implement #user"
        end

        # Get the schema for this prompt instance
        #
        # This allows agents to access the schema defined in the prompt class
        # for structured output configuration.
        #
        # @return [Hash] The JSON schema hash
        def schema
          self.class.get_schema
        end

        # Check if this prompt has a schema defined
        #
        # @return [Boolean] true if schema is defined, false otherwise
        def has_schema?
          self.class.has_schema?
        end

        # Render both prompts as a hash (for compatibility with PromptLoader)
        def render_messages
          {
            system: render(:system),
            user: render(:user)
          }
        end

        # Render a specific prompt type
        def render(type = nil)
          if type
            validate_variable_contract!
            render_prompt(type)
          else
            # Default to rendering both as a hash
            render_messages
          end
        end

        # Explicitly validate the variable contract
        #
        # This method can be called manually to validate context before rendering,
        # or it will be called automatically during rendering operations.
        #
        # @raise [VariableContractError] if validation fails
        # @return [void]
        def validate!
          validate_variable_contract!
        end

        protected

        # Render a specific prompt method
        def render_prompt(type)
          # Call the method and get its return value
          content = send(type)

          # If it's an array (multiple heredocs), join them
          if content.is_a?(Array)
            content.map(&:to_s).map(&:rstrip).join("\n\n")
          else
            content.to_s.rstrip
          end
        end

        def method_missing(method, *args, &block)
          # Check if this is a context-mapped variable
          if self.class._context_mappings.key?(method)
            get_context_mapped_value(method)
          elsif @context_variables&.has?(method)
            @context_variables.get(method)
          elsif @context&.key?(method)
            @context[method]
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          self.class._context_mappings.key?(method) ||
            @context_variables&.has?(method) ||
            @context&.key?(method) ||
            super
        end

        private

        # Get value for a context-mapped variable
        def get_context_mapped_value(variable_name)
          # Memoize the value
          instance_var = "@#{variable_name}"
          return instance_variable_get(instance_var) if instance_variable_defined?(instance_var)

          mapping = self.class._context_mappings[variable_name]
          path = mapping[:path]
          default_value = mapping[:default]

          # Navigate the context path using unified context variables
          value = if @context_variables
                    @context_variables.get_nested(path)
                  elsif @context
                    # Get the actual context (without the wrapper)
                    actual_context = @context[:context] || @context

                    # Use dig method which properly handles symbol keys
                    value = actual_context.dig(*path)

                    # If dig fails, log debug info for troubleshooting
                    if value.nil?
                      log_debug("Context path resolution failed",
                                variable_name: variable_name,
                                path: path.inspect,
                                context_keys: actual_context.keys.inspect,
                                first_path_key_exists: path.first && actual_context.key?(path.first))
                    end

                    value
                  else
                    nil
                  end

          # Treat empty strings as nil for required fields
          value = nil if value.is_a?(String) && value.strip.empty?

          # If value is nil and no default, provide clear error
          if value.nil? && default_value.nil? && mapping[:required]
            # Enhanced error message with context debugging
            error_msg = "Context path #{path.join(' -> ')} not found for required variable " \
                        "'#{variable_name}' in #{self.class.name}"
            if @context
              actual_context = @context[:context] || @context
              error_msg += "\nAvailable context keys: #{actual_context.keys.inspect}"
              if path.first && actual_context.key?(path.first)
                first_level = actual_context[path.first]
                error_msg += "\nAvailable at #{path.first}: #{if first_level.respond_to?(:keys)
                                                                first_level.keys.inspect
                                                              end}"
              end
            end
            raise VariableContractError, error_msg
          end

          # Use default if value is nil
          value = default_value if value.nil?

          # Store in instance variable for memoization
          instance_variable_set(instance_var, value)
          value
        end

        # Validate variable contracts based on the configured mode
        def validate_variable_contract!
          return if self.class._contract_mode == :lenient && self.class._required_variables.empty?

          # Validate context-mapped variables
          validate_context_mapped_variables!

          # Get non-context-mapped variables
          context_mapped_vars = self.class._context_mappings.keys
          provided_variables = @context.keys.map(&:to_sym)
          required_variables = self.class._required_variables - context_mapped_vars
          declared_variables = self.class.declared_variables - context_mapped_vars

          # Check for missing required variables (non-context-mapped)  
          missing_required = required_variables - provided_variables
          
          # Try to resolve missing variables from context_variables (agent context)
          if missing_required.any? && @context_variables
            resolved_variables = {}
            still_missing = []
            
            missing_required.each do |var|
              if @context_variables.has?(var)
                resolved_variables[var] = @context_variables.get(var)
              else
                still_missing << var
              end
            end
            
            # Add resolved variables to context
            @context.merge!(resolved_variables) if resolved_variables.any?
            
            # Only raise error for variables that couldn't be resolved
            missing_required = still_missing
          end
          
          if missing_required.any?
            raise VariableContractError,
                  "Missing required variables for #{self.class.name}: #{missing_required.join(', ')}"
          end

          # Check for unused variables (only in strict or warn mode)
          return unless %i[strict warn].include?(self.class._contract_mode) && declared_variables.any?

          # Get context root keys that are used by context mappings
          context_root_keys = self.class._context_mappings.values.map { |m| m[:path].first }.uniq

          # Variables that are legitimately used (either directly or as context roots)
          legitimately_used = declared_variables + context_root_keys

          # Filter out special RAAF parameters that shouldn't be considered unused
          raaf_special_params = [:context_variables]
          unused_variables = provided_variables - legitimately_used - raaf_special_params
          return unless unused_variables.any?

          message = "Unused variables provided to #{self.class.name}: #{unused_variables.join(', ')}"

          raise VariableContractError, message if self.class._contract_mode == :strict

          # warn mode
          log_warn("Variable contract warning",
                   message: message,
                   unused_variables: unused_variables,
                   prompt_class: self.class.name)
        end

        # Validate that context paths exist for required context-mapped variables
        def validate_context_mapped_variables!
          missing_paths = []

          self.class._context_mappings.each do |variable_name, mapping|
            next unless mapping[:required] # Only check required variables

            path = mapping[:path]

            # Get the actual context (without the wrapper)
            actual_context = @context[:context] || @context

            # Use dig method which properly handles symbol keys
            value = actual_context.dig(*path)

            # Treat empty strings as nil for validation
            value = nil if value.is_a?(String) && value.strip.empty?

            if value.nil? && mapping[:default].nil?
              missing_paths << "#{variable_name} (context path: #{path.join(' -> ')})"
            end
          end

          return unless missing_paths.any?

          raise VariableContractError,
                "Missing required context paths for #{self.class.name}: #{missing_paths.join(', ')}"
        end
      end
    end
  end
end
