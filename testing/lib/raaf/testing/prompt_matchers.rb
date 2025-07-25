# frozen_string_literal: true

# Custom RSpec matchers for AI Agent DSL prompt testing
#
# This module provides a comprehensive set of matchers for testing AI Agent DSL prompts,
# including content validation, context handling, and validation testing.
#
# @example Basic usage
#   require 'raaf/testing/prompt_matchers'
#
#   RSpec.describe MyPrompt do
#     it "includes expected content" do
#       expect(MyPrompt).to include_prompt_content("analysis")
#         .with_context(document: "test.pdf")
#     end
#   end
#
# @since 0.1.0
module RAAF
  module Testing
    module PromptMatchers

      # Only define matchers if RSpec is available
      if defined?(::RSpec)
        # Matcher for testing prompt content inclusion
        #
        # @example Basic usage
        #   expect(prompt).to include_prompt_content("OpenAI")
        #   expect(prompt).to include_prompt_content("document", in: :system)
        #   expect(prompt).to include_prompt_content(/analysis.*complete/, in: :user)
        #
        # @example With context validation
        #   expect(prompt).to include_prompt_content("Test Document")
        #     .with_context(document: { name: "Test Document" })
        #
        # @example Multiple expectations
        #   expect(prompt).to include_prompt_content("system prompt", "analysis")
        #     .in_prompt(:system)
        #
        ::RSpec::Matchers.define :include_prompt_content do |*expected_content|
          match do |prompt_instance_or_class|
            @prompt = resolve_prompt(prompt_instance_or_class)
            @rendered_content = render_prompts(@prompt)

            check_content_inclusion(expected_content, @rendered_content)
          end

          chain :in_prompt do |prompt_type|
            @prompt_type = prompt_type.to_sym
          end

          chain :with_context do |context|
            @context = context
          end

          chain :and_not_include do |*excluded_content|
            @excluded_content = excluded_content.flatten
          end

          failure_message do
            build_failure_message(expected_content, @rendered_content, inclusion: true)
          end

          failure_message_when_negated do
            build_failure_message(expected_content, @rendered_content, inclusion: false)
          end

          description do
            prompt_desc = @prompt_type ? "#{@prompt_type} prompt" : "prompts"
            content_desc = expected_content.map(&:inspect).join(", ")
            "include #{content_desc} in #{prompt_desc}"
          end

          # Support for block syntax to test prompt rendering
          supports_block_expectations

          private

          def resolve_prompt(prompt_instance_or_class)
            case prompt_instance_or_class
            when Class
              raise ArgumentError, "Context required when testing prompt class. Use .with_context()" unless @context

              # Ensure common non-context variables are provided in context
              enhanced_context = @context.dup
              enhanced_context[:processing_params] ||= {}
              enhanced_context[:agent_name] ||= "TestAgent"

              prompt_instance_or_class.new(**enhanced_context)

            when RAAF::DSL::Prompts::Base
              raise ArgumentError, "Context should not be provided when testing prompt instance" if @context

              prompt_instance_or_class
            else
              raise ArgumentError, "Expected prompt class or instance, got #{prompt_instance_or_class.class}"
            end
          end

          def render_prompts(prompt)
            if @prompt_type
              { @prompt_type => prompt.render(@prompt_type) }
            else
              prompt.render_messages
            end
          rescue RAAF::DSL::Prompts::VariableContractError => e
            @validation_error = e
            raise ::RSpec::Expectations::ExpectationNotMetError,
                  "Prompt validation failed: #{e.message}. Consider using .with_context() to " \
                  "provide required variables."
          end

          def check_content_inclusion(expected_content, rendered_content)
            success = true
            @missing_content = []
            @unexpected_content = []

            # Check for expected content
            expected_content.flatten.each do |content|
              found = rendered_content.values.any? { |text| matches_content?(text, content) }
              unless found
                success = false
                @missing_content << content
              end
            end

            # Check for excluded content if specified
            @excluded_content&.each do |content|
              found = rendered_content.values.any? { |text| matches_content?(text, content) }
              if found
                success = false
                @unexpected_content << content
              end
            end

            success
          end

          def matches_content?(text, pattern)
            case pattern
            when String
              text.include?(pattern)
            when Regexp
              text.match?(pattern)
            else
              text.to_s.include?(pattern.to_s)
            end
          end

          def build_failure_message(expected_content, rendered_content, inclusion:)
            lines = []

            if inclusion
              lines << "Expected prompt to include: #{expected_content.map(&:inspect).join(", ")}"
              lines << "Missing content: #{@missing_content.map(&:inspect).join(", ")}" if @missing_content&.any?
              if @unexpected_content&.any?
                lines << "Unexpected content: #{@unexpected_content.map(&:inspect).join(", ")}"
              end
            else
              lines << "Expected prompt NOT to include: #{expected_content.map(&:inspect).join(", ")}"
              lines << "But found: #{@unexpected_content.map(&:inspect).join(", ")}" if @unexpected_content&.any?
            end

            lines << ""
            lines << "Rendered content:"
            if rendered_content
              rendered_content.each do |type, content|
                lines << "  #{type}:"
                content.split("\n").each { |line| lines << "    #{line}" }
                lines << ""
              end
            else
              lines << "  (No content rendered due to validation error)"
            end

            lines.join("\n")
          end
        end

        # Matcher for testing prompt validation
        #
        # @example Test validation success
        #   expect(prompt).to validate_prompt_successfully
        #   expect(MyPrompt).to validate_prompt_successfully.with_context(required_field: "value")
        #
        # @example Test validation failure
        #   expect(prompt).to fail_prompt_validation.with_error(/Missing required/)
        #   expect(MyPrompt).to fail_prompt_validation.with_context({}).with_error("Missing required variables")
        #
        ::RSpec::Matchers.define :validate_prompt_successfully do
          match do |prompt_instance_or_class|
            @prompt = resolve_prompt_for_validation(prompt_instance_or_class)

            begin
              @prompt.validate!
              true
            rescue RAAF::DSL::Prompts::VariableContractError => e
              @validation_error = e
              false
            end
          end

          chain :with_context do |context|
            @context = context
          end

          failure_message do
            "Expected prompt to validate successfully, but validation failed with: #{@validation_error.message}"
          end

          failure_message_when_negated do
            "Expected prompt validation to fail, but it succeeded"
          end

          description do
            "validate successfully"
          end

          private

          def resolve_prompt_for_validation(prompt_instance_or_class)
            case prompt_instance_or_class
            when Class
              context = @context || {}
              prompt_instance_or_class.new(**context)
            when RAAF::DSL::Prompts::Base
              raise ArgumentError, "Context should not be provided when testing prompt instance" if @context

              prompt_instance_or_class
            else
              raise ArgumentError, "Expected prompt class or instance, got #{prompt_instance_or_class.class}"
            end
          end
        end

        # Matcher for testing prompt validation failures
        ::RSpec::Matchers.define :fail_prompt_validation do
          match do |prompt_instance_or_class|
            @prompt = resolve_prompt_for_validation(prompt_instance_or_class)

            begin
              @prompt.validate!
              false
            rescue RAAF::DSL::Prompts::VariableContractError => e
              @validation_error = e
              if @expected_error
                matches_error?(@expected_error, e.message)
              else
                true
              end
            end
          end

          chain :with_context do |context|
            @context = context
          end

          chain :with_error do |error_pattern|
            @expected_error = error_pattern
          end

          failure_message do
            if @validation_error
              "Expected validation to fail with #{@expected_error.inspect}, but got: #{@validation_error.message}"
            else
              expected_desc = @expected_error ? " with error #{@expected_error.inspect}" : ""
              "Expected prompt validation to fail#{expected_desc}, but it succeeded"
            end
          end

          failure_message_when_negated do
            "Expected prompt validation to succeed, but it failed with: #{@validation_error&.message}"
          end

          description do
            error_desc = @expected_error ? " with error #{@expected_error.inspect}" : ""
            "fail validation#{error_desc}"
          end

          private

          def resolve_prompt_for_validation(prompt_instance_or_class)
            case prompt_instance_or_class
            when Class
              context = @context || {}
              prompt_instance_or_class.new(**context)
            when RAAF::DSL::Prompts::Base
              raise ArgumentError, "Context should not be provided when testing prompt instance" if @context

              prompt_instance_or_class
            else
              raise ArgumentError, "Expected prompt class or instance, got #{prompt_instance_or_class.class}"
            end
          end

          def matches_error?(pattern, message)
            case pattern
            when String
              message.include?(pattern)
            when Regexp
              message.match?(pattern)
            else
              message.include?(pattern.to_s)
            end
          end
        end

        # Matcher for testing prompt context access
        #
        # @example Test context variable access
        #   expect(prompt).to have_prompt_context_variable(:document_name).with_value("Test Doc")
        #   expect(prompt).to have_prompt_context_variable(:optional_field).with_default("default_value")
        #
        ::RSpec::Matchers.define :have_prompt_context_variable do |variable_name|
          match do |prompt|
            @variable_name = variable_name

            begin
              @actual_value = prompt.send(variable_name)
              if @expected_value
                @actual_value == @expected_value
              else
                true # Just check that variable exists and doesn't raise error
              end
            rescue NoMethodError
              false
            rescue RAAF::DSL::Prompts::VariableContractError => e
              @contract_error = e
              false
            end
          end

          chain :with_value do |expected_value|
            @expected_value = expected_value
          end

          chain :with_default do |default_value|
            @expected_value = default_value
          end

          failure_message do
            if @contract_error
              "Expected prompt to have context variable #{@variable_name.inspect}, but got " \
              "contract error: #{@contract_error.message}"
            elsif @expected_value
              "Expected context variable #{@variable_name.inspect} to have value " \
              "#{@expected_value.inspect}, but got #{@actual_value.inspect}"
            else
              "Expected prompt to have context variable #{@variable_name.inspect}, but it doesn't exist"
            end
          end

          failure_message_when_negated do
            "Expected prompt NOT to have context variable #{@variable_name.inspect}, but it does"
          end

          description do
            if @expected_value
              "have context variable #{@variable_name.inspect} with value #{@expected_value.inspect}"
            else
              "have context variable #{@variable_name.inspect}"
            end
          end
        end

      end

    end
  end
end