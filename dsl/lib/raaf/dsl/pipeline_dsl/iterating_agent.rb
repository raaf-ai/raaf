# frozen_string_literal: true

require 'thread'
require 'timeout'
require_relative '../core/context_variables'
require_relative 'wrapper_dsl'

module RAAF
  module DSL
    module PipelineDSL
      # Represents an agent that iterates over multiple data entries
      # Created using .each_over() method: AgentClass.each_over(:field_name)
      #
      # DSL Usage Patterns:
      #   Agent.each_over(:items)                    # Sequential processing (default)
      #   Agent.each_over(:items, parallel: true)   # Parallel processing
      #   Agent.each_over(:items).parallel           # Fluent parallel syntax
      #   Agent.each_over(:items).timeout(30)       # With configuration
      #
      # Execution Models:
      # - Sequential: Process items one at a time, maintain order, memory efficient
      # - Parallel: Process items concurrently using threads, faster for I/O-bound operations
      #
      # Field Flow: input_field (array) -> processed_field_name (array of results)
      class IteratingAgent
        include WrapperDSL

        attr_reader :agent_class, :field, :options

        def initialize(agent_class, field, options = {})
          @agent_class = agent_class
          @field = field.to_sym
          @options = options.dup
          @parallel = @options.delete(:parallel) || false
          @custom_output_field = @options.delete(:to)&.to_sym
          @custom_field_name = @options.delete(:as)&.to_sym

          RAAF.logger.debug "IteratingAgent initialized: class=#{agent_class}, field=#{field}, as=#{@custom_field_name}, to=#{@custom_output_field}, options=#{options.inspect}"
        end

        # Create a new wrapper with merged options (required by WrapperDSL)
        def create_wrapper(**new_options)
          # Restore special options that were extracted in initialize
          merged_options = @options.merge(new_options)
          merged_options[:parallel] = @parallel if @parallel
          merged_options[:to] = @custom_output_field if @custom_output_field
          merged_options[:as] = @custom_field_name if @custom_field_name

          IteratingAgent.new(@agent_class, @field, merged_options)
        end

        # DSL method: Enable parallel execution
        def parallel
          @parallel = true
          self
        end

        # Delegate metadata methods to the wrapped agent class
        def required_fields
          base_fields = @agent_class.respond_to?(:required_fields) ? @agent_class.required_fields : []
          # Add the iteration field as a requirement
          (base_fields + [@field]).uniq
        end

        def provided_fields
          # Generate output field name from input field name
          # :companies -> :processed_companies, :items -> :processed_items
          base_fields = @agent_class.respond_to?(:provided_fields) ? @agent_class.provided_fields : []
          output_field = generate_output_field_name(@field)
          (base_fields + [output_field]).uniq
        end

        def requirements_met?(context)
          # Check if the iteration field exists and is an array
          return false unless context.respond_to?(:[]) && context.respond_to?(:key?)
          return false unless context.key?(@field)
          
          items = context[@field]
          return false unless items.respond_to?(:each) # Must be enumerable
          
          # Check if wrapped agent's requirements can be met
          @agent_class.respond_to?(:requirements_met?) ? 
            @agent_class.requirements_met?(context) : true
        end

        # Execute iteration over the specified field
        def execute(context)
          # Wrap execution with before_execute/after_execute hooks
          agent_name = @agent_class.respond_to?(:agent_name) ? @agent_class.agent_name : @agent_class.name

          execute_with_hooks(context, :iterating, agent_name: agent_name, field: @field, parallel: @parallel, output_field: generate_output_field_name(@field)) do
            # Ensure context is ContextVariables if it's a plain Hash
            unless context.respond_to?(:set)
              context = RAAF::DSL::ContextVariables.new(context)
            end

            items = extract_items(context)

            if items.empty?
              RAAF.logger.info "No items found in field '#{@field}' for iteration"
              return context
            end

            RAAF.logger.info "#{@parallel ? 'Parallel' : 'Sequential'} iteration over #{items.length} items in field '#{@field}'"

            results = if @parallel
                        execute_parallel(items, context)
                      else
                        execute_sequential(items, context)
                      end

            # Add results to context using generated output field name
            output_field = generate_output_field_name(@field)
            context[output_field] = results

            context
          end
        end

        private

        def extract_items(context)
          items = context[@field] || []
          
          # Handle different item types
          items = items.to_a if items.respond_to?(:to_a)
          
          # Apply limit if specified
          if @options[:limit]
            items = items.first(@options[:limit])
            RAAF.logger.info "Limited iteration to #{@options[:limit]} items"
          end

          items
        end

        def execute_sequential(items, context)
          results = []
          
          items.each_with_index do |item, index|
            RAAF.logger.debug "Processing item #{index + 1}/#{items.length} in field '#{@field}'"
            
            begin
              result = execute_single_item(item, context, index)
              results << result
            rescue => e
              error_msg = "Error processing item #{index + 1} in field '#{@field}': #{e.message}"
              RAAF.logger.error error_msg
              
              # For sequential execution, we can choose to continue or stop
              # For now, continue but mark the failure
              results << { 
                error: true, 
                message: e.message, 
                item_index: index,
                original_item: item
              }
            end
          end

          results
        end

        def execute_parallel(items, context)
          # Use thread pool pattern similar to existing ParallelAgents
          threads = items.map.with_index do |item, index|
            Thread.new do
              RAAF.logger.debug "Processing item #{index + 1}/#{items.length} in field '#{@field}' (parallel)"
              
              begin
                execute_single_item(item, context.dup, index)
              rescue => e
                error_msg = "Error processing item #{index + 1} in field '#{@field}': #{e.message}"
                RAAF.logger.error error_msg
                
                # Return error result for this item
                { 
                  error: true, 
                  message: e.message, 
                  item_index: index,
                  original_item: item
                }
              end
            end
          end

          # Collect results maintaining order
          results = []
          threads.each_with_index do |thread, index|
            begin
              results[index] = thread.value
            rescue => e
              RAAF.logger.error "Thread error for item #{index + 1}: #{e.message}"
              results[index] = { 
                error: true, 
                message: e.message, 
                item_index: index,
                thread_error: true
              }
            end
          end

          results
        end

        def execute_single_item(item, context, index)
          # Create context for this specific item
          item_context = prepare_item_context(item, context, index)
          
          # Apply timeout and retry configuration
          timeout_value = @options[:timeout] || 30
          retry_count = @options[:retry] || 1

          Timeout.timeout(timeout_value) do
            attempts = 0
            begin
              attempts += 1
              
              # Execute agent/service with item-specific context
              # Services and Agents have different context initialization patterns
              if @agent_class < RAAF::DSL::Service
                # For Services, pass context explicitly to ensure proper ContextAccess resolution
                RAAF.logger.debug "Instantiating Service #{@agent_class.name} with explicit context"
                RAAF.logger.debug "Custom field name: #{@custom_field_name.inspect}, Field: #{@field.inspect}"
                
                agent = @agent_class.new(context: item_context)
              else
                # For Agents, maintain backward compatibility with keyword arguments
                context_hash = item_context.is_a?(RAAF::DSL::ContextVariables) ? 
                               item_context.to_h : item_context
                
                RAAF.logger.debug "Instantiating Agent #{@agent_class.name} with context keys: #{context_hash.keys.inspect}"
                RAAF.logger.debug "Custom field name: #{@custom_field_name.inspect}, Field: #{@field.inspect}"
                
                agent = @agent_class.new(**context_hash)
              end
              
              # Check if it's a Service (uses call) or Agent (uses run)
              result = if agent.respond_to?(:call)
                         agent.call  # Service uses call
                       else
                         agent.run   # Agent uses run
                       end

              # Return the result (could be a hash, object, or primitive)
              result
            rescue => e
              if attempts < retry_count
                sleep_time = 2 ** (attempts - 1) # Exponential backoff
                RAAF.logger.warn "Retrying #{@agent_class.name} for item #{index + 1} after #{sleep_time}s (attempt #{attempts}/#{retry_count})"
                sleep(sleep_time)
                retry
              else
                raise e
              end
            end
          end
        rescue Timeout::Error => e
          RAAF.logger.error "#{@agent_class.name} timed out after #{timeout_value} seconds for item #{index + 1}"
          raise e
        end

        def prepare_item_context(item, base_context, index)
          # Create context that includes the current item and preserves base context
          # Ensure we always work with a proper ContextVariables object for Services
          if base_context.is_a?(RAAF::DSL::ContextVariables)
            context_hash = base_context.to_h.dup
          else
            context_hash = base_context.dup
          end
          
          # Add the current item to context - agents can access it via standard context methods
          # Use a generic name that works for any iteration
          context_hash[:current_item] = item
          context_hash[:item_index] = index
          
          # Add item under a specific name - use custom field name if provided, 
          # otherwise generate from the original field
          if @custom_field_name
            RAAF.logger.debug "Using custom field name '#{@custom_field_name}' for item at index #{index}"
            context_hash[@custom_field_name] = item
          else
            singular_name = singularize_field_name(@field)
            RAAF.logger.debug "Using default field name '#{singular_name}' for item at index #{index}"
            context_hash[singular_name] = item
          end

          RAAF.logger.debug "Item context keys: #{context_hash.keys.inspect}"
          
          # Return as ContextVariables object for proper Service handling
          RAAF::DSL::ContextVariables.new(context_hash)
        end

        def generate_output_field_name(input_field)
          # Return custom output field if specified, otherwise generate default
          return @custom_output_field if @custom_output_field
          
          # Generate meaningful output field names
          # :companies -> :processed_companies
          # :items -> :processed_items  
          # :markets -> :processed_markets
          "processed_#{input_field}".to_sym
        end

        def singularize_field_name(field)
          # Simple singularization for common patterns
          # :companies -> :company (default, no prefix)
          # :items -> :item
          # :markets -> :market
          # :search_terms -> :search_term
          field_str = field.to_s
          singular = if field_str.end_with?('ies')
                       field_str.gsub(/ies$/, 'y')
                     elsif field_str.end_with?('s')
                       field_str.gsub(/s$/, '')
                     else
                       field_str
                     end
          
          singular.to_sym
        end
      end
    end
  end
end