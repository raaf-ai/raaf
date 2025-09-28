# frozen_string_literal: true

require 'ostruct'

module RAAF
  module DSL
    # ObjectSerializer provides intelligent serialization for different Ruby object types
    #
    # This module handles serialization of various object types including ActiveRecord
    # models, POROs, Structs, OpenStructs, and other Ruby objects. It provides
    # configurable serialization with depth control and circular reference detection.
    #
    module ObjectSerializer
      # Default maximum serialization depth to prevent infinite recursion
      DEFAULT_MAX_DEPTH = 5

      # Build primitive types list
      primitive_list = [
        NilClass, TrueClass, FalseClass,
        Integer, Float,
        String, Symbol,
        Date, DateTime, Time
      ]
      
      # Add BigDecimal if available (it's in stdlib but not always loaded)
      begin
        require 'bigdecimal'
        primitive_list << BigDecimal
      rescue LoadError
        # BigDecimal not available
      end
      
      # Types that should be returned as-is without serialization
      PRIMITIVE_TYPES = primitive_list.freeze

      class << self
        # Serialize any Ruby object based on its type
        #
        # @param object [Object] The object to serialize
        # @param options [Hash] Serialization options
        # @option options [Array<Symbol>] :only Whitelist of attributes to include
        # @option options [Array<Symbol>] :except Blacklist of attributes to exclude
        # @option options [Array<Symbol>] :methods Additional methods to call and include
        # @option options [Integer] :depth Current serialization depth
        # @option options [Integer] :max_depth Maximum serialization depth (default: 2)
        # @option options [Set] :seen Objects already serialized (for circular reference detection)
        #
        # @return [Object] Serialized representation of the object
        #
        def serialize(object, options = {})
          options = normalize_options(options)
          
          # Check for circular references
          seen = options[:seen] ||= Set.new
          return handle_circular_reference(object) if seen.include?(object.object_id)
          
          # Check depth limit
          return handle_depth_limit(object) if options[:depth] >= options[:max_depth]
          
          # Mark object as seen
          seen << object.object_id if trackable?(object)
          
          begin
            case object
            when nil, true, false, Numeric, String, Symbol, Date, DateTime, Time
              object
            when Hash
              serialize_hash(object, options)
            when Array
              serialize_array(object, options)
            when ->(obj) { active_record?(obj) }
              serialize_active_record(object, options)
            when Struct
              serialize_struct(object, options)
            when OpenStruct
              serialize_open_struct(object, options)
            else
              serialize_generic_object(object, options)
            end
          ensure
            # Remove from seen set after serialization
            seen.delete(object.object_id) if trackable?(object)
          end
        end

        private

        # Normalize and set default options
        def normalize_options(options)
          options = options.dup
          options[:max_depth] ||= DEFAULT_MAX_DEPTH
          options[:depth] ||= 0
          options
        end

        # Check if object should be tracked for circular references
        def trackable?(object)
          !PRIMITIVE_TYPES.any? { |type| object.is_a?(type) }
        end

        # Check if object is an ActiveRecord model
        def active_record?(object)
          defined?(ActiveRecord::Base) && object.is_a?(ActiveRecord::Base)
        end

        # Handle circular reference detection
        def handle_circular_reference(object)
          { 
            "__circular_reference__" => true,
            "class" => object.class.name,
            "object_id" => object.object_id.to_s
          }
        end

        # Handle depth limit reached
        def handle_depth_limit(object)
          case object
          when Hash, Array
            object.class.new # Empty collection
          when String
            object.to_s
          else
            { 
              "__depth_limit__" => true,
              "class" => object.class.name,
              "to_s" => safe_to_s(object)
            }
          end
        end

        # Safely call to_s on an object
        def safe_to_s(object)
          object.to_s
        rescue => e
          "#<#{object.class.name}:#{object.object_id}>"
        end

        # Serialize a Hash
        def serialize_hash(hash, options)
          next_options = options.merge(depth: options[:depth] + 1)
          
          hash.each_with_object({}) do |(key, value), result|
            serialized_key = serialize(key, next_options)
            serialized_value = serialize(value, next_options)
            result[serialized_key] = serialized_value
          end
        end

        # Serialize an Array
        def serialize_array(array, options)
          next_options = options.merge(depth: options[:depth] + 1)
          array.map { |item| serialize(item, next_options) }
        end

        # Serialize an ActiveRecord model
        def serialize_active_record(model, options)
          return nil unless model
          
          # Start with basic attributes
          attributes = model.attributes.dup
          
          # Apply only/except filters
          attributes = filter_attributes(attributes, options)
          
          # Add methods if requested
          if options[:methods]
            options[:methods].each do |method|
              if model.respond_to?(method)
                attributes[method.to_s] = model.send(method)
              end
            end
          end
          
          # Serialize nested values
          next_options = options.merge(depth: options[:depth] + 1)
          attributes.each do |key, value|
            attributes[key] = serialize(value, next_options)
          end
          
          # Add metadata
          attributes["__class__"] = model.class.name
          attributes["__id__"] = model.id if model.respond_to?(:id)
          
          attributes
        end

        # Serialize a Struct
        def serialize_struct(struct, options)
          next_options = options.merge(depth: options[:depth] + 1)
          
          result = {
            "__class__" => struct.class.name
          }
          
          struct.members.each do |member|
            if attribute_allowed?(member, options)
              result[member.to_s] = serialize(struct[member], next_options)
            end
          end
          
          result
        end

        # Serialize an OpenStruct
        def serialize_open_struct(ostruct, options)
          next_options = options.merge(depth: options[:depth] + 1)
          
          attributes = ostruct.to_h
          attributes = filter_attributes(attributes, options)
          
          result = attributes.each_with_object({}) do |(key, value), hash|
            hash[key.to_s] = serialize(value, next_options)
          end
          
          result["__class__"] = "OpenStruct"
          result
        end

        # Serialize a generic Ruby object
        def serialize_generic_object(object, options)
          next_options = options.merge(depth: options[:depth] + 1)
          
          result = {
            "__class__" => object.class.name
          }
          
          # Get public methods that look like attributes
          attribute_methods = find_attribute_methods(object)
          
          # Apply filters
          attribute_methods = filter_methods(attribute_methods, options)
          
          # Include methods if specified
          if options[:methods]
            attribute_methods += options[:methods].map(&:to_sym)
            attribute_methods.uniq!
          end
          
          # Serialize each attribute
          attribute_methods.each do |method|
            if object.respond_to?(method) && object.method(method).arity == 0
              begin
                value = object.send(method)
                result[method.to_s] = serialize(value, next_options)
              rescue => e
                # Skip methods that raise errors
                result[method.to_s] = "[Error: #{e.class.name}]"
              end
            end
          end
          
          result
        end

        # Find methods that look like attribute accessors
        def find_attribute_methods(object)
          # Get all public methods
          methods = object.public_methods(false)
          
          # Filter to methods that:
          # - Don't have parameters
          # - Don't end with = or ! or ?
          # - Don't start with _
          # - Aren't common object methods
          
          excluded_methods = [:to_s, :to_h, :to_a, :inspect, :class, :hash, 
                            :object_id, :nil?, :empty?, :blank?, :present?,
                            :eql?, :equal?, :frozen?, :tainted?, :untrusted?]
          
          methods.select do |method|
            method_name = method.to_s
            !method_name.match?(/[=!?]$/) &&
              !method_name.start_with?('_') &&
              !excluded_methods.include?(method) &&
              object.method(method).arity == 0
          end
        end

        # Filter attributes based on only/except options
        def filter_attributes(attributes, options)
          attributes = attributes.symbolize_keys if attributes.respond_to?(:symbolize_keys)
          
          if options[:only]
            only_keys = options[:only].map(&:to_sym)
            attributes.select { |key, _| only_keys.include?(key.to_sym) }
          elsif options[:except]
            except_keys = options[:except].map(&:to_sym)
            attributes.reject { |key, _| except_keys.include?(key.to_sym) }
          else
            attributes
          end
        end

        # Filter methods based on only/except options
        def filter_methods(methods, options)
          if options[:only]
            methods & options[:only].map(&:to_sym)
          elsif options[:except]
            methods - options[:except].map(&:to_sym)
          else
            methods
          end
        end

        # Check if an attribute is allowed
        def attribute_allowed?(attribute, options)
          attr_sym = attribute.to_sym
          
          if options[:only]
            options[:only].include?(attr_sym)
          elsif options[:except]
            !options[:except].include?(attr_sym)
          else
            true
          end
        end
      end
    end
  end
end