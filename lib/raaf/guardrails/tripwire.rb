# frozen_string_literal: true

require_relative "base_guardrail"
require_relative "../logging"

module RubyAIAgentsFactory
  module Guardrails
    # Tripwire Guardrail - Immediately stops execution when triggered
    #
    # This guardrail can immediately halt agent execution when it detects
    # dangerous content, security violations, or other critical issues.
    # Unlike other guardrails that may modify or reject content, tripwires
    # throw exceptions that stop the entire execution flow.
    #
    # @example Basic usage
    #   tripwire = TripwireGuardrail.new(
    #     patterns: [/DROP TABLE/i, /DELETE FROM/i],
    #     keywords: ["hack", "exploit", "malware"]
    #   )
    #   agent.add_guardrail(tripwire)
    #
    # @example With custom detector
    #   tripwire = TripwireGuardrail.new do |content|
    #     content.include?("URGENT") && content.include?("wire transfer")
    #   end
    class TripwireGuardrail < BaseGuardrail
      include Logger
      class TripwireException < StandardError
        attr_reader :triggered_by, :content, :metadata

        def initialize(message, triggered_by:, content:, metadata: {})
          super(message)
          @triggered_by = triggered_by
          @content = content
          @metadata = metadata
        end
      end

      def initialize(patterns: [], keywords: [], custom_detector: nil, &block)
        super()
        @patterns = patterns
        @keywords = keywords.map(&:downcase)
        @custom_detector = custom_detector || block
        @triggered_count = 0
        @trigger_log = []
      end

      def check_input(content)
        check_content(content, "input")
      end

      def check_output(content)
        check_content(content, "output")
      end

      def check_tool_call(tool_name, arguments)
        # Check tool name
        if dangerous_tool?(tool_name)
          trigger_tripwire(
            "Dangerous tool call detected",
            triggered_by: "tool_name",
            content: { tool: tool_name, arguments: arguments }
          )
        end

        # Check arguments
        arg_string = arguments.to_s
        check_content(arg_string, "tool_arguments")

        # Tool-specific checks
        case tool_name
        when /shell|command|exec/i
          check_shell_command(arguments)
        when /sql|query|database/i
          check_sql_query(arguments)
        when /file|write|delete/i
          check_file_operation(arguments)
        end
      end

      # Get statistics about tripwire triggers
      def stats
        {
          triggered_count: @triggered_count,
          trigger_log: @trigger_log.last(10),
          patterns: @patterns.size,
          keywords: @keywords.size,
          has_custom_detector: !@custom_detector.nil?
        }
      end

      # Reset the tripwire state
      def reset!
        @triggered_count = 0
        @trigger_log.clear
      end

      private

      def check_content(content, context)
        return unless content

        content_str = content.to_s

        # Check patterns
        @patterns.each do |pattern|
          next unless content_str.match?(pattern)

          trigger_tripwire(
            "Dangerous pattern detected: #{pattern.inspect}",
            triggered_by: "pattern",
            content: content_str,
            metadata: { context: context, pattern: pattern.to_s }
          )
        end

        # Check keywords
        content_lower = content_str.downcase
        @keywords.each do |keyword|
          next unless content_lower.include?(keyword)

          trigger_tripwire(
            "Dangerous keyword detected: '#{keyword}'",
            triggered_by: "keyword",
            content: content_str,
            metadata: { context: context, keyword: keyword }
          )
        end

        # Check custom detector
        return unless @custom_detector

        begin
          if @custom_detector.call(content_str)
            trigger_tripwire(
              "Custom detector triggered",
              triggered_by: "custom",
              content: content_str,
              metadata: { context: context }
            )
          end
        rescue StandardError => e
          # Don't let custom detector errors break the flow
          log_error("Custom detector error: #{e.message}", guardrail: "TripwireGuardrail", error_class: e.class.name)
        end
      end

      def trigger_tripwire(message, triggered_by:, content:, metadata: {})
        @triggered_count += 1

        log_entry = {
          timestamp: Time.now,
          message: message,
          triggered_by: triggered_by,
          content_preview: content.to_s[0..100],
          metadata: metadata
        }

        @trigger_log << log_entry

        # Throw the tripwire exception
        raise TripwireException.new(
          message,
          triggered_by: triggered_by,
          content: content,
          metadata: metadata
        )
      end

      def dangerous_tool?(tool_name)
        dangerous_tools = %w[
          rm delete destroy
          eval exec system
          __send__ send instance_eval class_eval module_eval
        ]

        dangerous_tools.any? { |danger| tool_name.to_s.downcase.include?(danger) }
      end

      def check_shell_command(arguments)
        dangerous_commands = %w[
          rm curl wget
          chmod chown
          sudo su
          eval exec
          python perl ruby php
          nc netcat
          base64
        ]

        command = arguments[:command] || arguments["command"] || ""

        dangerous_commands.each do |cmd|
          next unless command.include?(cmd)

          trigger_tripwire(
            "Dangerous shell command: #{cmd}",
            triggered_by: "shell_command",
            content: command,
            metadata: { command: cmd }
          )
        end
      end

      def check_sql_query(arguments)
        dangerous_sql = [
          /DROP\s+(TABLE|DATABASE)/i,
          /DELETE\s+FROM/i,
          /TRUNCATE/i,
          /INSERT\s+INTO\s+.*\s+VALUES.*;.*;/i, # SQL injection pattern
          /UNION\s+SELECT/i,
          /OR\s+1\s*=\s*1/i
        ]

        query = arguments[:query] || arguments["query"] || ""

        dangerous_sql.each do |pattern|
          next unless query.match?(pattern)

          trigger_tripwire(
            "Dangerous SQL detected",
            triggered_by: "sql_query",
            content: query,
            metadata: { pattern: pattern.to_s }
          )
        end
      end

      def check_file_operation(arguments)
        dangerous_paths = [
          %r{^/etc/},
          %r{^/sys/},
          %r{^/root/},
          /\.\./, # Directory traversal
          /~/, # Home directory expansion
          /^\$/ # Environment variable
        ]

        path = arguments[:path] || arguments[:file_path] ||
               arguments["path"] || arguments["file_path"] || ""

        dangerous_paths.each do |pattern|
          next unless path.match?(pattern)

          trigger_tripwire(
            "Dangerous file path detected",
            triggered_by: "file_path",
            content: path,
            metadata: { pattern: pattern.to_s }
          )
        end
      end
    end

    # Composite tripwire that combines multiple tripwires
    class CompositeTripwire < TripwireGuardrail
      def initialize
        super(patterns: [], keywords: [])
        @tripwires = []
      end

      def add_tripwire(tripwire)
        @tripwires << tripwire
        self
      end

      def check_input(content)
        @tripwires.each { |t| t.check_input(content) }
        super
      end

      def check_output(content)
        @tripwires.each { |t| t.check_output(content) }
        super
      end

      def check_tool_call(tool_name, arguments)
        @tripwires.each { |t| t.check_tool_call(tool_name, arguments) }
        super
      end
    end

    # Pre-configured tripwires for common security concerns
    module CommonTripwires
      # SQL injection prevention
      def self.sql_injection
        TripwireGuardrail.new(
          patterns: [
            /;\s*DROP\s+/i,
            /;\s*DELETE\s+/i,
            /UNION\s+SELECT/i,
            /OR\s+1\s*=\s*1/i,
            /'\s+OR\s+'/i
          ]
        )
      end

      # Command injection prevention
      def self.command_injection
        TripwireGuardrail.new(
          patterns: [
            /;\s*(rm|del)\s+/i,
            /\|\s*rm\s+/i,
            /`[^`]*rm[^`]*`/,
            /\$\([^)]*rm[^)]*\)/,
            /&&\s*rm\s+/i
          ],
          keywords: %w[eval exec system __send__]
        )
      end

      # Path traversal prevention
      def self.path_traversal
        TripwireGuardrail.new(
          patterns: [
            %r{\.\.[/\\]},
            /\.\.%2[Ff]/,
            /%2[Ee]\s*%2[Ee]/
          ]
        )
      end

      # Sensitive data exposure
      def self.sensitive_data
        TripwireGuardrail.new(
          patterns: [
            /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, # Email
            /\b\d{3}-\d{2}-\d{4}\b/, # SSN
            /\b4[0-9]{12}(?:[0-9]{3})?\b/, # Visa
            /\b5[1-5][0-9]{14}\b/, # Mastercard
            /\b3[47][0-9]{13}\b/, # Amex
            /(?:password|pwd|pass)\s*[:=]\s*['"]?[^\s'"]+/i
          ]
        )
      end

      # Financial fraud detection
      def self.financial_fraud
        TripwireGuardrail.new(
          keywords: ["wire transfer", "western union", "bitcoin", "crypto wallet"],
          custom_detector: proc do |content|
            # Detect urgency + money patterns
            urgent = content.match?(/urgent|immediately|asap|now/i)
            money = content.match?(/\$\d+|\d+\s*(?:usd|dollars|euros|pounds)/i)
            transfer = content.match?(/transfer|send|wire|payment/i)

            urgent && money && transfer
          end
        )
      end

      # Create a combined security tripwire
      def self.all_security
        CompositeTripwire.new.tap do |composite|
          composite.add_tripwire(sql_injection)
          composite.add_tripwire(command_injection)
          composite.add_tripwire(path_traversal)
          composite.add_tripwire(sensitive_data)
        end
      end
    end
  end
end
