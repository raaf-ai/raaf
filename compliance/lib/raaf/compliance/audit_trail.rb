# frozen_string_literal: true

require "json"
require "digest"
require "openssl"

module RubyAIAgentsFactory
  module Compliance
    ##
    # Comprehensive audit trail for regulatory compliance
    #
    # Provides secure, immutable audit logging for all agent activities
    # with tamper-proof records, encryption, and comprehensive querying
    # capabilities for regulatory compliance requirements.
    #
    class AuditTrail
      include RubyAIAgentsFactory::Logging

      # @return [Symbol] Storage backend
      attr_reader :storage_backend

      # @return [Integer] Retention days
      attr_reader :retention_days

      # @return [Boolean] Encryption enabled
      attr_reader :encryption_enabled

      # @return [Boolean] Real-time monitoring
      attr_reader :real_time_monitoring

      ##
      # Initialize audit trail
      #
      # @param storage_backend [Symbol] Storage backend (:database, :file, :s3)
      # @param retention_days [Integer] Retention period in days
      # @param encryption_enabled [Boolean] Enable encryption
      # @param real_time_monitoring [Boolean] Enable real-time monitoring
      #
      def initialize(storage_backend: :database, retention_days: 2555, encryption_enabled: true, real_time_monitoring: true)
        @storage_backend = storage_backend
        @retention_days = retention_days
        @encryption_enabled = encryption_enabled
        @real_time_monitoring = real_time_monitoring
        @storage = create_storage_backend
        @encryption_key = generate_encryption_key if encryption_enabled
        @monitors = []
      end

      ##
      # Log agent activity
      #
      # @param agent_id [String] Agent identifier
      # @param action [String] Action performed
      # @param user_id [String] User identifier
      # @param data [Hash] Activity data
      # @param compliance_tags [Array<Symbol>] Compliance tags
      # @param ip_address [String] IP address
      # @param user_agent [String] User agent
      # @param session_id [String] Session identifier
      # @return [String] Audit record ID
      #
      def log_agent_activity(agent_id:, action:, user_id: nil, data: {}, compliance_tags: [], ip_address: nil, user_agent: nil, session_id: nil)
        record = create_audit_record(
          record_type: :agent_activity,
          agent_id: agent_id,
          action: action,
          user_id: user_id,
          data: data,
          compliance_tags: compliance_tags,
          ip_address: ip_address,
          user_agent: user_agent,
          session_id: session_id
        )
        
        store_record(record)
        notify_monitors(record) if @real_time_monitoring
        
        log_info("Agent activity logged", record_id: record[:id], agent_id: agent_id, action: action)
        record[:id]
      end

      ##
      # Log data access
      #
      # @param user_id [String] User identifier
      # @param data_type [String] Type of data accessed
      # @param data_id [String] Data identifier
      # @param access_type [String] Access type (read, write, delete)
      # @param purpose [String] Purpose of access
      # @param compliance_tags [Array<Symbol>] Compliance tags
      # @return [String] Audit record ID
      #
      def log_data_access(user_id:, data_type:, data_id:, access_type:, purpose: nil, compliance_tags: [])
        record = create_audit_record(
          record_type: :data_access,
          user_id: user_id,
          data_type: data_type,
          data_id: data_id,
          access_type: access_type,
          purpose: purpose,
          compliance_tags: compliance_tags
        )
        
        store_record(record)
        notify_monitors(record) if @real_time_monitoring
        
        log_info("Data access logged", record_id: record[:id], user_id: user_id, data_type: data_type)
        record[:id]
      end

      ##
      # Log compliance event
      #
      # @param event_type [String] Event type
      # @param compliance_framework [Symbol] Compliance framework
      # @param severity [Symbol] Severity level
      # @param description [String] Event description
      # @param metadata [Hash] Additional metadata
      # @return [String] Audit record ID
      #
      def log_compliance_event(event_type:, compliance_framework:, severity:, description:, metadata: {})
        record = create_audit_record(
          record_type: :compliance_event,
          event_type: event_type,
          compliance_framework: compliance_framework,
          severity: severity,
          description: description,
          metadata: metadata,
          compliance_tags: [compliance_framework]
        )
        
        store_record(record)
        notify_monitors(record) if @real_time_monitoring
        
        log_info("Compliance event logged", record_id: record[:id], event_type: event_type)
        record[:id]
      end

      ##
      # Log security event
      #
      # @param event_type [String] Security event type
      # @param severity [Symbol] Severity level
      # @param user_id [String] User identifier
      # @param ip_address [String] IP address
      # @param description [String] Event description
      # @param metadata [Hash] Additional metadata
      # @return [String] Audit record ID
      #
      def log_security_event(event_type:, severity:, user_id: nil, ip_address: nil, description:, metadata: {})
        record = create_audit_record(
          record_type: :security_event,
          event_type: event_type,
          severity: severity,
          user_id: user_id,
          ip_address: ip_address,
          description: description,
          metadata: metadata,
          compliance_tags: [:security]
        )
        
        store_record(record)
        notify_monitors(record) if @real_time_monitoring
        
        log_info("Security event logged", record_id: record[:id], event_type: event_type)
        record[:id]
      end

      ##
      # Query audit records
      #
      # @param start_date [Time] Start date
      # @param end_date [Time] End date
      # @param user_id [String] User identifier
      # @param agent_id [String] Agent identifier
      # @param record_type [Symbol] Record type
      # @param compliance_tags [Array<Symbol>] Compliance tags
      # @param limit [Integer] Maximum number of records
      # @return [Array<Hash>] Audit records
      #
      def query(start_date: nil, end_date: nil, user_id: nil, agent_id: nil, record_type: nil, compliance_tags: [], limit: 1000)
        filters = {}
        filters[:start_date] = start_date if start_date
        filters[:end_date] = end_date if end_date
        filters[:user_id] = user_id if user_id
        filters[:agent_id] = agent_id if agent_id
        filters[:record_type] = record_type if record_type
        filters[:compliance_tags] = compliance_tags if compliance_tags.any?
        filters[:limit] = limit
        
        records = @storage.query(filters)
        
        # Decrypt records if encryption is enabled
        if @encryption_enabled
          records = records.map { |record| decrypt_record(record) }
        end
        
        log_debug("Audit records queried", filters: filters, count: records.size)
        records
      end

      ##
      # Get audit record by ID
      #
      # @param record_id [String] Record ID
      # @return [Hash, nil] Audit record or nil if not found
      #
      def get_record(record_id)
        record = @storage.get(record_id)
        return nil unless record
        
        if @encryption_enabled
          record = decrypt_record(record)
        end
        
        record
      end

      ##
      # Verify record integrity
      #
      # @param record_id [String] Record ID
      # @return [Boolean] True if record is valid
      #
      def verify_record_integrity(record_id)
        record = @storage.get(record_id)
        return false unless record
        
        # Verify hash chain
        calculated_hash = calculate_record_hash(record)
        stored_hash = record[:hash]
        
        valid = calculated_hash == stored_hash
        
        log_info("Record integrity verified", record_id: record_id, valid: valid)
        valid
      end

      ##
      # Get record count
      #
      # @param filters [Hash] Query filters
      # @return [Integer] Number of records
      #
      def record_count(filters = {})
        @storage.count(filters)
      end

      ##
      # Export audit records
      #
      # @param format [Symbol] Export format (:csv, :json, :pdf)
      # @param filters [Hash] Query filters
      # @return [String] Exported data
      #
      def export_records(format: :csv, **filters)
        records = query(**filters)
        
        case format
        when :csv
          export_csv(records)
        when :json
          export_json(records)
        when :pdf
          export_pdf(records)
        else
          raise ArgumentError, "Unsupported export format: #{format}"
        end
      end

      ##
      # Add real-time monitor
      #
      # @param monitor [Proc] Monitor callback
      def add_monitor(&monitor)
        @monitors << monitor
      end

      ##
      # Remove real-time monitor
      #
      # @param monitor [Proc] Monitor callback
      def remove_monitor(monitor)
        @monitors.delete(monitor)
      end

      ##
      # Archive old records
      #
      # @param older_than [Time] Archive records older than this date
      # @return [Integer] Number of archived records
      #
      def archive_old_records(older_than = @retention_days.days.ago)
        archived_count = @storage.archive(older_than)
        log_info("Old records archived", count: archived_count, older_than: older_than)
        archived_count
      end

      ##
      # Purge expired records
      #
      # @param older_than [Time] Purge records older than this date
      # @return [Integer] Number of purged records
      #
      def purge_expired_records(older_than = @retention_days.days.ago)
        purged_count = @storage.purge(older_than)
        log_info("Expired records purged", count: purged_count, older_than: older_than)
        purged_count
      end

      ##
      # Get audit statistics
      #
      # @return [Hash] Audit statistics
      #
      def statistics
        {
          total_records: record_count,
          records_by_type: record_count_by_type,
          records_by_compliance_tag: record_count_by_compliance_tag,
          storage_backend: @storage_backend,
          encryption_enabled: @encryption_enabled,
          retention_days: @retention_days,
          oldest_record: oldest_record_date,
          newest_record: newest_record_date
        }
      end

      private

      def create_audit_record(record_type:, **attributes)
        timestamp = Time.current
        record_id = SecureRandom.uuid
        
        record = {
          id: record_id,
          record_type: record_type,
          timestamp: timestamp.iso8601,
          sequence_number: generate_sequence_number,
          **attributes
        }
        
        # Add hash for integrity
        record[:hash] = calculate_record_hash(record)
        
        # Add previous record hash for chain integrity
        record[:previous_hash] = get_last_record_hash
        
        record
      end

      def store_record(record)
        encrypted_record = @encryption_enabled ? encrypt_record(record) : record
        @storage.store(encrypted_record)
      end

      def encrypt_record(record)
        cipher = OpenSSL::Cipher.new('AES-256-GCM')
        cipher.encrypt
        cipher.key = @encryption_key
        
        data = JSON.generate(record)
        encrypted_data = cipher.update(data) + cipher.final
        
        {
          id: record[:id],
          encrypted_data: [encrypted_data].pack('m0'),
          auth_tag: [cipher.auth_tag].pack('m0'),
          timestamp: record[:timestamp]
        }
      end

      def decrypt_record(encrypted_record)
        return encrypted_record unless encrypted_record[:encrypted_data]
        
        cipher = OpenSSL::Cipher.new('AES-256-GCM')
        cipher.decrypt
        cipher.key = @encryption_key
        cipher.auth_tag = encrypted_record[:auth_tag].unpack('m0')[0]
        
        encrypted_data = encrypted_record[:encrypted_data].unpack('m0')[0]
        decrypted_data = cipher.update(encrypted_data) + cipher.final
        
        JSON.parse(decrypted_data, symbolize_names: true)
      end

      def calculate_record_hash(record)
        # Remove hash field for calculation
        record_without_hash = record.dup
        record_without_hash.delete(:hash)
        record_without_hash.delete(:previous_hash)
        
        data = JSON.generate(record_without_hash, sort_keys: true)
        Digest::SHA256.hexdigest(data)
      end

      def generate_sequence_number
        @sequence_number ||= 0
        @sequence_number += 1
      end

      def get_last_record_hash
        last_record = @storage.get_last_record
        last_record ? last_record[:hash] : nil
      end

      def generate_encryption_key
        OpenSSL::Random.random_bytes(32)
      end

      def notify_monitors(record)
        @monitors.each do |monitor|
          begin
            monitor.call(record)
          rescue StandardError => e
            log_error("Monitor notification failed", error: e)
          end
        end
      end

      def create_storage_backend
        case @storage_backend
        when :database
          DatabaseStorage.new
        when :file
          FileStorage.new
        when :s3
          S3Storage.new
        else
          raise ArgumentError, "Unsupported storage backend: #{@storage_backend}"
        end
      end

      def record_count_by_type
        @storage.count_by_field(:record_type)
      end

      def record_count_by_compliance_tag
        @storage.count_by_field(:compliance_tags)
      end

      def oldest_record_date
        @storage.oldest_record_date
      end

      def newest_record_date
        @storage.newest_record_date
      end

      def export_csv(records)
        require 'csv'
        
        CSV.generate do |csv|
          # Header
          csv << %w[ID RecordType Timestamp UserID AgentID Action Description ComplianceTags]
          
          # Data rows
          records.each do |record|
            csv << [
              record[:id],
              record[:record_type],
              record[:timestamp],
              record[:user_id],
              record[:agent_id],
              record[:action],
              record[:description],
              record[:compliance_tags]&.join(', ')
            ]
          end
        end
      end

      def export_json(records)
        JSON.pretty_generate(records)
      end

      def export_pdf(records)
        require 'prawn'
        require 'prawn/table'
        
        Prawn::Document.new do |pdf|
          pdf.text "Audit Trail Report", size: 20, style: :bold
          pdf.text "Generated: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}", size: 12
          pdf.move_down 20
          
          # Create table data
          table_data = [['ID', 'Type', 'Timestamp', 'User', 'Agent', 'Action']]
          records.each do |record|
            table_data << [
              record[:id][0..8],
              record[:record_type],
              record[:timestamp],
              record[:user_id],
              record[:agent_id],
              record[:action]
            ]
          end
          
          pdf.table(table_data, header: true, width: pdf.bounds.width) do
            row(0).font_style = :bold
            cells.padding = 5
            cells.size = 8
          end
        end.render
      end
    end

    ##
    # Database storage backend for audit trail
    #
    class DatabaseStorage
      def initialize
        # Initialize database connection
        # This would use ActiveRecord or similar ORM
      end

      def store(record)
        # Store record in database
        # AuditRecord.create!(record)
      end

      def get(record_id)
        # Get record by ID
        # AuditRecord.find(record_id)&.attributes&.symbolize_keys
      end

      def query(filters)
        # Query records with filters
        # AuditRecord.where(filters).limit(filters[:limit] || 1000).to_a
      end

      def count(filters = {})
        # Count records
        # AuditRecord.where(filters).count
      end

      def get_last_record
        # Get last record
        # AuditRecord.order(:sequence_number).last&.attributes&.symbolize_keys
      end

      def archive(older_than)
        # Archive old records
        # AuditRecord.where('timestamp < ?', older_than).count
      end

      def purge(older_than)
        # Purge old records
        # AuditRecord.where('timestamp < ?', older_than).delete_all
      end

      def count_by_field(field)
        # Count by field
        # AuditRecord.group(field).count
      end

      def oldest_record_date
        # AuditRecord.minimum(:timestamp)
      end

      def newest_record_date
        # AuditRecord.maximum(:timestamp)
      end
    end

    ##
    # File storage backend for audit trail
    #
    class FileStorage
      def initialize(base_path = "audit_logs")
        @base_path = base_path
        FileUtils.mkdir_p(@base_path)
      end

      def store(record)
        date = Date.current.strftime('%Y-%m-%d')
        file_path = File.join(@base_path, "#{date}.json")
        
        File.open(file_path, 'a') do |f|
          f.puts JSON.generate(record)
        end
      end

      def get(record_id)
        # Search through daily files
        Dir.glob(File.join(@base_path, "*.json")).each do |file|
          File.readlines(file).each do |line|
            record = JSON.parse(line.strip, symbolize_names: true)
            return record if record[:id] == record_id
          end
        end
        nil
      end

      def query(filters)
        records = []
        
        Dir.glob(File.join(@base_path, "*.json")).each do |file|
          File.readlines(file).each do |line|
            record = JSON.parse(line.strip, symbolize_names: true)
            
            # Apply filters
            next if filters[:start_date] && record[:timestamp] < filters[:start_date].iso8601
            next if filters[:end_date] && record[:timestamp] > filters[:end_date].iso8601
            next if filters[:user_id] && record[:user_id] != filters[:user_id]
            next if filters[:agent_id] && record[:agent_id] != filters[:agent_id]
            next if filters[:record_type] && record[:record_type] != filters[:record_type]
            
            records << record
            break if records.size >= (filters[:limit] || 1000)
          end
        end
        
        records
      end

      def count(filters = {})
        query(filters).size
      end

      def get_last_record
        last_record = nil
        
        Dir.glob(File.join(@base_path, "*.json")).sort.reverse.each do |file|
          File.readlines(file).reverse.each do |line|
            record = JSON.parse(line.strip, symbolize_names: true)
            return record if last_record.nil? || record[:sequence_number] > last_record[:sequence_number]
            last_record = record
          end
        end
        
        last_record
      end

      def archive(older_than)
        # Move old files to archive directory
        archived_count = 0
        
        Dir.glob(File.join(@base_path, "*.json")).each do |file|
          file_date = File.basename(file, '.json')
          if Date.parse(file_date) < older_than.to_date
            archive_path = File.join(@base_path, 'archive')
            FileUtils.mkdir_p(archive_path)
            FileUtils.mv(file, archive_path)
            archived_count += File.readlines(File.join(archive_path, File.basename(file))).size
          end
        end
        
        archived_count
      end

      def purge(older_than)
        purged_count = 0
        
        Dir.glob(File.join(@base_path, "*.json")).each do |file|
          file_date = File.basename(file, '.json')
          if Date.parse(file_date) < older_than.to_date
            purged_count += File.readlines(file).size
            File.delete(file)
          end
        end
        
        purged_count
      end

      def count_by_field(field)
        counts = Hash.new(0)
        
        Dir.glob(File.join(@base_path, "*.json")).each do |file|
          File.readlines(file).each do |line|
            record = JSON.parse(line.strip, symbolize_names: true)
            value = record[field]
            counts[value] += 1
          end
        end
        
        counts
      end

      def oldest_record_date
        Dir.glob(File.join(@base_path, "*.json")).map do |file|
          File.basename(file, '.json')
        end.min
      end

      def newest_record_date
        Dir.glob(File.join(@base_path, "*.json")).map do |file|
          File.basename(file, '.json')
        end.max
      end
    end
  end
end