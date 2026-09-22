# frozen_string_literal: true

module RAAF
  module DSL
    ##
    # Base class for prompt resolvers. Each resolver handles a specific
    # prompt format (e.g., Phlex classes, Markdown files, ERB templates).
    #
    # @abstract Subclass and implement {#resolve} to create a custom resolver
    #
    class PromptResolver
      # @return [Symbol] unique identifier for this resolver
      attr_reader :name

      # @return [Hash] resolver-specific options
      attr_reader :options

      ##
      # Initialize a new resolver
      #
      # @param name [Symbol] unique identifier for this resolver
      # @param options [Hash] resolver-specific options
      #
      def initialize(name:, **options)
        @name = name
        @options = options
      end

      ##
      # Determine if this resolver can handle the given prompt specification
      #
      # @param prompt_spec [Object] the prompt specification to check
      # @return [Boolean] true if this resolver can handle the specification
      #
      def can_resolve?(prompt_spec)
        raise NotImplementedError, "#{self.class} must implement #can_resolve?"
      end

      ##
      # Resolve a prompt specification into a Prompt object
      #
      # @param prompt_spec [Object] the prompt specification to resolve
      # @param context [Hash] runtime context for prompt generation
      # @return [Prompt, nil] resolved prompt or nil if cannot resolve
      #
      def resolve(prompt_spec, context = {})
        raise NotImplementedError, "#{self.class} must implement #resolve"
      end

      ##
      # Priority of this resolver (higher = checked first)
      #
      # @return [Integer] priority value
      #
      def priority
        options[:priority] || 0
      end
    end

    ##
    # Registry for managing prompt resolvers
    #
    class PromptResolverRegistry
      def initialize
        @resolvers = []
        @mutex = Mutex.new
      end

      ##
      # Register a new resolver
      #
      # @param resolver [PromptResolver] the resolver to register
      # @return [self]
      #
      def register(resolver)
        @mutex.synchronize do
          @resolvers << resolver
          @resolvers.sort_by! { |r| -r.priority } # Sort by priority descending
        end
        self
      end

      ##
      # Unregister a resolver by name
      #
      # @param name [Symbol] the resolver name to unregister
      # @return [PromptResolver, nil] the removed resolver or nil
      #
      def unregister(name)
        @mutex.synchronize do
          resolver = @resolvers.find { |r| r.name == name }
          @resolvers.delete(resolver) if resolver
          resolver
        end
      end

      ##
      # Clear all registered resolvers
      #
      # @return [self]
      #
      def clear
        @mutex.synchronize do
          @resolvers.clear
        end
        self
      end

      ##
      # Get all registered resolvers
      #
      # @return [Array<PromptResolver>] list of resolvers sorted by priority
      #
      def resolvers
        @mutex.synchronize { @resolvers.dup }
      end

      ##
      # Find a resolver by name
      #
      # @param name [Symbol] resolver name
      # @return [PromptResolver, nil]
      #
      def find(name)
        @mutex.synchronize do
          @resolvers.find { |r| r.name == name }
        end
      end

      ##
      # Resolve a prompt using the registered resolvers
      #
      # @param prompt_spec [Object] the prompt specification
      # @param context [Hash] runtime context
      # @return [Prompt, nil] resolved prompt or nil
      #
      def resolve(prompt_spec, context = {})
        @mutex.synchronize do
          @resolvers.each do |resolver|
            next unless resolver.can_resolve?(prompt_spec)

            result = resolver.resolve(prompt_spec, context)
            return result if result
          end
        end

        nil
      end
    end
  end
end
