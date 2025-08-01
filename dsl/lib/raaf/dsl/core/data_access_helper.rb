# frozen_string_literal: true

module RAAF
  module DSL
    # DataAccessHelper provides utilities for safely accessing hash data with mixed key types
    #
    # This module helps handle the common issue of data coming from different sources
    # with inconsistent key types (strings vs symbols). It provides safe access methods
    # that work with both string and symbol keys.
    #
    # @example Include in your class
    #   class MyAgent < RAAF::DSL::Agents::Base
    #     include RAAF::DSL::DataAccessHelper
    #     
    #     def process_data(response)
    #       # Works with both response["results"] and response[:results]
    #       results = safe_get(response, :results)
    #       
    #       # Deep access with mixed keys
    #       company_name = safe_dig(response, :data, :company, :name)
    #     end
    #   end
    #
    # @example Standalone usage
    #   include RAAF::DSL::DataAccessHelper
    #   
    #   data = { "name" => "John", age: 30 }
    #   safe_get(data, :name)  # => "John"
    #   safe_get(data, "age")  # => 30
    #
    module DataAccessHelper
      extend self

      # Safely get a value from a hash using either string or symbol key
      #
      # @param hash [Hash, nil] The hash to access
      # @param key [String, Symbol] The key to look up
      # @param default [Object] Default value if key not found
      # @return [Object] The value or default
      #
      # @example
      #   data = { "name" => "John", age: 30 }
      #   safe_get(data, :name)        # => "John"
      #   safe_get(data, "age")        # => 30
      #   safe_get(data, :missing, "default") # => "default"
      #   safe_get(nil, :key)          # => nil
      #
      def safe_get(hash, key, default = nil)
        return default unless hash.is_a?(Hash)
        
        hash[key.to_s] || hash[key.to_sym] || default
      end

      # Safely dig through nested hashes with mixed key types
      #
      # @param hash [Hash, nil] The hash to dig through
      # @param keys [Array<String, Symbol>] Path of keys to follow
      # @return [Object, nil] The nested value or nil
      #
      # @example
      #   data = { 
      #     "user" => { 
      #       name: "John",
      #       "address" => { city: "NYC" }
      #     }
      #   }
      #   safe_dig(data, :user, :name)           # => "John"
      #   safe_dig(data, "user", "address", :city) # => "NYC"
      #   safe_dig(data, :user, :missing, :key)  # => nil
      #
      def safe_dig(hash, *keys)
        return nil unless hash.is_a?(Hash)
        
        keys.reduce(hash) do |current, key|
          break nil unless current.is_a?(Hash)
          current[key.to_s] || current[key.to_sym]
        end
      end

      # Check if a key exists in hash (as string or symbol)
      #
      # @param hash [Hash, nil] The hash to check
      # @param key [String, Symbol] The key to check for
      # @return [Boolean] True if key exists
      #
      # @example
      #   data = { "name" => "John", age: 30 }
      #   safe_key?(data, :name)  # => true
      #   safe_key?(data, "age")  # => true
      #   safe_key?(data, :missing) # => false
      #
      def safe_key?(hash, key)
        return false unless hash.is_a?(Hash)
        
        hash.key?(key.to_s) || hash.key?(key.to_sym)
      end

      # Get all values for keys that exist (as string or symbol)
      #
      # @param hash [Hash, nil] The hash to access
      # @param keys [Array<String, Symbol>] Keys to fetch
      # @param defaults [Hash] Default values for missing keys
      # @return [Hash] Hash with requested keys and their values
      #
      # @example
      #   data = { "name" => "John", age: 30, "role" => "admin" }
      #   safe_fetch_all(data, [:name, :age, :missing])
      #   # => { name: "John", age: 30, missing: nil }
      #   
      #   safe_fetch_all(data, [:name, :missing], missing: "default")
      #   # => { name: "John", missing: "default" }
      #
      def safe_fetch_all(hash, keys, defaults = {})
        return {} unless hash.is_a?(Hash)
        
        keys.each_with_object({}) do |key, result|
          result[key.to_sym] = safe_get(hash, key, defaults[key.to_sym])
        end
      end

      # Convert all keys in a hash to symbols recursively
      #
      # @param obj [Object] The object to process
      # @return [Object] Object with symbolized keys
      #
      # @example
      #   data = { "name" => "John", "address" => { "city" => "NYC" } }
      #   symbolize_keys_deep(data)
      #   # => { name: "John", address: { city: "NYC" } }
      #
      def symbolize_keys_deep(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), result|
            result[key.to_sym] = symbolize_keys_deep(value)
          end
        when Array
          obj.map { |item| symbolize_keys_deep(item) }
        else
          obj
        end
      end

      # Convert all keys in a hash to strings recursively
      #
      # @param obj [Object] The object to process
      # @return [Object] Object with stringified keys
      #
      # @example
      #   data = { name: "John", address: { city: "NYC" } }
      #   stringify_keys_deep(data)
      #   # => { "name" => "John", "address" => { "city" => "NYC" } }
      #
      def stringify_keys_deep(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), result|
            result[key.to_s] = stringify_keys_deep(value)
          end
        when Array
          obj.map { |item| stringify_keys_deep(item) }
        else
          obj
        end
      end

      # Merge hashes with mixed key types safely
      #
      # @param base [Hash] Base hash
      # @param other [Hash] Hash to merge in
      # @param symbolize [Boolean] Whether to symbolize all keys
      # @return [Hash] Merged hash
      #
      # @example
      #   base = { "name" => "John", age: 30 }
      #   other = { name: "Jane", "role" => "admin" }
      #   safe_merge(base, other)
      #   # => { "name" => "Jane", age: 30, "role" => "admin" }
      #   
      #   safe_merge(base, other, symbolize: true)
      #   # => { name: "Jane", age: 30, role: "admin" }
      #
      def safe_merge(base, other, symbolize: false)
        return base unless other.is_a?(Hash)
        
        if symbolize
          symbolize_keys_deep(base).merge(symbolize_keys_deep(other))
        else
          # Merge while preserving original key types
          result = base.dup
          other.each do |key, value|
            if safe_key?(result, key)
              # Update existing key with same type
              existing_key = result.key?(key.to_s) ? key.to_s : key.to_sym
              result[existing_key] = value
            else
              # Add new key as-is
              result[key] = value
            end
          end
          result
        end
      end

      # Extract subset of hash with consistent key types
      #
      # @param hash [Hash] Source hash
      # @param keys [Array<String, Symbol>] Keys to extract
      # @param symbolize [Boolean] Whether to symbolize result keys
      # @return [Hash] Extracted subset
      #
      # @example
      #   data = { "name" => "John", age: 30, "role" => "admin" }
      #   safe_slice(data, [:name, :age])
      #   # => { "name" => "John", age: 30 }
      #   
      #   safe_slice(data, [:name, :age], symbolize: true)
      #   # => { name: "John", age: 30 }
      #
      def safe_slice(hash, keys, symbolize: false)
        return {} unless hash.is_a?(Hash)
        
        result = {}
        keys.each do |key|
          if hash.key?(key.to_s)
            result_key = symbolize ? key.to_sym : key.to_s
            result[result_key] = hash[key.to_s]
          elsif hash.key?(key.to_sym)
            result_key = symbolize ? key.to_sym : key.to_sym
            result[result_key] = hash[key.to_sym]
          end
        end
        result
      end

      # Transform hash keys using a mapping
      #
      # @param hash [Hash] Source hash
      # @param mapping [Hash] Key transformation mapping
      # @return [Hash] Transformed hash
      #
      # @example
      #   data = { "company_name" => "Acme", "company_size" => 100 }
      #   mapping = { company_name: :name, company_size: :employee_count }
      #   safe_transform_keys(data, mapping)
      #   # => { name: "Acme", employee_count: 100 }
      #
      def safe_transform_keys(hash, mapping)
        return {} unless hash.is_a?(Hash)
        
        result = {}
        mapping.each do |from_key, to_key|
          value = safe_get(hash, from_key)
          result[to_key] = value unless value.nil?
        end
        result
      end
    end
  end
end