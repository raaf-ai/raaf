# frozen_string_literal: true

require_relative "../context_access"
require_relative "../context_spy"

module RAAF
  module DSL
    module Prompts
      # Base class for AI prompts with Phlex-inspired design and automatic context access
      #
      # This class provides a clean, convention-over-configuration way to build AI prompts 
      # using heredocs for natural text writing with Ruby interpolation support. Context 
      # variables are automatically accessible via method_missing without requiring 
      # explicit declarations.
      #
      # Key features:
      # - Phlex-inspired API for building prompts
      # - Automatic context variable access via method_missing
      # - Clean Ruby error messages when variables are missing
      # - Support for context_variables from agents
      # - Direct context access from initialization
      #
      # @abstract Subclasses must implement {#system} and {#user} methods
      #
      # @example Basic prompt with automatic context access
      #   class CompanyEnrichment < RAAF::DSL::Prompts::Base
      #     def system
      #       <<~SYSTEM
      #         You are an AI assistant specializing in company data enrichment.
      #
      #         Your role is to research #{company.name} and fill in these attributes:
      #         #{attributes.map { |a| "- #{a}" }.join("\n")}
      #       SYSTEM
      #     end
      #
      #     def user
      #       <<~USER
      #         Research and enrich data for #{company.name}.
      #         Current website: #{company.website}
      #         Research depth: #{research_depth || 'standard'}
      #       USER
      #     end
      #   end
      #
      # @example Context variables from agents
      #   class DocumentAnalysis < RAAF::DSL::Prompts::Base
      #     def system
      #       <<~SYSTEM
      #         You are a document analysis specialist.
      #         Document: #{document_name}
      #         Analysis type: #{analysis_type || 'standard'}
      #       SYSTEM
      #     end
      #
      #     def user
      #       "Please analyze the document using #{analysis_type || 'standard'} analysis."
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
        include RAAF::DSL::ContextAccess

        # Inheritance callback for setup
        #
        # @param subclass [Class] The inheriting subclass
        # @api private
        #
        def self.inherited(subclass)
          super
        end


        # Schema functionality has been moved to agent classes
        # Prompts now focus purely on content generation


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
            render_prompt(type)
          else
            # Default to rendering both as a hash
            render_messages
          end
        end

        # Perform dry-run validation to detect missing context variables
        def dry_run_validation!
          # Skip if no context to validate
          return if @context.nil? || @context.empty?
          
          # Create spy context
          spy = RAAF::DSL::ContextSpy.new(@context)
          
          # Track original context
          original_context = @context
          original_context_variables = @context_variables
          
          begin
            # Replace with spy
            @context = spy
            @context_variables = spy if @context_variables
            
            # Try to render both prompts (ignore errors, just track access)
            [:system, :user].each do |prompt_type|
              begin
                render(prompt_type)
              rescue => e
                # Ignore errors during dry run, we're just tracking access
              end
            end
            
          ensure
            # Restore original context
            @context = original_context
            @context_variables = original_context_variables
          end
          
          # Report missing variables
          if spy.missing_variables.any?
            # Try to find suggestions for missing variables
            suggestions = find_suggestions_for(spy.missing_variables, original_context.keys)
            
            error_msg = "Context validation failed for #{self.class.name}:\n" \
                        "  Missing variables: #{spy.missing_variables.uniq.inspect}\n" \
                        "  Available context: #{original_context.keys.inspect}\n" \
                        "  Accessed variables: #{spy.accessed_variables.uniq.inspect}\n"
            
            if suggestions.any?
              error_msg += "\n  Did you mean? #{suggestions.inspect}"
            end
            
            error_msg += "\n\nThis error was detected during dry-run validation before executing any agents."
            
            raise RAAF::DSL::Error, error_msg
          end
          
          true
        end

        # Check if context has all required variables (without throwing errors)
        def validate_context
          dry_run_validation!
          true
        rescue RAAF::DSL::Error => e
          false
        end

        protected

        # Render a specific prompt method
        def render_prompt(type)
          begin
            # Call the method and get its return value
            content = send(type)

            # If it's an array (multiple heredocs), join them
            if content.is_a?(Array)
              content.map(&:to_s).map(&:rstrip).join("\n\n")
            else
              content.to_s.rstrip
            end
          rescue StandardError => e
            # Re-raise with additional context but preserve the original error and stack trace
            raise e.class, "Error in #{type} method of #{self.class.name}: #{e.message}", e.backtrace
          end
        end

        private

        def find_suggestions_for(missing_vars, available_keys)
          suggestions = {}
          
          missing_vars.each do |missing|
            missing_str = missing.to_s
            
            # Find similar keys (pluralization, partial matches)
            similar = available_keys.select do |key|
              key_str = key.to_s
              
              # Basic pluralization/singularization (simple approach)
              missing_singular = missing_str.end_with?('s') ? missing_str.chomp('s') : missing_str
              missing_plural = missing_str.end_with?('s') ? missing_str : "#{missing_str}s"
              key_singular = key_str.end_with?('s') ? key_str.chomp('s') : key_str
              key_plural = key_str.end_with?('s') ? key_str : "#{key_str}s"
              
              # Check for matches
              key_str.include?(missing_singular) ||
              key_str.include?(missing_plural) ||
              missing_str.include?(key_singular) ||
              missing_str.include?(key_plural) ||
              (key_singular == missing_singular && key_singular != key_str)
            end
            
            suggestions[missing] = similar unless similar.empty?
          end
          
          suggestions
        end

        # Context access now handled by RAAF::DSL::ContextAccess module
      end
    end
  end
end
