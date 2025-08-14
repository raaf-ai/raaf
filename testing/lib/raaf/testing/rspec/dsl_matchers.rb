# frozen_string_literal: true

module RAAF
  module Testing
    module RSpec
      ##
      # DSL-specific RSpec matchers for testing RAAF DSL components
      #
      # This module provides custom matchers specifically designed for testing
      # AI agents built with the RAAF DSL, including context validation,
      # agent configuration testing, and workflow verification.
      #
      # @example Using DSL matchers
      #   RSpec.describe MyAgent do
      #     it "has valid configuration" do
      #       expect(MyAgent).to have_valid_agent_config
      #       expect(MyAgent).to require_context_keys(:product, :company)
      #     end
      #   end
      #
      module DSLMatchers
        ##
        # Match agents that have valid configuration
        #
        # @example
        #   expect(MyAgent).to have_valid_agent_config
        #
        ::RSpec::Matchers.define :have_valid_agent_config do
          match do |agent_class|
            @validation_errors = []
            
            # Check if agent has name
            unless agent_class.respond_to?(:agent_name) && agent_class.agent_name
              @validation_errors << "Agent must have a name defined with agent_name"
            end
            
            # Check if agent has model configured
            unless agent_class.respond_to?(:model) || agent_class.respond_to?(:_model)
              @validation_errors << "Agent must have a model configured"
            end
            
            # Check for prompt or instructions
            has_prompt = agent_class.respond_to?(:prompt_class) && agent_class.prompt_class
            has_instructions = agent_class.respond_to?(:instructions) && agent_class.instructions
            
            unless has_prompt || has_instructions
              @validation_errors << "Agent must have either prompt_class or instructions defined"
            end
            
            @validation_errors.empty?
          end
          
          failure_message do |agent_class|
            "Expected #{agent_class} to have valid configuration, but found errors:\n" +
              @validation_errors.map { |error| "  - #{error}" }.join("\n")
          end
        end

        ##
        # Match agents that require specific context keys
        #
        # @param keys [Array<Symbol>] Expected required context keys
        #
        # @example
        #   expect(MyAgent).to require_context_keys(:product, :company)
        #
        ::RSpec::Matchers.define :require_context_keys do |*expected_keys|
          match do |agent_class|
            return false unless agent_class.respond_to?(:_required_context_keys)
            
            required_keys = agent_class._required_context_keys || []
            expected_keys.all? { |key| required_keys.include?(key) }
          end
          
          failure_message do |agent_class|
            required_keys = agent_class.respond_to?(:_required_context_keys) ? 
              agent_class._required_context_keys || [] : []
              
            "Expected #{agent_class} to require context keys #{expected_keys.inspect}, " \
            "but requires #{required_keys.inspect}"
          end
        end

        ##
        # Match agents that have specific tools configured
        #
        # @param tool_names [Array<Symbol>] Expected tool names
        #
        # @example
        #   expect(MyAgent).to have_tools(:web_search, :calculator)
        #
        ::RSpec::Matchers.define :have_tools do |*expected_tools|
          match do |agent_class|
            return false unless agent_class.respond_to?(:_tools)
            
            configured_tools = agent_class._tools&.keys || []
            expected_tools.all? { |tool| configured_tools.include?(tool) }
          end
          
          failure_message do |agent_class|
            configured_tools = agent_class.respond_to?(:_tools) ? 
              agent_class._tools&.keys || [] : []
              
            "Expected #{agent_class} to have tools #{expected_tools.inspect}, " \
            "but has #{configured_tools.inspect}"
          end
        end

        ##
        # Match agent instances that have specific context values
        #
        # @param expected_values [Hash] Expected context key-value pairs
        #
        # @example
        #   expect(agent_instance).to have_context_values(user_id: 123, environment: "test")
        #
        ::RSpec::Matchers.define :have_context_values do |expected_values|
          match do |agent_instance|
            return false unless agent_instance.respond_to?(:context)
            
            context = agent_instance.context
            return false unless context.respond_to?(:get)
            
            expected_values.all? do |key, expected_value|
              actual_value = context.get(key)
              actual_value == expected_value
            end
          end
          
          failure_message do |agent_instance|
            context = agent_instance.context
            actual_values = {}
            
            expected_values.each do |key, _|
              actual_values[key] = context.respond_to?(:get) ? context.get(key) : nil
            end
            
            "Expected agent to have context values #{expected_values.inspect}, " \
            "but has #{actual_values.inspect}"
          end
        end

        ##
        # Match agent executions that use specific tools
        #
        # @param tool_name [Symbol] Expected tool name
        # @param args [Hash] Optional expected tool arguments
        #
        # @example
        #   expect(result).to have_used_tool(:web_search)
        #   expect(result).to have_used_tool(:web_search, query: "Ruby programming")
        #
        ::RSpec::Matchers.define :have_used_tool do |tool_name, args = nil|
          match do |result|
            return false unless result.respond_to?(:tool_calls) || result.respond_to?(:messages)
            
            # Check for tool calls in result
            if result.respond_to?(:tool_calls) && result.tool_calls
              used_tools = result.tool_calls.map { |call| call[:name]&.to_sym }
              tool_used = used_tools.include?(tool_name)
              
              if args && tool_used
                matching_call = result.tool_calls.find { |call| call[:name]&.to_sym == tool_name }
                return matching_call && args.all? { |k, v| matching_call[:arguments]&.[](k) == v }
              end
              
              return tool_used
            end
            
            # Check messages for tool calls
            if result.respond_to?(:messages) && result.messages
              result.messages.any? do |message|
                message[:tool_calls]&.any? do |tool_call|
                  tool_call.dig(:function, :name)&.to_sym == tool_name
                end
              end
            else
              false
            end
          end
          
          failure_message do |result|
            if args
              "Expected result to have used tool #{tool_name} with arguments #{args.inspect}"
            else
              "Expected result to have used tool #{tool_name}"
            end
          end
        end

        ##
        # Match successful agent executions
        #
        # @example
        #   expect(result).to have_successful_execution
        #
        ::RSpec::Matchers.define :have_successful_execution do
          match do |result|
            # Handle different result types
            if result.respond_to?(:success?)
              result.success?
            elsif result.respond_to?(:success)
              result.success == true || result.success == "true"
            elsif result.is_a?(Hash)
              result[:success] == true || result[:success] == "true"
            else
              false
            end
          end
          
          failure_message do |result|
            if result.respond_to?(:errors)
              "Expected successful execution, but got errors: #{result.errors}"
            else
              "Expected successful execution, but result indicates failure: #{result.inspect}"
            end
          end
        end

        ##
        # Match context variables that follow immutable pattern
        #
        # @example
        #   expect { context.set(:key, "value") }.to preserve_original_context(context)
        #
        ::RSpec::Matchers.define :preserve_original_context do |original_context|
          supports_block_expectations
          
          match do |block|
            original_size = original_context.size
            original_keys = original_context.to_h.keys
            
            # Execute the block (which should create a new context)
            block.call
            
            # Verify original context is unchanged
            original_context.size == original_size &&
              original_context.to_h.keys == original_keys
          end
          
          failure_message do
            "Expected block to preserve original context (immutable pattern), " \
            "but original context was modified"
          end
        end

        ##
        # Match agent results that contain specific output structure
        #
        # @param expected_structure [Hash] Expected structure with keys and types
        #
        # @example
        #   expect(result).to have_output_structure(
        #     success: :boolean,
        #     data: :hash,
        #     markets: :array
        #   )
        #
        ::RSpec::Matchers.define :have_output_structure do |expected_structure|
          match do |result|
            @missing_keys = []
            @type_mismatches = []
            
            expected_structure.each do |key, expected_type|
              unless result.respond_to?(:key?) ? result.key?(key) : result.has_key?(key)
                @missing_keys << key
                next
              end
              
              actual_value = result[key]
              
              case expected_type
              when :boolean
                unless [true, false].include?(actual_value)
                  @type_mismatches << "#{key}: expected boolean, got #{actual_value.class}"
                end
              when :array
                unless actual_value.is_a?(Array)
                  @type_mismatches << "#{key}: expected Array, got #{actual_value.class}"
                end
              when :hash
                unless actual_value.is_a?(Hash)
                  @type_mismatches << "#{key}: expected Hash, got #{actual_value.class}"
                end
              when :string
                unless actual_value.is_a?(String)
                  @type_mismatches << "#{key}: expected String, got #{actual_value.class}"
                end
              when :integer
                unless actual_value.is_a?(Integer)
                  @type_mismatches << "#{key}: expected Integer, got #{actual_value.class}"
                end
              when Class
                unless actual_value.is_a?(expected_type)
                  @type_mismatches << "#{key}: expected #{expected_type}, got #{actual_value.class}"
                end
              end
            end
            
            @missing_keys.empty? && @type_mismatches.empty?
          end
          
          failure_message do |result|
            errors = []
            errors.concat(@missing_keys.map { |key| "Missing key: #{key}" }) if @missing_keys.any?
            errors.concat(@type_mismatches) if @type_mismatches.any?
            
            "Expected result to have structure #{expected_structure.inspect}, but found errors:\n" +
              errors.map { |error| "  - #{error}" }.join("\n")
          end
        end
      end
    end
  end
end