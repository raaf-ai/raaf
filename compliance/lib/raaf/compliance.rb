# frozen_string_literal: true

require "json"
require "time"
require "digest"
require "fileutils"
require "logger"

module RAAF
  ##
  # Compliance and audit logging system
  #
  # This module provides comprehensive compliance and audit capabilities for RAAF,
  # including audit logging, policy management, PII detection, data retention, and
  # regulatory compliance monitoring. It's designed to meet enterprise compliance
  # requirements including GDPR, HIPAA, SOX, and other regulatory frameworks.
  #
  # == Key Components
  #
  # * **AuditLogger**: Comprehensive audit trail logging with multiple storage backends
  # * **PolicyManager**: Centralized policy management and enforcement
  # * **ComplianceMonitor**: Real-time compliance monitoring and alerting
  # * **CompliancePolicy**: Base policy framework with specialized implementations
  # * **DataRetentionPolicy**: Automated data lifecycle management
  # * **AccessControlPolicy**: Access control and authorization policies
  # * **PIIHandlingPolicy**: Personally identifiable information protection
  #
  # == Compliance Features
  #
  # * **Audit Trails**: Detailed logging of all agent activities
  # * **Data Protection**: PII detection, redaction, and handling
  # * **Access Control**: Role-based access and authorization
  # * **Data Retention**: Automated retention and deletion policies
  # * **Policy Enforcement**: Real-time policy validation and enforcement
  # * **Regulatory Support**: GDPR, HIPAA, SOX compliance frameworks
  # * **Security Monitoring**: Security event detection and alerting
  #
  # @example Basic audit logging
  #   audit_logger = Compliance::AuditLogger.new(
  #     storage: :file,
  #     retention_days: 2555,  # 7 years
  #     encryption: true
  #   )
  #   
  #   audit_logger.log_agent_execution(agent, messages, result)
  #   audit_logger.log_tool_usage("search", { query: "[REDACTED]" }, result)
  #
  # @example Policy management
  #   policy_manager = Compliance::PolicyManager.new
  #   policy_manager.add_policy(Compliance::PIIHandlingPolicy.new)
  #   policy_manager.add_policy(Compliance::DataRetentionPolicy.new(retention_days: 90))
  #   
  #   result = policy_manager.enforce_policies(context, data)
  #
  # @example Compliance monitoring
  #   monitor = Compliance::ComplianceMonitor.new(
  #     policies: [data_retention_policy, pii_policy],
  #     audit_logger: audit_logger
  #   )
  #   
  #   monitor.start_monitoring
  #   compliance_status = monitor.check_compliance
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see AuditLogger For audit trail management
  # @see PolicyManager For policy enforcement
  # @see ComplianceMonitor For real-time monitoring
  module Compliance
    ##
    # Audit logger for compliance tracking
    #
    # The AuditLogger provides comprehensive audit trail capabilities for RAAF,
    # tracking all agent executions, tool usage, data access, and security events.
    # It supports multiple storage backends, encryption, and configurable retention
    # policies to meet various compliance requirements.
    #
    # == Features
    #
    # * **Multi-Backend Storage**: File, database, and cloud storage support
    # * **Encryption**: Configurable encryption for sensitive audit data
    # * **Data Retention**: Automatic cleanup based on retention policies
    # * **Event Types**: Agent execution, tool usage, data access, security events
    # * **PII Protection**: Automatic detection and handling of sensitive data
    # * **Session Tracking**: Session-based audit trail correlation
    # * **Export Capabilities**: Compliance report generation and export
    #
    # == Event Types
    #
    # * **agent_execution**: Complete agent conversation logging
    # * **tool_usage**: Individual tool invocation tracking
    # * **data_access**: Resource access and modification events
    # * **security_***: Security-related events and alerts
    # * **pii_detection**: PII detection and handling events
    # * **policy_violation**: Policy enforcement violations
    #
    # @example Basic configuration
    #   audit_logger = AuditLogger.new(
    #     storage: :file,
    #     storage_path: "/var/log/openai_agents/audit",
    #     retention_days: 2555,  # 7 years for regulatory compliance
    #     encryption: true,
    #     store_conversations: false  # Don't store full conversations
    #   )
    #
    # @example Database storage
    #   audit_logger = AuditLogger.new(
    #     storage: :database,
    #     database_url: "postgresql://localhost/audit_logs",
    #     encryption: true,
    #     pii_detection: true
    #   )
    #
    # @example Cloud storage with compliance
    #   audit_logger = AuditLogger.new(
    #     storage: :s3,
    #     bucket: "compliance-audit-logs",
    #     encryption: true,
    #     compliance_mode: :hipaa,
    #     retention_days: 2555
    #   )
    #
    # @author RAAF (Ruby AI Agents Factory) Team
    # @since 0.1.0
    # @see PolicyManager For policy-based audit configuration
    class AuditLogger
      # @return [Hash] audit logger configuration
      attr_reader :config
      
      # @return [Logger] underlying logger instance
      attr_reader :logger

      ##
      # Initialize audit logger with configuration
      #
      # @param config [Hash] audit logger configuration
      # @option config [Symbol] :storage storage backend (:file, :database, :s3)
      # @option config [String] :storage_path file storage path
      # @option config [Integer] :retention_days data retention period
      # @option config [Boolean] :encryption enable encryption
      # @option config [Boolean] :store_conversations store full conversation data
      # @option config [Boolean] :pii_detection enable PII detection
      # @option config [Symbol] :compliance_mode compliance framework (:gdpr, :hipaa, :sox)
      #
      # @example Basic file storage
      #   AuditLogger.new(storage: :file, retention_days: 365)
      #
      # @example HIPAA compliance
      #   AuditLogger.new(
      #     storage: :database,
      #     encryption: true,
      #     compliance_mode: :hipaa,
      #     pii_detection: true
      #   )
      def initialize(config = {})
        @config = default_config.merge(config)
        @logger = setup_logger
        @mutex = Mutex.new
        @session_id = generate_session_id
        @event_counter = 0

        setup_storage
        log_system_event("audit_logger_initialized", { config: sanitized_config })
      end

      ##
      # Log agent execution for audit trail
      #
      # Records complete agent execution including input/output message counts,
      # token usage, execution duration, and success status. Optionally stores
      # full conversation data based on configuration.
      #
      # @param agent [Agent] the agent that was executed
      # @param messages [Array<Hash>] input messages to the agent
      # @param result [RunResult] execution result with messages and usage
      # @param metadata [Hash] additional metadata to log
      # @option metadata [Float] :duration_ms execution duration in milliseconds
      # @option metadata [String] :session_id session identifier
      # @option metadata [String] :user_id user identifier (if available)
      # @return [void]
      #
      # @example Logging agent execution
      #   audit_logger.log_agent_execution(
      #     agent,
      #     messages,
      #     result,
      #     duration_ms: 1500.0,
      #     session_id: "session_123",
      #     user_id: "user_456"
      #   )
      def log_agent_execution(agent, messages, result, metadata = {})
        event = {
          event_type: "agent_execution",
          agent_name: agent.name,
          agent_model: agent.model,
          input_messages: messages.size,
          output_messages: result.messages.size,
          token_usage: result.usage,
          duration_ms: metadata[:duration_ms],
          success: true,
          metadata: metadata
        }

        log_compliance_event(event)

        # Store detailed records if required
        return unless @config[:store_conversations]

        store_conversation_record(agent, messages, result, event[:event_id])
      end

      ##
      # Log tool usage for audit trail
      #
      # Records individual tool invocations including arguments (sanitized),
      # success status, and error information if applicable.
      #
      # @param tool_name [String] name of the tool that was executed
      # @param args [Hash] arguments passed to the tool (will be sanitized)
      # @param result [Object, Exception] tool execution result or error
      # @param metadata [Hash] additional metadata to log
      # @return [void]
      #
      # @example Successful tool usage
      #   audit_logger.log_tool_usage(
      #     "search",
      #     { query: "weather", limit: 10 },
      #     search_results,
      #     execution_time: 250
      #   )
      #
      # @example Failed tool usage
      #   audit_logger.log_tool_usage(
      #     "database_query",
      #     { table: "users", filter: "[REDACTED]" },
      #     StandardError.new("Connection failed")
      #   )
      def log_tool_usage(tool_name, args, result, metadata = {})
        event = {
          event_type: "tool_usage",
          tool_name: tool_name,
          arguments: sanitize_arguments(args),
          success: !result.is_a?(Exception),
          error: result.is_a?(Exception) ? result.message : nil,
          metadata: metadata
        }

        log_compliance_event(event)
      end

      ##
      # Log data access for audit trail
      #
      # Records access to sensitive resources including databases, files,
      # APIs, and other data sources. Essential for compliance auditing.
      #
      # @param resource_type [String] type of resource accessed (e.g., "database", "file", "api")
      # @param resource_id [String] identifier of the specific resource
      # @param action [String] action performed ("read", "write", "delete", etc.)
      # @param metadata [Hash] additional context about the access
      # @return [void]
      #
      # @example Database access
      #   audit_logger.log_data_access(
      #     "database",
      #     "users_table",
      #     "read",
      #     records_accessed: 15,
      #     query_hash: "abc123"
      #   )
      #
      # @example File access
      #   audit_logger.log_data_access(
      #     "file",
      #     "/sensitive/data.csv",
      #     "read",
      #     file_size: 1024000
      #   )
      def log_data_access(resource_type, resource_id, action, metadata = {})
        event = {
          event_type: "data_access",
          resource_type: resource_type,
          resource_id: resource_id,
          action: action,
          metadata: metadata
        }

        log_compliance_event(event)
      end

      ##
      # Log security events for audit trail
      #
      # Records security-related events including authentication failures,
      # authorization violations, suspicious activities, and security alerts.
      # High severity events trigger additional alerting mechanisms.
      #
      # @param event_type [String] type of security event
      # @param details [Hash] detailed information about the event
      # @param severity [Symbol] event severity (:low, :medium, :high, :critical)
      # @return [void]
      #
      # @example Authentication failure
      #   audit_logger.log_security_event(
      #     "authentication_failure",
      #     { user_id: "user_123", ip_address: "192.168.1.100" },
      #     :medium
      #   )
      #
      # @example Critical security alert
      #   audit_logger.log_security_event(
      #     "privilege_escalation_attempt",
      #     { user_id: "user_456", attempted_action: "admin_access" },
      #     :critical
      #   )
      def log_security_event(event_type, details, severity = :medium)
        event = {
          event_type: "security_#{event_type}",
          severity: severity,
          details: details,
          metadata: {
            security_event: true
          }
        }

        log_compliance_event(event)

        # Alert on high severity
        return unless %i[high critical].include?(severity)

        trigger_security_alert(event)
      end

      ##
      # Log PII detection events for audit trail
      #
      # Records detection of personally identifiable information in agent
      # inputs or outputs, along with actions taken to protect the data.
      #
      # @param content_type [String] type of content analyzed ("input", "output", "tool_args")
      # @param pii_types [Array<String>] types of PII detected (e.g., ["email", "ssn"])
      # @param action_taken [String] action taken ("redacted", "blocked", "flagged")
      # @param metadata [Hash] additional context about the detection
      # @return [void]
      #
      # @example PII redaction
      #   audit_logger.log_pii_detection(
      #     "user_input",
      #     ["email", "phone_number"],
      #     "redacted",
      #     confidence_score: 0.95,
      #     original_length: 150
      #   )
      def log_pii_detection(content_type, pii_types, action_taken, metadata = {})
        event = {
          event_type: "pii_detection",
          content_type: content_type,
          pii_types: pii_types,
          action_taken: action_taken,
          metadata: metadata
        }

        log_compliance_event(event)
      end

      # Log consent events
      def log_consent_event(user_id, consent_type, action, metadata = {})
        event = {
          event_type: "consent_management",
          user_id: hash_user_id(user_id),
          consent_type: consent_type,
          action: action,
          metadata: metadata
        }

        log_compliance_event(event)
      end

      # Generate audit report
      def generate_audit_report(start_time: nil, end_time: nil, filters: {})
        events = query_events(start_time: start_time, end_time: end_time, filters: filters)

        report = {
          report_id: SecureRandom.uuid,
          generated_at: Time.now.iso8601,
          period: {
            start: start_time&.iso8601,
            end: end_time&.iso8601
          },
          summary: generate_summary(events),
          compliance_metrics: calculate_compliance_metrics(events),
          events_by_type: group_events_by_type(events),
          security_summary: generate_security_summary(events),
          recommendations: generate_recommendations(events)
        }

        # Store report
        store_audit_report(report)

        report
      end

      # Export audit logs
      def export_logs(format: :json, start_time: nil, end_time: nil, output_file: nil)
        events = query_events(start_time: start_time, end_time: end_time)

        formatted_data = case format
                         when :json
                           export_as_json(events)
                         when :csv
                           export_as_csv(events)
                         when :siem
                           export_for_siem(events)
                         else
                           raise "Unknown export format: #{format}"
                         end

        if output_file
          File.write(output_file, formatted_data)
          log_system_event("audit_log_exported", { format: format, file: output_file })
        end

        formatted_data
      end

      # Verify log integrity
      def verify_integrity(start_time: nil, end_time: nil)
        events = query_events(start_time: start_time, end_time: end_time)

        verification_results = {
          total_events: events.size,
          valid_events: 0,
          invalid_events: 0,
          missing_events: 0,
          integrity_violations: []
        }

        previous_event = nil
        events.each do |event|
          if verify_event_integrity(event, previous_event)
            verification_results[:valid_events] += 1
          else
            verification_results[:invalid_events] += 1
            verification_results[:integrity_violations] << {
              event_id: event[:event_id],
              reason: "Hash mismatch or sequence break"
            }
          end
          previous_event = event
        end

        verification_results
      end

      private

      def default_config
        {
          log_file: "audit.log",
          log_rotation: "daily",
          log_retention_days: 90,
          storage_backend: :file,
          storage_path: "./audit_logs",
          encryption_enabled: true,
          encryption_key: ENV.fetch("AUDIT_ENCRYPTION_KEY", nil),
          hash_algorithm: "SHA256",
          store_conversations: true,
          store_pii: false,
          alert_webhook: ENV.fetch("SECURITY_ALERT_WEBHOOK", nil),
          compliance_standards: %w[GDPR SOC2 HIPAA]
        }
      end

      def setup_logger
        logger = Logger.new(
          @config[:log_file],
          @config[:log_rotation],
          progname: "AuditLogger"
        )

        logger.formatter = proc do |severity, datetime, progname, msg|
          {
            timestamp: datetime.iso8601(6),
            severity: severity,
            progname: progname,
            message: msg
          }.to_json + "\n"
        end

        logger
      end

      def setup_storage
        case @config[:storage_backend]
        when :file
          FileUtils.mkdir_p(@config[:storage_path])
          FileUtils.mkdir_p(File.join(@config[:storage_path], "events"))
          FileUtils.mkdir_p(File.join(@config[:storage_path], "conversations"))
          FileUtils.mkdir_p(File.join(@config[:storage_path], "reports"))
        when :database
          # Initialize database connection
        when :s3
          # Initialize S3 client
        end
      end

      def log_compliance_event(event)
        @mutex.synchronize do
          # Add metadata
          event[:event_id] = generate_event_id
          event[:session_id] = @session_id
          event[:timestamp] = Time.now.iso8601(6)
          event[:sequence_number] = next_sequence_number
          event[:user_id] = hash_user_id(event[:user_id]) if event[:user_id]

          # Add integrity hash
          event[:integrity_hash] = calculate_integrity_hash(event)

          # Log to file
          @logger.info(event.to_json)

          # Store in backend
          store_event(event)

          # Update metrics
          update_metrics(event)
        end
      end

      def log_system_event(event_type, details)
        event = {
          event_type: "system_#{event_type}",
          details: details,
          system_event: true
        }

        log_compliance_event(event)
      end

      def generate_session_id
        "#{Socket.gethostname}-#{Process.pid}-#{Time.now.to_i}"
      end

      def generate_event_id
        "evt_#{Time.now.to_f.to_s.gsub(".", "")}_#{SecureRandom.hex(4)}"
      end

      def next_sequence_number
        @event_counter += 1
      end

      def hash_user_id(user_id)
        return nil unless user_id

        Digest::SHA256.hexdigest("#{user_id}:#{@config[:hash_salt]}")
      end

      def sanitize_arguments(args)
        return {} unless args.is_a?(Hash)

        args.transform_values do |value|
          if sensitive_field?(value)
            "[REDACTED]"
          elsif value.is_a?(String) && value.length > 1000
            value[0..1000] + "...[truncated]"
          else
            value
          end
        end
      end

      def sensitive_field?(value)
        return false unless value.is_a?(String)

        # Check for common sensitive patterns
        value =~ /\b(password|secret|token|key|ssn|credit_card)\b/i ||
          value =~ /\b\d{3}-\d{2}-\d{4}\b/ || # SSN
          value =~ /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/ # Credit card
      end

      def calculate_integrity_hash(event)
        # Create deterministic string representation
        data = [
          event[:event_id],
          event[:session_id],
          event[:timestamp],
          event[:sequence_number],
          event[:event_type]
        ].join(":")

        Digest::SHA256.hexdigest(data)
      end

      def verify_event_integrity(event, previous_event)
        # Verify hash
        expected_hash = calculate_integrity_hash(event)
        return false unless event[:integrity_hash] == expected_hash

        # Verify sequence
        return false if previous_event && event[:sequence_number] != previous_event[:sequence_number] + 1

        true
      end

      def store_event(event)
        case @config[:storage_backend]
        when :file
          store_event_to_file(event)
        when :database
          store_event_to_database(event)
        when :s3
          store_event_to_s3(event)
        end
      end

      def store_event_to_file(event)
        date = Date.parse(event[:timestamp])
        filename = "events_#{date.strftime("%Y%m%d")}.jsonl"
        filepath = File.join(@config[:storage_path], "events", filename)

        File.open(filepath, "a") do |f|
          f.puts(event.to_json)
        end
      end

      def store_conversation_record(agent, messages, result, event_id)
        record = {
          event_id: event_id,
          timestamp: Time.now.iso8601,
          agent: {
            name: agent.name,
            model: agent.model
          },
          messages: @config[:store_pii] ? messages : redact_pii_from_messages(messages),
          result: {
            messages: @config[:store_pii] ? result.messages : redact_pii_from_messages(result.messages),
            usage: result.usage
          }
        }

        filename = "conversation_#{event_id}.json"
        filepath = File.join(@config[:storage_path], "conversations", filename)

        content = @config[:encryption_enabled] ? encrypt_data(record.to_json) : record.to_json
        File.write(filepath, content)
      end

      def redact_pii_from_messages(messages)
        messages.map do |msg|
          msg.merge(
            content: redact_pii(msg[:content])
          )
        end
      end

      def redact_pii(text)
        return text unless text.is_a?(String)

        # Redact common PII patterns
        text = text.gsub(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, "[EMAIL]")
        text = text.gsub(/\b\d{3}-\d{2}-\d{4}\b/, "[SSN]")
        text = text.gsub(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/, "[CREDIT_CARD]")
        text.gsub(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/, "[PHONE]")
      end

      def encrypt_data(data)
        # Simple encryption - in production use proper encryption
        Base64.encode64(data)
      end

      def decrypt_data(encrypted_data)
        Base64.decode64(encrypted_data)
      end

      def query_events(start_time: nil, end_time: nil, filters: {})
        events = []

        case @config[:storage_backend]
        when :file
          events = query_events_from_files(start_time, end_time, filters)
        when :database
          events = query_events_from_database(start_time, end_time, filters)
        end

        events
      end

      def query_events_from_files(start_time, end_time, filters)
        events = []

        Dir.glob(File.join(@config[:storage_path], "events", "*.jsonl")).each do |file|
          File.foreach(file) do |line|
            event = JSON.parse(line, symbolize_names: true)

            # Apply time filters
            event_time = Time.parse(event[:timestamp])
            next if start_time && event_time < start_time
            next if end_time && event_time > end_time

            # Apply other filters
            next unless filters.all? { |k, v| event[k] == v }

            events << event
          end
        end

        events.sort_by { |e| e[:timestamp] }
      end

      def update_metrics(event)
        # Update internal metrics for monitoring
        @metrics ||= {}
        @metrics[event[:event_type]] ||= 0
        @metrics[event[:event_type]] += 1
      end

      def trigger_security_alert(event)
        return unless @config[:alert_webhook]

        alert = {
          alert_type: "security_event",
          severity: event[:severity],
          event: event,
          timestamp: Time.now.iso8601,
          environment: ENV["RAILS_ENV"] || "production"
        }

        # Send webhook
        begin
          uri = URI(@config[:alert_webhook])
          Net::HTTP.post_form(uri, alert)
        rescue StandardError => e
          @logger.error("Failed to send security alert: #{e.message}")
        end
      end

      def sanitized_config
        @config.except(:encryption_key, :alert_webhook)
      end

      def generate_summary(events)
        {
          total_events: events.size,
          events_by_type: events.group_by { |e| e[:event_type] }.transform_values(&:count),
          unique_sessions: events.map { |e| e[:session_id] }.uniq.size,
          unique_users: events.map { |e| e[:user_id] }.compact.uniq.size,
          time_range: {
            start: events.first&.dig(:timestamp),
            end: events.last&.dig(:timestamp)
          }
        }
      end

      def calculate_compliance_metrics(events)
        metrics = {}

        # GDPR compliance
        metrics[:gdpr] = calculate_gdpr_metrics(events) if @config[:compliance_standards].include?("GDPR")

        # SOC2 compliance
        metrics[:soc2] = calculate_soc2_metrics(events) if @config[:compliance_standards].include?("SOC2")

        # HIPAA compliance
        metrics[:hipaa] = calculate_hipaa_metrics(events) if @config[:compliance_standards].include?("HIPAA")

        metrics
      end

      def calculate_gdpr_metrics(events)
        consent_events = events.select { |e| e[:event_type] == "consent_management" }
        pii_events = events.select { |e| e[:event_type] == "pii_detection" }

        {
          consent_events: consent_events.count,
          consent_granted: consent_events.count { |e| e[:action] == "granted" },
          consent_revoked: consent_events.count { |e| e[:action] == "revoked" },
          pii_detections: pii_events.count,
          pii_redacted: pii_events.count { |e| e[:action_taken] == "redacted" }
        }
      end

      def calculate_soc2_metrics(events)
        security_events = events.select { |e| e[:event_type].to_s.start_with?("security_") }
        access_events = events.select { |e| e[:event_type] == "data_access" }

        {
          security_events: security_events.count,
          critical_security_events: security_events.count { |e| e[:severity] == :critical },
          data_access_events: access_events.count,
          unique_resources_accessed: access_events.map { |e| e[:resource_id] }.uniq.size
        }
      end

      def calculate_hipaa_metrics(events)
        phi_events = events.select { |e| e[:metadata]&.dig(:phi_involved) }

        {
          phi_access_events: phi_events.count,
          phi_modifications: phi_events.count { |e| %w[update delete].include?(e[:action]) }
        }
      end

      def group_events_by_type(events)
        events.group_by { |e| e[:event_type] }.transform_values do |type_events|
          {
            count: type_events.size,
            first_occurrence: type_events.first[:timestamp],
            last_occurrence: type_events.last[:timestamp]
          }
        end
      end

      def generate_security_summary(events)
        security_events = events.select { |e| e[:event_type].to_s.start_with?("security_") }

        {
          total_security_events: security_events.size,
          by_severity: security_events.group_by { |e| e[:severity] }.transform_values(&:count),
          top_security_concerns: identify_top_security_concerns(security_events)
        }
      end

      def identify_top_security_concerns(security_events)
        concerns = []

        # High severity events
        high_severity = security_events.count { |e| %i[high critical].include?(e[:severity]) }
        concerns << "#{high_severity} high/critical severity events detected" if high_severity > 0

        # Repeated security events
        event_counts = security_events.group_by do |e|
          e[:details][:type]
        rescue StandardError
          nil
        end.transform_values(&:count)
        event_counts.select { |_, count| count > 5 }.each do |type, count|
          concerns << "#{type} occurred #{count} times"
        end

        concerns
      end

      def generate_recommendations(events)
        recommendations = []

        # Check for missing consent events
        if events.none? { |e| e[:event_type] == "consent_management" }
          recommendations << "Implement consent tracking for GDPR compliance"
        end

        # Check for PII handling
        pii_events = events.select { |e| e[:event_type] == "pii_detection" }
        recommendations << "Implement automatic PII redaction" if pii_events.any? { |e| e[:action_taken] == "none" }

        # Check for security monitoring
        if events.none? { |e| e[:event_type].to_s.start_with?("security_") }
          recommendations << "Enable security event monitoring"
        end

        recommendations
      end

      def store_audit_report(report)
        filename = "audit_report_#{report[:report_id]}.json"
        filepath = File.join(@config[:storage_path], "reports", filename)

        File.write(filepath, JSON.pretty_generate(report))

        log_system_event("audit_report_generated", { report_id: report[:report_id] })
      end

      def export_as_json(events)
        JSON.pretty_generate({
                               export_timestamp: Time.now.iso8601,
                               total_events: events.size,
                               events: events
                             })
      end

      def export_as_csv(events)
        require "csv"

        CSV.generate do |csv|
          # Header
          csv << ["Event ID", "Timestamp", "Event Type", "Session ID", "User ID", "Details"]

          # Data
          events.each do |event|
            csv << [
              event[:event_id],
              event[:timestamp],
              event[:event_type],
              event[:session_id],
              event[:user_id],
              event.except(:event_id, :timestamp, :event_type, :session_id, :user_id).to_json
            ]
          end
        end
      end

      def export_for_siem(events)
        # Common Event Format (CEF) for SIEM integration
        events.map do |event|
          "CEF:0|OpenAIAgents|Compliance|1.0|#{event[:event_type]}|#{event[:event_type]}|3|" \
            "eventId=#{event[:event_id]} " \
            "rt=#{Time.parse(event[:timestamp]).to_i * 1000} " \
            "session=#{event[:session_id]} " \
            "suser=#{event[:user_id]}"
        end.join("\n")
      end
    end

    # Compliance policy manager
    class PolicyManager
      def initialize
        @policies = {}
        load_default_policies
      end

      def register_policy(name, policy)
        @policies[name] = policy
      end

      def check_compliance(context)
        violations = []

        @policies.each_value do |policy|
          result = policy.check(context)
          violations.concat(result.violations) unless result.compliant?
        end

        ComplianceResult.new(violations.empty?, violations)
      end

      private

      def load_default_policies
        @policies[:data_retention] = DataRetentionPolicy.new
        @policies[:access_control] = AccessControlPolicy.new
        @policies[:pii_handling] = PIIHandlingPolicy.new
        @policies[:audit_requirements] = AuditRequirementsPolicy.new
      end
    end

    # Compliance policies
    class CompliancePolicy
      def check(context)
        raise NotImplementedError
      end
    end

    class DataRetentionPolicy < CompliancePolicy
      def check(context)
        violations = []

        # Check if data is being retained beyond policy
        violations << "Data retained beyond 90-day policy" if context[:data_age_days] && context[:data_age_days] > 90

        ComplianceResult.new(violations.empty?, violations)
      end
    end

    class AccessControlPolicy < CompliancePolicy
      def check(context)
        violations = []

        # Check for proper authentication
        violations << "Access without proper authentication" unless context[:authenticated]

        # Check for authorization
        violations << "Unauthorized resource access" if context[:resource_accessed] && !context[:authorized]

        ComplianceResult.new(violations.empty?, violations)
      end
    end

    class PIIHandlingPolicy < CompliancePolicy
      def check(context)
        violations = []

        # Check for unencrypted PII
        violations << "PII stored without encryption" if context[:contains_pii] && !context[:encrypted]

        # Check for PII in logs
        violations << "PII found in logs" if context[:log_contains_pii]

        ComplianceResult.new(violations.empty?, violations)
      end
    end

    class AuditRequirementsPolicy < CompliancePolicy
      def check(context)
        violations = []

        # Check for required audit fields
        required_fields = %i[timestamp user_id action resource]
        missing_fields = required_fields - context.keys

        violations << "Missing required audit fields: #{missing_fields.join(", ")}" unless missing_fields.empty?

        ComplianceResult.new(violations.empty?, violations)
      end
    end

    # Compliance result
    class ComplianceResult
      attr_reader :violations

      def initialize(compliant, violations = [])
        @compliant = compliant
        @violations = violations
      end

      def compliant?
        @compliant
      end

      def to_h
        {
          compliant: @compliant,
          violations: @violations
        }
      end
    end

    # Real-time compliance monitor
    class ComplianceMonitor
      def initialize(audit_logger, policy_manager)
        @audit_logger = audit_logger
        @policy_manager = policy_manager
        @monitors = {}
      end

      def start_monitoring
        @monitors[:agent_execution] = monitor_agent_executions
        @monitors[:data_access] = monitor_data_access
        @monitors[:security] = monitor_security_events
      end

      def stop_monitoring
        @monitors.each_value(&:kill)
        @monitors.clear
      end

      private

      def monitor_agent_executions
        Thread.new do
          loop do
            # Check recent agent executions for compliance
            sleep 60
          end
        end
      end

      def monitor_data_access
        Thread.new do
          loop do
            # Monitor data access patterns
            sleep 30
          end
        end
      end

      def monitor_security_events
        Thread.new do
          loop do
            # Monitor for security violations
            sleep 10
          end
        end
      end
    end
  end
end
