# frozen_string_literal: true

module RAAF
  module Testing
    module RSpec
      ##
      # RSpec matchers for testing RAAF context variables and context handling
      #
      # This module provides matchers specifically designed for testing
      # the immutable ContextVariables system and context-related functionality.
      #
      module ContextMatchers
        ##
        # Match context variables that contain specific keys
        #
        # @param expected_keys [Array<Symbol>] Expected context keys
        #
        # @example
        #   expect(context).to have_context_keys(:user_id, :session_id)
        #
        ::RSpec::Matchers.define :have_context_keys do |*expected_keys|
          match do |context|
            return false unless context.respond_to?(:get) || context.respond_to?(:key?)
            
            expected_keys.all? do |key|
              if context.respond_to?(:get)
                !context.get(key).nil?
              elsif context.respond_to?(:key?)
                context.key?(key)
              else
                context.has_key?(key)
              end
            end
          end
          
          failure_message do |context|
            available_keys = extract_context_keys(context)
            "Expected context to have keys #{expected_keys.inspect}, " \
            "but available keys are #{available_keys.inspect}"
          end
          
          def extract_context_keys(context)
            if context.respond_to?(:to_h)
              context.to_h.keys
            elsif context.respond_to?(:keys)
              context.keys
            elsif context.is_a?(Hash)
              context.keys
            else
              []
            end
          end
        end

        ##
        # Match context variables with specific values
        #
        # @param expected_values [Hash] Expected key-value pairs
        #
        # @example
        #   expect(context).to have_context_values(user_id: 123, environment: "test")
        #
        ::RSpec::Matchers.define :have_context_values do |expected_values|
          match do |context|
            expected_values.all? do |key, expected_value|
              actual_value = if context.respond_to?(:get)
                           context.get(key)
                         elsif context.respond_to?(:[])
                           context[key]
                         else
                           nil
                         end
              actual_value == expected_value
            end
          end
          
          failure_message do |context|
            actual_values = {}
            expected_values.each do |key, _|
              actual_values[key] = if context.respond_to?(:get)
                                 context.get(key)
                               elsif context.respond_to?(:[])
                                 context[key]
                               else
                                 nil
                               end
            end
            
            "Expected context values #{expected_values.inspect}, " \
            "but got #{actual_values.inspect}"
          end
        end

        ##
        # Match context variables that follow immutable pattern
        # (i.e., operations return new instances without modifying the original)
        #
        # @example
        #   expect(context).to be_immutable
        #
        ::RSpec::Matchers.define :be_immutable do
          match do |context|
            return false unless context.respond_to?(:set)
            
            # Store original state
            original_size = context.respond_to?(:size) ? context.size : 0
            original_hash = context.respond_to?(:to_h) ? context.to_h.dup : {}
            
            # Perform an operation that should return a new instance
            new_context = context.set(:test_key, "test_value")
            
            # Verify original is unchanged
            current_size = context.respond_to?(:size) ? context.size : 0
            current_hash = context.respond_to?(:to_h) ? context.to_h : {}
            
            # Check that original context is unchanged
            original_unchanged = (current_size == original_size) && 
                               (current_hash == original_hash)
            
            # Check that new context is different
            new_context_different = new_context != context
            
            original_unchanged && new_context_different
          end
          
          failure_message do |context|
            "Expected context to be immutable (operations return new instances), " \
            "but context appears to be mutable"
          end
        end

        ##
        # Match context that grows in size when new values are added
        #
        # @param expected_size_change [Integer] Expected size increase
        #
        # @example
        #   expect { context.set(:new_key, "value") }.to increase_context_size_by(1)
        #
        ::RSpec::Matchers.define :increase_context_size_by do |expected_size_change|
          supports_block_expectations
          
          match do |block|
            @initial_size = get_context_size(@initial_context)
            @result_context = block.call
            @final_size = get_context_size(@result_context)
            @actual_size_change = @final_size - @initial_size
            
            @actual_size_change == expected_size_change
          end
          
          chain :from do |context|
            @initial_context = context
          end
          
          failure_message do
            "Expected context size to increase by #{expected_size_change}, " \
            "but increased by #{@actual_size_change} " \
            "(from #{@initial_size} to #{@final_size})"
          end
          
          def get_context_size(context)
            if context.respond_to?(:size)
              context.size
            elsif context.respond_to?(:length)
              context.length
            elsif context.respond_to?(:count)
              context.count
            elsif context.respond_to?(:to_h)
              context.to_h.size
            else
              0
            end
          end
        end

        ##
        # Match context operations that preserve type safety
        #
        # @example
        #   expect(context.set(:key, "value")).to preserve_type_safety
        #
        ::RSpec::Matchers.define :preserve_type_safety do
          match do |context|
            # Test that context maintains its type after operations
            original_class = context.class
            
            # Perform various operations
            modified_context = context
            if context.respond_to?(:set)
              modified_context = modified_context.set(:test_key_1, "string")
              modified_context = modified_context.set(:test_key_2, 123)
              modified_context = modified_context.set(:test_key_3, { nested: "hash" })
            end
            
            # Check that the result maintains the same type
            modified_context.class == original_class
          end
          
          failure_message do |context|
            "Expected context operations to preserve type safety, " \
            "but context type changed during operations"
          end
        end

        ##
        # Match context that can be serialized and deserialized safely
        #
        # @example
        #   expect(context).to be_serializable
        #
        ::RSpec::Matchers.define :be_serializable do
          match do |context|
            begin
              # Test JSON serialization
              if context.respond_to?(:to_h)
                hash_data = context.to_h
                json_data = hash_data.to_json
                parsed_data = JSON.parse(json_data)
                
                # Compare keys (values might have different types after JSON roundtrip)
                original_keys = hash_data.keys.map(&:to_s).sort
                parsed_keys = parsed_data.keys.sort
                
                original_keys == parsed_keys
              else
                false
              end
            rescue JSON::GeneratorError, JSON::ParserError => e
              @serialization_error = e
              false
            end
          end
          
          failure_message do |context|
            if @serialization_error
              "Expected context to be serializable, but got error: #{@serialization_error.message}"
            else
              "Expected context to be serializable, but serialization test failed"
            end
          end
        end

        ##
        # Match context that contains nested data structures safely
        #
        # @example
        #   expect(context).to handle_nested_data_safely
        #
        ::RSpec::Matchers.define :handle_nested_data_safely do
          match do |context|
            return false unless context.respond_to?(:set) && context.respond_to?(:get)
            
            # Test with various nested data types
            test_data = {
              array: [1, 2, 3],
              hash: { nested: { deeply: "nested" } },
              mixed: [{ key: "value" }, ["nested", "array"]],
              nil_value: nil,
              boolean: true
            }
            
            # Set nested data
            new_context = context
            test_data.each do |key, value|
              new_context = new_context.set(key, value)
            end
            
            # Verify nested data can be retrieved correctly
            test_data.all? do |key, expected_value|
              actual_value = new_context.get(key)
              actual_value == expected_value
            end
          rescue => e
            @nested_data_error = e
            false
          end
          
          failure_message do |context|
            if @nested_data_error
              "Expected context to handle nested data safely, " \
              "but got error: #{@nested_data_error.message}"
            else
              "Expected context to handle nested data safely, " \
              "but nested data handling failed"
            end
          end
        end

        ##
        # Match context with specific size
        #
        # @param expected_size [Integer] Expected context size
        #
        # @example
        #   expect(context).to have_size(5)
        #
        ::RSpec::Matchers.define :have_context_size do |expected_size|
          match do |context|
            actual_size = if context.respond_to?(:size)
                        context.size
                      elsif context.respond_to?(:length)
                        context.length
                      elsif context.respond_to?(:count)
                        context.count
                      elsif context.respond_to?(:to_h)
                        context.to_h.size
                      else
                        0
                      end
            actual_size == expected_size
          end
          
          failure_message do |context|
            actual_size = context.respond_to?(:size) ? context.size : "unknown"
            "Expected context to have size #{expected_size}, but got #{actual_size}"
          end
        end
      end
    end
  end
end