# frozen_string_literal: true

module RAAF
  # New Pipeline base class for elegant DSL
  # Supports agent chaining with >> and | operators
  #
  # DSL Design Philosophy:
  # - Declarative over imperative: Define flow structure, not execution steps
  # - Context-aware: Automatic field validation and propagation
  # - Ruby-idiomatic: Uses familiar patterns (context, defaults, readers)
  #
  # Usage Pattern:
  #   class MyPipeline < RAAF::Pipeline
  #     flow Agent1 >> Agent2 >> (Agent3 | Agent4) >> Agent5
  #     context_reader :required_field
  #     context { default :optional_field, "default_value" }
  #   end
  class Pipeline
    class << self
      attr_reader :flow_chain, :context_config, :context_readers
      
      # Define the agent execution flow using DSL operators
      # Stores the chained/parallel agent structure for execution
      def flow(chain)
        @flow_chain = chain
      end
      
      # Context DSL - just like agents
      # Provides default values and computed context setup
      def context(&block)
        if block_given?
          @context_config ||= {}
          @context_config[:defaults] ||= {}
          
          # Simple DSL for context defaults
          config_proxy = Object.new
          parent = self
          config_proxy.define_singleton_method(:default) do |key, value|
            parent.context_config[:defaults][key] = value
          end
          
          config_proxy.instance_eval(&block)
        end
        @context_config ||= {}
      end
      
      # Context readers - just like agents  
      # Declares required fields that must be provided when creating pipeline instance
      def context_reader(*fields)
        @context_readers ||= []
        @context_readers.concat(fields)
      end
      
      def required_fields
        @context_readers || []
      end
    end
    
    # Initialize a pipeline with flexible context options
    #
    # Supports the same flexible API as RAAF agents for consistency:
    # 1. With context hash: Pipeline.new(context: { key: value })
    # 2. With keyword args: Pipeline.new(key: value, key2: value2)
    # 3. Mixed: Pipeline.new(context: base_context, extra_key: value)
    #
    # @param context [Hash, nil] Optional context hash (like agents)
    # @param provided_context [Hash] Additional context as keyword arguments
    def initialize(context: nil, **provided_context)
      # Support both context: hash and direct keyword arguments like agents do
      if context
        # Context provided explicitly (like agents)
        @context = build_context_from_param(context).merge(provided_context)
      else
        # Use keyword arguments as context
        @context = build_initial_context(provided_context)
      end
      
      @flow = self.class.flow_chain
      @context[:pipeline_instance] = self if @context.is_a?(Hash)
      validate_initial_context!
    end
    
    def run
      execute_chain(@flow, @context)
    end
    
    private
    
    def build_context_from_param(context_param)
      case context_param
      when Hash
        context_param
      else
        raise ArgumentError, "Pipeline context must be a Hash, got #{context_param.class}"
      end
    end
    
    def build_initial_context(provided_context)
      # Start with provided context
      context = provided_context.dup
      
      # Apply defaults from context block (just like agents)
      config = self.class.context_config
      if config && config[:defaults]
        config[:defaults].each do |key, value|
          context[key] ||= value.is_a?(Proc) ? value.call : value
        end
      end
      
      # Add any computed context fields (if we have build_*_context methods)
      self.class.required_fields.each do |field|
        method_name = "build_#{field}_context"
        if respond_to?(method_name, true)
          context[field] ||= send(method_name)
        end
      end
      
      context
    end
    
    def validate_initial_context!
      return unless @flow
      
      # Extract first agent from chain
      first_agent = extract_first_agent(@flow)
      return unless first_agent && first_agent.respond_to?(:required_fields)
      
      required = first_agent.required_fields
      provided = @context.keys
      missing = required - provided
      
      if missing.any?
        raise ArgumentError, <<~MSG
          Pipeline initialization error!
          
          First agent #{first_agent.name} requires: #{required.inspect}
          You have in context: #{provided.inspect}
          Missing: #{missing.inspect}
          
          Either:
          1. Add missing fields when creating the pipeline:
             pipeline = #{self.class.name}.new(
               #{missing.map { |f| "#{f}: #{f}_value" }.join(",\n               ")}
             )
          
          2. Or define defaults in the pipeline class:
             class #{self.class.name}
               context do
                 default :#{missing.first}, "default_value"
               end
             end
        MSG
      end
    end
    
    def extract_first_agent(chain)
      case chain
      when DSL::PipelineDSL::ChainedAgent
        extract_first_agent(chain.first)
      when DSL::PipelineDSL::ParallelAgents
        agents = chain.agents
        agents.first if agents
      when DSL::PipelineDSL::ConfiguredAgent
        chain.agent_class
      when Class
        chain
      else
        nil
      end
    end
    
    def execute_chain(chain, context)
      case chain
      when DSL::PipelineDSL::ChainedAgent, DSL::PipelineDSL::ParallelAgents, DSL::PipelineDSL::ConfiguredAgent
        chain.execute(context)
      when Class
        execute_agent(chain, context)
      when Symbol
        send(chain, context) if respond_to?(chain, true)
        context
      else
        raise "Unknown chain type: #{chain.class}"
      end
    end
    
    def execute_agent(agent_class, context)
      unless agent_class.respond_to?(:requirements_met?) && agent_class.requirements_met?(context)
        RAAF.logger.warn "Skipping #{agent_class.name}: requirements not met"
        return context
      end
      
      agent = agent_class.new(context: context)
      result = agent.run
      
      # Merge provisions into context
      if agent_class.respond_to?(:provided_fields)
        agent_class.provided_fields.each do |field|
          context[field] = result[field] if result.respond_to?(:[]) && result[field]
        end
      end
      
      context
    end
  end
end