# frozen_string_literal: true

module RAAF
  module DSL
    ##
    # Tool builder for DSL-based tool construction
    #
    # Provides a fluent interface for building tools using declarative syntax
    # with support for parameters, validation, and advanced tool features.
    #
    class ToolBuilder
      include RAAF::Logging

      @@count = 0

      # @return [Symbol] Tool name
      attr_reader :tool_name

      # @return [Hash] Tool configuration
      attr_reader :config

      ##
      # Initialize tool builder
      #
      # @param name [Symbol] Tool name
      #
      def initialize(name)
        @tool_name = name
        @config = {
          parameters: {
            type: "object",
            properties: {},
            required: []
          }
        }
        @execution_block = nil
        @validation_rules = []
        @middleware = []
        @@count += 1
      end

      ##
      # Set tool description
      #
      # @param description [String] Tool description
      #
      def description(description)
        @config[:description] = description
      end

      ##
      # Define a parameter
      #
      # @param name [Symbol] Parameter name
      # @param type [Symbol] Parameter type
      # @param options [Hash] Parameter options
      #
      def parameter(name, type: :string, required: false, **options)
        @config[:parameters][:properties][name] = {
          type: type.to_s,
          **options
        }

        return unless required

        @config[:parameters][:required] << name
      end

      ##
      # Define string parameter
      #
      # @param name [Symbol] Parameter name
      # @param options [Hash] Parameter options
      #
      def string_parameter(name, **options)
        parameter(name, type: :string, **options)
      end

      ##
      # Define number parameter
      #
      # @param name [Symbol] Parameter name
      # @param options [Hash] Parameter options
      #
      def number_parameter(name, **options)
        parameter(name, type: :number, **options)
      end

      ##
      # Define integer parameter
      #
      # @param name [Symbol] Parameter name
      # @param options [Hash] Parameter options
      #
      def integer_parameter(name, **options)
        parameter(name, type: :integer, **options)
      end

      ##
      # Define boolean parameter
      #
      # @param name [Symbol] Parameter name
      # @param options [Hash] Parameter options
      #
      def boolean_parameter(name, **options)
        parameter(name, type: :boolean, **options)
      end

      ##
      # Define array parameter
      #
      # @param name [Symbol] Parameter name
      # @param items [Hash] Array items schema
      # @param options [Hash] Parameter options
      #
      def array_parameter(name, items: {}, **options)
        parameter(name, type: :array, items: items, **options)
      end

      ##
      # Define object parameter
      #
      # @param name [Symbol] Parameter name
      # @param properties [Hash] Object properties
      # @param options [Hash] Parameter options
      #
      def object_parameter(name, properties: {}, **options)
        parameter(name, type: :object, properties: properties, **options)
      end

      ##
      # Define enum parameter
      #
      # @param name [Symbol] Parameter name
      # @param values [Array] Enum values
      # @param options [Hash] Parameter options
      #
      def enum_parameter(name, values:, **options)
        parameter(name, type: :string, enum: values, **options)
      end

      ##
      # Set parameter defaults
      #
      # @param defaults [Hash] Default values
      #
      def defaults(**defaults)
        defaults.each do |name, value|
          @config[:parameters][:properties][name][:default] = value if @config[:parameters][:properties][name]
        end
      end

      ##
      # Define execution block
      #
      # @param block [Proc] Execution block
      #
      def execute(&block)
        @execution_block = block
      end

      ##
      # Define validation rule
      #
      # @param name [String] Rule name
      # @param block [Proc] Validation block
      #
      def validate(name, &block)
        @validation_rules << {
          name: name,
          block: block
        }
      end

      ##
      # Define before hook
      #
      # @param block [Proc] Before hook block
      #
      def before(&block)
        @config[:before_hook] = block
      end

      ##
      # Define after hook
      #
      # @param block [Proc] After hook block
      #
      def after(&block)
        @config[:after_hook] = block
      end

      ##
      # Define error handler
      #
      # @param block [Proc] Error handler block
      #
      def on_error(&block)
        @config[:error_handler] = block
      end

      ##
      # Add middleware
      #
      # @param middleware [Object] Middleware instance
      #
      def use_middleware(middleware)
        @middleware << middleware
      end

      ##
      # Set tool timeout
      #
      # @param timeout [Integer] Timeout in seconds
      #
      def timeout(timeout)
        @config[:timeout] = timeout
      end

      ##
      # Set tool retry policy
      #
      # @param policy [Hash] Retry policy
      #
      def retry_policy(**policy)
        @config[:retry_policy] = policy
      end

      ##
      # Set tool caching
      #
      # @param options [Hash] Caching options
      #
      def caching(**options)
        @config[:caching] = options
      end

      ##
      # Set tool rate limiting
      #
      # @param options [Hash] Rate limiting options
      #
      def rate_limit(**options)
        @config[:rate_limit] = options
      end

      ##
      # Set tool permissions
      #
      # @param permissions [Array<String>] Required permissions
      #
      def requires_permissions(*permissions)
        @config[:permissions] = permissions.flatten
      end

      ##
      # Set tool authentication
      #
      # @param auth [Hash] Authentication options
      #
      def requires_auth(**auth)
        @config[:authentication] = auth
      end

      ##
      # Set tool metadata
      #
      # @param metadata [Hash] Tool metadata
      #
      def metadata(**metadata)
        @config[:metadata] = (@config[:metadata] || {}).merge(metadata)
      end

      ##
      # Set tool tags
      #
      # @param tags [Array<String>] Tool tags
      #
      def tags(*tags)
        @config[:tags] = tags.flatten
      end

      ##
      # Set tool category
      #
      # @param category [String] Tool category
      #
      def category(category)
        @config[:category] = category
      end

      ##
      # Set tool version
      #
      # @param version [String] Tool version
      #
      def version(version)
        @config[:version] = version
      end

      ##
      # Set tool as deprecated
      #
      # @param message [String] Deprecation message
      #
      def deprecated(message = nil)
        @config[:deprecated] = true
        @config[:deprecation_message] = message if message
      end

      ##
      # Set tool as experimental
      #
      def experimental
        @config[:experimental] = true
      end

      ##
      # Set tool as internal
      #
      def internal
        @config[:internal] = true
      end

      ##
      # Define tool examples
      #
      # @param examples [Array<Hash>] Tool examples
      #
      def examples(*examples)
        @config[:examples] = examples.flatten
      end

      ##
      # Add single example
      #
      # @param description [String] Example description
      # @param input [Hash] Example input
      # @param output [Object] Example output
      #
      def example(description, input:, output:)
        @config[:examples] ||= []
        @config[:examples] << {
          description: description,
          input: input,
          output: output
        }
      end

      ##
      # Build a tool using DSL
      #
      # @param name [Symbol, String] Tool name (optional)
      # @param block [Proc] Configuration block
      # @return [Tool] Configured tool
      #
      def self.build(name = nil, &block)
        builder = new(name || "tool_#{SecureRandom.hex(4)}")
        builder.instance_eval(&block) if block_given?
        builder.build
      end

      ##
      # Set tool name
      #
      # @param name [String] Tool name
      #
      def name(name)
        @tool_name = name
      end

      ##
      # Build the tool
      #
      # @return [Tool] Configured tool
      #
      def build
        validate_configuration!

        tool = RAAF::FunctionTool.new(
          name: @tool_name,
          description: @config[:description],
          parameters: @config[:parameters],
          &@execution_block
        )

        # Apply configuration
        apply_configuration(tool)

        # Add validation rules
        add_validation_rules(tool)

        # Add middleware
        add_middleware(tool)

        log_info("Tool built successfully", tool_name: @tool_name)
        tool
      end

      ##
      # Build configuration hash
      #
      # @return [Hash] Configuration hash
      #
      def build_config
        @config.merge(
          execution_block: @execution_block,
          validation_rules: @validation_rules,
          middleware: @middleware
        )
      end

      ##
      # Get builder statistics
      #
      # @return [Hash] Builder statistics
      def statistics
        {
          name: @tool_name,
          parameters_count: @config[:parameters][:properties].size,
          required_parameters: @config[:parameters][:required].size,
          validation_rules: @validation_rules.size,
          middleware_count: @middleware.size,
          has_execution_block: !@execution_block.nil?
        }
      end

      ##
      # Get total count of tools built
      #
      # @return [Integer] Total count
      def self.count
        @@count
      end

      ##
      # Reset count
      #
      def self.reset_count!
        @@count = 0
      end

      private

      def validate_configuration!
        errors = []

        errors << "Tool name is required" unless @tool_name
        errors << "Tool description is required" unless @config[:description]
        errors << "Tool execution block is required" unless @execution_block

        # Validate parameters
        @config[:parameters][:properties].each do |name, param|
          errors << "Parameter '#{name}' must have a type" unless param[:type]
        end

        # Validate required parameters exist
        @config[:parameters][:required].each do |name|
          errors << "Required parameter '#{name}' not defined" unless @config[:parameters][:properties].key?(name)
        end

        # Validate timeout
        errors << "Timeout must be positive" if @config[:timeout]&.negative?

        raise DSL::ValidationError, errors.join(", ") if errors.any?
      end

      def apply_configuration(tool)
        # Apply configuration options to tool
        @config.each do |key, value|
          case key
          when :timeout
            tool.timeout = value
          when :retry_policy
            tool.retry_policy = value
          when :caching
            tool.caching = value
          when :rate_limit
            tool.rate_limit = value
          when :permissions
            tool.required_permissions = value
          when :authentication
            tool.authentication = value
          when :metadata
            tool.metadata = value
          when :tags
            tool.tags = value
          when :category
            tool.category = value
          when :version
            tool.version = value
          when :deprecated
            tool.deprecated = value
          when :experimental
            tool.experimental = value
          when :internal
            tool.internal = value
          when :examples
            tool.examples = value
          when :before_hook
            tool.before_execution(&value)
          when :after_hook
            tool.after_execution(&value)
          when :error_handler
            tool.on_error(&value)
          end
        end
      end

      def add_validation_rules(tool)
        @validation_rules.each do |rule|
          tool.add_validation_rule(rule[:name], &rule[:block])
        end
      end

      def add_middleware(tool)
        @middleware.each do |middleware|
          tool.use_middleware(middleware)
        end
      end
    end
  end
end
