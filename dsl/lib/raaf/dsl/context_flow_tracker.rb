# frozen_string_literal: true

module RAAF
  module DSL
    # Tracks context as it flows through a pipeline for validation
    class ContextFlowTracker
      attr_reader :current_context, :stage_number, :stage_history
      
      def initialize(initial_context)
        @initial_context = initial_context.dup
        @current_context = initial_context.dup
        @stage_number = 0
        @stage_history = []
      end
      
      def enter_stage(stage_name)
        @stage_number += 1
        @current_stage = stage_name
        @stage_history << {
          number: @stage_number,
          name: stage_name,
          context_before: @current_context.keys.dup,
          context_after: nil
        }
      end
      
      def add_output_fields(fields)
        return if fields.nil? || fields.empty?
        
        # Add fields that this stage will output
        fields = [fields].flatten  # Handle both single field and array
        fields.each do |field|
          @current_context[field.to_sym] = :simulated
        end
        
        # Update stage history
        if @stage_history.last
          @stage_history.last[:context_after] = @current_context.keys.dup
          @stage_history.last[:added_fields] = fields
        end
      end
      
      def available_keys
        @current_context.keys
      end
      
      def create_branch_tracker
        # For parallel execution, create a new tracker with current context
        self.class.new(@current_context)
      end
      
      def merge_branch_results(branch_tracker)
        # Merge fields added by parallel branch back into main context
        branch_tracker.current_context.each do |key, value|
          @current_context[key] = value unless @current_context.key?(key)
        end
      end
      
      def summary
        {
          initial_context: @initial_context.keys,
          final_context: @current_context.keys,
          stages_processed: @stage_number,
          fields_added: @current_context.keys - @initial_context.keys,
          stage_history: @stage_history
        }
      end
    end
  end
end