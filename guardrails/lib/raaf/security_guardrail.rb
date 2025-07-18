# frozen_string_literal: true

require_relative "../security"
require_relative "base"

module RAAF
  module Guardrails
    # Security guardrail to protect against various threats
    class SecurityGuardrail < Base
      attr_reader :scanner, :policies

      def initialize(policies: nil, **options)
        super(**options)
        @scanner = Security::Scanner.new(options[:scanner_config] || {})
        @policies = load_policies(policies)
        @violation_cache = {}
        @scan_cache = {}
      end

      def check(content, context = {})
        violations = []

        # Check content for security issues
        content_violations = check_content_security(content)
        violations.concat(content_violations)

        # Check context (agent, tools, etc.)
        if context[:agent]
          agent_violations = check_agent_security(context[:agent])
          violations.concat(agent_violations)
        end

        # Check for policy violations
        policy_violations = check_policies(content, context)
        violations.concat(policy_violations)

        # Cache results
        cache_key = generate_cache_key(content, context)
        @violation_cache[cache_key] = violations

        {
          allowed: violations.empty?,
          violations: violations,
          risk_level: assess_risk_level(violations),
          recommendations: generate_recommendations(violations)
        }
      end

      def filter(content, context = {})
        result = check(content, context)

        if result[:allowed]
          content
        else
          # Sanitize content based on violations
          sanitize_content(content, result[:violations])
        end
      end

      # Scan an agent for security issues
      def scan_agent(agent)
        cache_key = "agent_#{agent.name}_#{agent.object_id}"
        cached_result = @scan_cache[cache_key]

        return cached_result if cached_result && cache_fresh?(cached_result)

        result = @scanner.scan_agent(agent)
        result[:timestamp] = Time.now
        @scan_cache[cache_key] = result

        result
      end

      # Scan code for security issues
      def scan_code(code, language = :ruby)
        temp_file = create_temp_file(code, language)

        begin
          @scanner.scan(temp_file.path, type: :static_analysis)
        ensure
          temp_file.unlink
        end
      end

      # Check if a tool is safe to use
      def safe_tool?(tool, context = {})
        violations = []

        # Check tool permissions
        if defined?(tool.required_permissions)
          tool.required_permissions.each do |permission|
            next if allowed_permission?(permission, context)

            violations << {
              type: :permission,
              message: "Tool requires unauthorized permission: #{permission}"
            }
          end
        end

        # Check tool implementation
        if tool.respond_to?(:source_location)
          file, = tool.source_location
          if file && File.exist?(file)
            scan_result = @scanner.scan(file)
            violations.concat(scan_result[:issues]) if scan_result[:issues]
          end
        end

        violations.empty?
      end

      # Monitor runtime security
      def monitor_execution(&block)
        runtime_scanner = Security::RuntimeScanner.new(@config)

        # Start monitoring
        monitor_thread = Thread.new { runtime_scanner.scan(block) }

        # Execute block
        result = yield

        # Get monitoring results
        security_results = monitor_thread.value

        # Check for violations
        if security_results[:risk_assessment] == :high
          raise SecurityViolationError, "High risk behavior detected during execution"
        end

        result
      end

      private

      def load_policies(policies)
        default_policies.merge(policies || {})
      end

      def default_policies
        {
          # Content policies
          max_prompt_length: 10_000,
          forbidden_patterns: [
            /\bpassword\s*[:=]\s*["'][^"']+["']/i,
            /\bapi[_-]?key\s*[:=]\s*["'][^"']+["']/i,
            /-----BEGIN.*PRIVATE KEY-----/
          ],

          # Execution policies
          allowed_commands: %w[ls cat echo pwd date whoami],
          forbidden_commands: %w[rm sudo chmod chown curl wget nc ssh],
          max_execution_time: 30,

          # Network policies
          allowed_domains: [],
          forbidden_domains: ["localhost", "127.0.0.1", "0.0.0.0"],

          # Resource policies
          max_memory_mb: 1024,
          max_cpu_percent: 80,
          max_file_size_mb: 100
        }
      end

      def check_content_security(content)
        violations = []

        # Check length
        if content.length > @policies[:max_prompt_length]
          violations << {
            type: :length,
            severity: :medium,
            message: "Content exceeds maximum allowed length"
          }
        end

        # Check for forbidden patterns
        @policies[:forbidden_patterns].each do |pattern|
          next unless content.match?(pattern)

          violations << {
            type: :pattern,
            severity: :high,
            message: "Forbidden pattern detected in content",
            pattern: pattern.source
          }
        end

        # Check for injection attempts
        if injection_attempt?(content)
          violations << {
            type: :injection,
            severity: :critical,
            message: "Potential injection attack detected"
          }
        end

        violations
      end

      def check_agent_security(agent)
        violations = []

        # Scan agent
        scan_result = scan_agent(agent)

        if %i[high critical].include?(scan_result[:risk_level])
          violations << {
            type: :agent_risk,
            severity: scan_result[:risk_level],
            message: "Agent has security vulnerabilities",
            details: scan_result[:recommendations]
          }
        end

        # Check tools
        agent.tools.each do |tool|
          next if safe_tool?(tool)

          violations << {
            type: :unsafe_tool,
            severity: :high,
            message: "Unsafe tool detected: #{tool.name}"
          }
        end

        violations
      end

      def check_policies(content, context)
        violations = []

        # Check command execution
        if context[:command]
          command_parts = context[:command].split(/\s+/)
          base_command = command_parts.first

          if @policies[:forbidden_commands].include?(base_command)
            violations << {
              type: :forbidden_command,
              severity: :high,
              message: "Forbidden command: #{base_command}"
            }
          elsif !@policies[:allowed_commands].include?(base_command)
            violations << {
              type: :unauthorized_command,
              severity: :medium,
              message: "Unauthorized command: #{base_command}"
            }
          end
        end

        # Check network access
        if context[:url]
          domain = extract_domain(context[:url])

          if @policies[:forbidden_domains].include?(domain)
            violations << {
              type: :forbidden_domain,
              severity: :high,
              message: "Access to forbidden domain: #{domain}"
            }
          elsif !@policies[:allowed_domains].empty? && !@policies[:allowed_domains].include?(domain)
            violations << {
              type: :unauthorized_domain,
              severity: :medium,
              message: "Unauthorized domain access: #{domain}"
            }
          end
        end

        violations
      end

      def injection_attempt?(content)
        injection_patterns = [
          # Prompt injection patterns
          /ignore.*previous.*instructions/i,
          /disregard.*above/i,
          /new.*instructions.*:/i,
          /system.*prompt.*:/i,

          # Command injection patterns
          /;\s*rm\s+-rf/,
          /&&\s*curl.*\|.*sh/,
          /`[^`]*rm[^`]*`/,

          # SQL injection patterns
          /'\s*OR\s*'1'\s*=\s*'1/i,
          /;\s*DROP\s+TABLE/i,
          /UNION\s+SELECT/i
        ]

        injection_patterns.any? { |pattern| content.match?(pattern) }
      end

      def allowed_permission?(permission, context)
        # Check if permission is allowed based on context
        case permission
        when :file_read
          context[:allow_file_access]
        when :file_write
          context[:allow_file_write]
        when :network
          context[:allow_network]
        when :system
          context[:allow_system_commands]
        else
          false
        end
      end

      def sanitize_content(content, violations)
        sanitized = content.dup

        violations.each do |violation|
          case violation[:type]
          when :pattern
            # Redact sensitive patterns
            pattern = begin
              Regexp.new(violation[:pattern])
            rescue StandardError
              next
            end
            sanitized.gsub!(pattern) { |match| "[REDACTED:#{match.length}]" }
          when :length
            # Truncate content
            max_length = @policies[:max_prompt_length]
            sanitized = sanitized[0...max_length] + "...[TRUNCATED]"
          when :injection
            # Remove injection attempts
            sanitized = remove_injection_attempts(sanitized)
          end
        end

        sanitized
      end

      def remove_injection_attempts(content)
        # Remove common injection patterns
        content
          .gsub(/ignore.*previous.*instructions/i, "[REMOVED]")
          .gsub(/disregard.*above/i, "[REMOVED]")
          .gsub(/new.*instructions.*:/i, "[REMOVED]")
          .gsub(/system.*prompt.*:/i, "[REMOVED]")
      end

      def assess_risk_level(violations)
        return :minimal if violations.empty?

        severities = violations.map { |v| v[:severity] }

        if severities.include?(:critical)
          :critical
        elsif severities.include?(:high)
          :high
        elsif severities.include?(:medium)
          :medium
        else
          :low
        end
      end

      def generate_recommendations(violations)
        recommendations = []

        violation_types = violations.map { |v| v[:type] }.uniq

        violation_types.each do |type|
          case type
          when :pattern
            recommendations << "Remove or mask sensitive information from content"
          when :injection
            recommendations << "Review content for potential injection attacks"
          when :forbidden_command
            recommendations << "Use only authorized commands"
          when :agent_risk
            recommendations << "Review and fix agent security vulnerabilities"
          when :unsafe_tool
            recommendations << "Replace unsafe tools with secure alternatives"
          end
        end

        recommendations
      end

      def generate_cache_key(content, context)
        data = {
          content_hash: Digest::SHA256.hexdigest(content),
          context_keys: context.keys.sort
        }
        Digest::SHA256.hexdigest(data.to_json)
      end

      def cache_fresh?(cached_result)
        return false unless cached_result[:timestamp]

        Time.now - cached_result[:timestamp] < 3600 # 1 hour
      end

      def create_temp_file(code, language)
        extension = case language
                    when :ruby then ".rb"
                    when :python then ".py"
                    when :javascript then ".js"
                    else ".txt"
                    end

        temp_file = Tempfile.new(["code", extension])
        temp_file.write(code)
        temp_file.close
        temp_file
      end

      def extract_domain(url)
        uri = URI.parse(url)
        uri.host || url
      rescue URI::InvalidURIError
        url
      end

      class SecurityViolationError < StandardError; end
    end
  end
end
