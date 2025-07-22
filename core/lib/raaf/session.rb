# frozen_string_literal: true

require_relative "logging"

module RAAF

  ##
  # Session management for agent conversations
  #
  # This module provides session functionality similar to the Python SDK's
  # session system, allowing for persistent conversation state across multiple
  # agent runs. Sessions store conversation history and metadata.
  #
  # @example Basic session usage
  #   session = RAAF::Session.new
  #   session.add_message(role: "user", content: "Hello!")
  #   session.add_message(role: "assistant", content: "Hi there!")
  #
  #   # Access conversation history
  #   puts session.messages
  #
  # @example Session with metadata
  #   session = RAAF::Session.new(
  #     metadata: { user_id: "123", session_type: "support" }
  #   )
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  #
  class Session

    include Logger

    attr_reader :id, :messages, :metadata, :created_at, :updated_at

    ##
    # Initialize a new session
    #
    # @param id [String, nil] unique session identifier (auto-generated if nil)
    # @param messages [Array<Hash>] initial conversation messages
    # @param metadata [Hash] session metadata
    #
    def initialize(id: nil, messages: [], metadata: {})
      @id = id || SecureRandom.uuid
      @messages = messages.dup
      @metadata = metadata.dup
      @created_at = Time.now
      @updated_at = Time.now

      log_debug("Session created", session_id: @id)
    end

    ##
    # Add a message to the session
    #
    # @param role [String] message role ("user", "assistant", "system", "tool")
    # @param content [String] message content
    # @param tool_call_id [String, nil] tool call ID for tool messages
    # @param tool_calls [Array<Hash>, nil] tool calls for assistant messages
    # @param metadata [Hash] message metadata
    # @return [Hash] the added message
    #
    def add_message(role:, content:, tool_call_id: nil, tool_calls: nil, metadata: {})
      message = {
        role: role,
        content: content,
        timestamp: Time.now.to_f,
        metadata: metadata
      }

      message[:tool_call_id] = tool_call_id if tool_call_id
      message[:tool_calls] = tool_calls if tool_calls

      @messages << message
      @updated_at = Time.now

      log_debug("Message added to session", session_id: @id, role: role, content_length: content.length)
      message
    end

    ##
    # Get messages filtered by role
    #
    # @param role [String] role to filter by
    # @return [Array<Hash>] messages with the specified role
    #
    def messages_by_role(role)
      @messages.select { |msg| msg[:role] == role }
    end

    ##
    # Get the last message
    #
    # @return [Hash, nil] the last message or nil if no messages
    #
    def last_message
      @messages.last
    end

    ##
    # Get the last message with a specific role
    #
    # @param role [String] role to find
    # @return [Hash, nil] the last message with the specified role
    #
    def last_message_by_role(role)
      @messages.reverse.find { |msg| msg[:role] == role }
    end

    ##
    # Clear all messages
    #
    # @return [void]
    #
    def clear_messages
      @messages.clear
      @updated_at = Time.now
      log_debug("Session messages cleared", session_id: @id)
    end

    ##
    # Get message count
    #
    # @return [Integer] number of messages in the session
    #
    def message_count
      @messages.size
    end

    ##
    # Check if session is empty
    #
    # @return [Boolean] true if no messages
    #
    def empty?
      @messages.empty?
    end

    ##
    # Update session metadata
    #
    # @param new_metadata [Hash] metadata to merge
    # @return [void]
    #
    def update_metadata(new_metadata)
      @metadata.merge!(new_metadata)
      @updated_at = Time.now
      log_debug("Session metadata updated", session_id: @id)
    end

    ##
    # Get session summary
    #
    # @return [Hash] session summary information
    #
    def summary
      {
        id: @id,
        message_count: message_count,
        created_at: @created_at,
        updated_at: @updated_at,
        metadata: @metadata,
        roles: @messages.map { |msg| msg[:role] }.uniq
      }
    end

    ##
    # Convert to hash for serialization
    #
    # @return [Hash] session data as hash
    #
    def to_h
      {
        id: @id,
        messages: @messages,
        metadata: @metadata,
        created_at: @created_at,
        updated_at: @updated_at
      }
    end

    ##
    # Convert to JSON string
    #
    # @return [String] session data as JSON
    #
    def to_json(*)
      to_h.to_json(*)
    end

    ##
    # Create session from hash
    #
    # @param hash [Hash] session data hash
    # @return [Session] new session instance
    #
    def self.from_hash(hash)
      new(
        id: hash[:id] || hash["id"],
        messages: hash[:messages] || hash["messages"] || [],
        metadata: hash[:metadata] || hash["metadata"] || {}
      ).tap do |session|
        session.instance_variable_set(:@created_at, hash[:created_at] || hash["created_at"] || Time.now)
        session.instance_variable_set(:@updated_at, hash[:updated_at] || hash["updated_at"] || Time.now)
      end
    end

    ##
    # Create session from JSON string
    #
    # @param json [String] session data as JSON
    # @return [Session] new session instance
    #
    def self.from_json(json)
      require "json"
      hash = JSON.parse(json, symbolize_names: true)
      from_hash(hash)
    end

    ##
    # String representation
    #
    # @return [String] string representation
    #
    def to_s
      "#<#{self.class.name} id=#{@id} messages=#{message_count} updated=#{@updated_at}>"
    end

    ##
    # Inspect representation
    #
    # @return [String] inspect representation
    #
    def inspect
      to_s
    end

  end

  ##
  # In-memory session store
  #
  # Provides session storage and retrieval functionality using in-memory storage.
  # This is the default session store when no other store is configured.
  #
  # @example Basic usage
  #   store = RAAF::InMemorySessionStore.new
  #   session = RAAF::Session.new
  #   store.store(session)
  #   retrieved = store.retrieve(session.id)
  #
  class InMemorySessionStore

    include Logger

    ##
    # Initialize the store
    #
    def initialize
      @sessions = {}
      @mutex = Mutex.new
      log_debug("InMemorySessionStore initialized")
    end

    ##
    # Store a session
    #
    # @param session [Session] session to store
    # @return [void]
    #
    def store(session)
      @mutex.synchronize do
        @sessions[session.id] = session
        log_debug("Session stored", session_id: session.id)
      end
    end

    ##
    # Retrieve a session by ID
    #
    # @param session_id [String] session ID
    # @return [Session, nil] session or nil if not found
    #
    def retrieve(session_id)
      @mutex.synchronize do
        session = @sessions[session_id]
        log_debug("Session retrieved", session_id: session_id, found: !session.nil?)
        session
      end
    end

    ##
    # Delete a session
    #
    # @param session_id [String] session ID
    # @return [Session, nil] deleted session or nil if not found
    #
    def delete(session_id)
      @mutex.synchronize do
        session = @sessions.delete(session_id)
        log_debug("Session deleted", session_id: session_id, found: !session.nil?)
        session
      end
    end

    ##
    # Check if session exists
    #
    # @param session_id [String] session ID
    # @return [Boolean] true if session exists
    #
    def exists?(session_id)
      @mutex.synchronize do
        @sessions.key?(session_id)
      end
    end

    ##
    # List all session IDs
    #
    # @return [Array<String>] array of session IDs
    #
    def list_sessions
      @mutex.synchronize do
        @sessions.keys
      end
    end

    ##
    # Clear all sessions
    #
    # @return [void]
    #
    def clear
      @mutex.synchronize do
        count = @sessions.size
        @sessions.clear
        log_debug("All sessions cleared", count: count)
      end
    end

    ##
    # Get session count
    #
    # @return [Integer] number of stored sessions
    #
    def count
      @mutex.synchronize do
        @sessions.size
      end
    end

    ##
    # Get store statistics
    #
    # @return [Hash] store statistics
    #
    def stats
      @mutex.synchronize do
        {
          total_sessions: @sessions.size,
          session_ids: @sessions.keys,
          total_messages: @sessions.values.sum(&:message_count)
        }
      end
    end

  end

  ##
  # File-based session store
  #
  # Provides session storage and retrieval functionality using file system storage.
  # Sessions are stored as JSON files in a specified directory.
  #
  # @example Basic usage
  #   store = RAAF::FileSessionStore.new(directory: "/tmp/sessions")
  #   session = RAAF::Session.new
  #   store.store(session)
  #   retrieved = store.retrieve(session.id)
  #
  class FileSessionStore

    include Logger

    attr_reader :directory

    ##
    # Initialize the store
    #
    # @param directory [String] directory to store session files
    #
    def initialize(directory: "./sessions")
      @directory = File.expand_path(directory)
      @mutex = Mutex.new

      # Create directory if it doesn't exist
      FileUtils.mkdir_p(@directory)

      log_debug("FileSessionStore initialized", directory: @directory)
    end

    ##
    # Store a session
    #
    # @param session [Session] session to store
    # @return [void]
    #
    def store(session)
      @mutex.synchronize do
        filename = session_filename(session.id)
        File.write(filename, session.to_json)
        log_debug("Session stored to file", session_id: session.id, filename: filename)
      end
    end

    ##
    # Retrieve a session by ID
    #
    # @param session_id [String] session ID
    # @return [Session, nil] session or nil if not found
    #
    def retrieve(session_id)
      @mutex.synchronize do
        filename = session_filename(session_id)

        if File.exist?(filename)
          json_data = File.read(filename)
          session = Session.from_json(json_data)
          log_debug("Session retrieved from file", session_id: session_id, filename: filename)
          session
        else
          log_debug("Session not found", session_id: session_id, filename: filename)
          nil
        end
      end
    rescue StandardError => e
      log_error("Error retrieving session", session_id: session_id, error: e.message)
      nil
    end

    ##
    # Delete a session
    #
    # @param session_id [String] session ID
    # @return [Session, nil] deleted session or nil if not found
    #
    def delete(session_id)
      @mutex.synchronize do
        filename = session_filename(session_id)

        if File.exist?(filename)
          # Read session before deleting
          json_data = File.read(filename)
          session = Session.from_json(json_data)

          # Delete the file
          File.delete(filename)
          log_debug("Session deleted from file", session_id: session_id, filename: filename)
          session
        else
          log_debug("Session not found for deletion", session_id: session_id, filename: filename)
          nil
        end
      end
    rescue StandardError => e
      log_error("Error deleting session", session_id: session_id, error: e.message)
      nil
    end

    ##
    # Check if session exists
    #
    # @param session_id [String] session ID
    # @return [Boolean] true if session exists
    #
    def exists?(session_id)
      filename = session_filename(session_id)
      File.exist?(filename)
    end

    ##
    # List all session IDs
    #
    # @return [Array<String>] array of session IDs
    #
    def list_sessions
      Dir.glob(File.join(@directory, "*.json")).map do |filename|
        File.basename(filename, ".json")
      end
    end

    ##
    # Clear all sessions
    #
    # @return [void]
    #
    def clear
      @mutex.synchronize do
        files = Dir.glob(File.join(@directory, "*.json"))
        files.each { |file| File.delete(file) }
        log_debug("All sessions cleared", count: files.size)
      end
    end

    ##
    # Get session count
    #
    # @return [Integer] number of stored sessions
    #
    def count
      Dir.glob(File.join(@directory, "*.json")).size
    end

    ##
    # Get store statistics
    #
    # @return [Hash] store statistics
    #
    def stats
      session_ids = list_sessions
      total_messages = 0

      session_ids.each do |session_id|
        session = retrieve(session_id)
        total_messages += session.message_count if session
      end

      {
        total_sessions: session_ids.size,
        session_ids: session_ids,
        total_messages: total_messages,
        directory: @directory
      }
    end

    private

    ##
    # Get filename for session ID
    #
    # @param session_id [String] session ID
    # @return [String] full path to session file
    #
    def session_filename(session_id)
      File.join(@directory, "#{session_id}.json")
    end

  end

end
