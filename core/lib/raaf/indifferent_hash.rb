# frozen_string_literal: true

module RAAF

  ##
  # IndifferentHash - Hash with indifferent string/symbol key access
  #
  # A lightweight hash implementation that allows accessing values using either
  # string or symbol keys interchangeably. This eliminates the pain points of
  # converting between string and symbol keys throughout the RAAF ecosystem.
  #
  # == Key Features
  #
  # - **Indifferent access**: `hash[:key]` and `hash["key"]` return the same value
  # - **String storage**: Keys are stored as strings internally for consistency
  # - **Performance optimized**: No repeated key conversion overhead
  # - **API compatible**: Drop-in replacement for standard Hash in most cases
  # - **Recursive processing**: Automatically converts nested hashes
  #
  # == Memory and Performance
  #
  # - Keys are stored as strings (not duplicated for both string/symbol)
  # - Lookup performance is consistent regardless of access pattern
  # - No runtime key conversion during normal operations
  # - Minimal memory overhead compared to standard Hash
  #
  # @example Basic usage
  #   hash = RAAF::IndifferentHash.new
  #   hash[:name] = "John"
  #   hash["name"]  # => "John"
  #   hash[:name]   # => "John"
  #
  # @example Creation from existing hash
  #   data = {name: "John", age: 30}
  #   hash = RAAF::IndifferentHash.new(data)
  #   hash["name"]  # => "John"
  #   hash[:age]    # => 30
  #
  # @example Nested hash conversion
  #   data = {user: {profile: {name: "John"}}}
  #   hash = RAAF::IndifferentHash.new(data)
  #   hash[:user][:profile][:name]    # => "John"
  #   hash["user"]["profile"]["name"] # => "John"
  #
  # @example API response processing
  #   api_response = {"message" => {"role" => "assistant", "content" => "Hello"}}
  #   response = RAAF::IndifferentHash.new(api_response)
  #   response[:message][:role]     # => "assistant"
  #   response["message"]["role"]   # => "assistant"
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see RAAF::Utils For additional hash utilities
  class IndifferentHash < Hash

    ##
    # Create a new IndifferentHash
    #
    # @param initial_data [Hash, nil] Optional initial data to populate the hash
    # @example Create empty hash
    #   hash = RAAF::IndifferentHash.new
    #
    # @example Create from existing data
    #   hash = RAAF::IndifferentHash.new({name: "John", age: 30})
    def initialize(initial_data = nil)
      super()
      update(initial_data) if initial_data
    end

    ##
    # Get value using either string or symbol key
    #
    # @param key [String, Symbol] The key to look up
    # @return [Object] The value associated with the key
    # @example Indifferent access
    #   hash[:key] == hash["key"]  # => true
    def [](key)
      super(key.to_s)
    end

    ##
    # Set value using either string or symbol key
    #
    # @param key [String, Symbol] The key to set
    # @param value [Object] The value to store
    # @return [Object] The stored value
    # @example Indifferent assignment
    #   hash[:key] = "value"
    #   hash["key"]  # => "value"
    def []=(key, value)
      super(key.to_s, convert_value(value))
    end

    ##
    # Check if key exists (string or symbol)
    #
    # @param key [String, Symbol] The key to check
    # @return [Boolean] True if key exists
    # @example Key existence
    #   hash[:key] = "value"
    #   hash.key?("key")  # => true
    #   hash.key?(:key)   # => true
    def key?(key)
      super(key.to_s)
    end

    alias_method :has_key?, :key?
    alias_method :include?, :key?
    alias_method :member?, :key?

    ##
    # Get value with default if key doesn't exist
    #
    # @param key [String, Symbol] The key to fetch
    # @param default [Object] Default value if key not found
    # @yield Optional block to compute default value
    # @return [Object] The value or default
    # @example Fetch with default
    #   hash.fetch(:missing, "default")  # => "default"
    #   hash.fetch("missing") { "computed" }  # => "computed"
    def fetch(key, *args, &block)
      super(key.to_s, *args, &block)
    end

    ##
    # Delete key (string or symbol)
    #
    # @param key [String, Symbol] The key to delete
    # @return [Object, nil] The deleted value or nil
    # @example Delete key
    #   hash[:key] = "value"
    #   hash.delete("key")  # => "value"
    def delete(key)
      super(key.to_s)
    end

    ##
    # Update hash with another hash, converting keys
    #
    # @param other_hash [Hash] Hash to merge in
    # @return [IndifferentHash] Self for chaining
    # @example Merge data
    #   hash.update({name: "John", age: 30})
    def update(other_hash)
      other_hash.each_pair do |key, value|
        self[key] = value
      end
      self
    end

    alias_method :merge!, :update

    ##
    # Merge with another hash, returning new IndifferentHash
    #
    # @param other_hash [Hash] Hash to merge with
    # @return [IndifferentHash] New hash with merged data
    # @example Non-destructive merge
    #   new_hash = hash.merge({extra: "data"})
    def merge(other_hash)
      dup.update(other_hash)
    end

    ##
    # Create duplicate IndifferentHash
    #
    # @return [IndifferentHash] New hash with same data
    def dup
      self.class.new(self)
    end

    ##
    # Convert values recursively, making nested hashes indifferent
    #
    # @param value [Object] Value to convert
    # @return [Object] Converted value (IndifferentHash for Hash, Array for Array)
    # @example Recursive conversion
    #   hash[:nested] = {deep: {data: "value"}}
    #   hash[:nested][:deep][:data]  # => "value"
    def convert_value(value)
      case value
      when Hash
        # Convert regular hashes to IndifferentHash recursively
        if value.is_a?(self.class)
          value
        else
          self.class.new(value)
        end
      when Array
        # Convert array elements recursively
        value.map { |item| convert_value(item) }
      else
        value
      end
    end

    ##
    # Convert to regular Hash with string keys
    #
    # @return [Hash] Regular hash with string keys
    # @example Convert to regular hash
    #   regular_hash = indifferent_hash.to_hash
    def to_hash
      hash = {}
      each_pair do |key, value|
        hash[key] = case value
                    when IndifferentHash then value.to_hash
                    when Array then value.map { |item| item.is_a?(IndifferentHash) ? item.to_hash : item }
                    else value
                    end
      end
      hash
    end

    ##
    # Convert to Hash preserving indifferent access
    #
    # @return [IndifferentHash] Self
    def to_h
      self
    end

    ##
    # String representation showing indifferent access capability
    #
    # @return [String] Hash representation with class name
    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} #{super}>"
    end

    ##
    # Pretty print for debugging
    #
    # @return [String] Formatted representation
    def pretty_print(pp)
      pp.text(inspect)
    end

    private

    ##
    # Ensure all keys are strings when setting default value
    #
    # @param key [String, Symbol] The key for default value
    # @return [Object] The default value
    def convert_key(key)
      key.to_s
    end

  end

end