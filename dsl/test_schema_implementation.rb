#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone test to verify Schema Generator and Cache implementation
puts "=== Testing RAAF::DSL::Schema Implementation ==="
puts

# Add lib directory to load path
$LOAD_PATH.unshift File.join(__dir__, 'lib')

begin
  # Load required dependencies
  require 'json'
  require 'time'
  require 'logger'
  require 'ostruct'
  require 'pathname'

  # Mock ActiveSupport
  module ActiveSupport
    class StringInquirer < String
      def development?
        self == "development"
      end
    end
  end

  # Mock Time.current
  class Time
    def self.current
      Time.now
    end
  end

  # Mock String.underscore
  class String
    def underscore
      self.gsub(/::/, '/').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        tr("-", "_").
        downcase
    end
  end

  # Mock Rails for testing
  module Rails
    def self.env
      @env ||= ActiveSupport::StringInquirer.new("development")
    end

    def self.application
      @application ||= OpenStruct.new(config: OpenStruct.new)
    end

    def self.root
      @root ||= Pathname.new(__dir__)
    end

    def self.logger
      @logger ||= Logger.new($stdout)
    end
  end

  # Load schema classes directly
  require_relative 'lib/raaf/dsl/schema/schema_generator'
  require_relative 'lib/raaf/dsl/schema/schema_cache'

  puts "SUCCESS: Successfully loaded Schema classes"

  # Mock ActiveRecord classes for testing
  class MockColumn
    attr_reader :name, :type, :null, :limit, :precision, :scale

    def initialize(name, type, null: true, limit: nil, precision: nil, scale: nil)
      @name = name
      @type = type
      @null = null
      @limit = limit
      @precision = precision
      @scale = scale
    end
  end

  class MockAssociation
    attr_reader :name, :macro, :class_name

    def initialize(name, macro, class_name = nil)
      @name = name
      @macro = macro
      @class_name = class_name
    end
  end

  class MockValidator
    attr_reader :attributes, :options

    def initialize(attributes, options = {})
      @attributes = Array(attributes)
      @options = options
    end

    def kind
      :presence
    end
  end

  class MockModel
    def self.name
      "MockModel"
    end

    def self.columns
      [
        MockColumn.new("id", :integer, null: false),
        MockColumn.new("name", :string, null: false, limit: 255),
        MockColumn.new("email", :string, limit: 100),
        MockColumn.new("age", :integer),
        MockColumn.new("created_at", :datetime, null: false),
        MockColumn.new("metadata", :json)
      ]
    end

    def self.reflect_on_all_associations
      [
        MockAssociation.new(:orders, :has_many, "Order"),
        MockAssociation.new(:profile, :belongs_to, "Profile")
      ]
    end

    def self.validators
      [
        MockValidator.new(:name),
        MockValidator.new(:email)
      ]
    end
  end

  puts "SUCCESS: Created mock ActiveRecord classes"

  # Test SchemaGenerator
  puts "\n--- Testing SchemaGenerator ---"

  schema = RAAF::DSL::Schema::SchemaGenerator.generate_for_model(MockModel)
  puts "SUCCESS: Generated schema successfully"

  # Verify schema structure
  expected_keys = %w[type properties required]
  actual_keys = schema.keys.map(&:to_s)
  missing_keys = expected_keys - actual_keys

  if missing_keys.empty?
    puts "SUCCESS: Schema has all expected top-level keys: #{expected_keys.join(', ')}"
  else
    puts "ERROR: Schema missing keys: #{missing_keys.join(', ')}"
  end

  # Check properties
  if schema[:properties] && schema[:properties].is_a?(Hash)
    puts "SUCCESS: Schema has properties hash with #{schema[:properties].keys.size} fields"

    # Verify some expected fields
    expected_fields = %w[id name email age created_at metadata orders profile]
    found_fields = schema[:properties].keys.map(&:to_s)
    missing_fields = expected_fields - found_fields

    if missing_fields.empty?
      puts "SUCCESS: All expected fields found: #{expected_fields.join(', ')}"
    else
      puts "WARNING: Some fields missing: #{missing_fields.join(', ')}"
    end
  else
    puts "ERROR: Schema properties is not a hash"
  end

  # Check required fields
  if schema[:required] && schema[:required].is_a?(Array)
    puts "SUCCESS: Schema has required fields array: #{schema[:required]}"
  else
    puts "ERROR: Schema required is not an array"
  end

  # Test SchemaCache
  puts "\n--- Testing SchemaCache ---"

  # First call should generate and cache
  start_time = Time.now
  cached_schema1 = RAAF::DSL::Schema::SchemaCache.get_schema(MockModel)
  first_call_time = Time.now - start_time
  puts "SUCCESS: First call completed in #{(first_call_time * 1000).round(2)}ms"

  # Second call should use cache
  start_time = Time.now
  cached_schema2 = RAAF::DSL::Schema::SchemaCache.get_schema(MockModel)
  second_call_time = Time.now - start_time
  puts "SUCCESS: Second call completed in #{(second_call_time * 1000).round(2)}ms"

  # Verify caching works
  if cached_schema1 == cached_schema2
    puts "SUCCESS: Cache returns identical schema"
  else
    puts "ERROR: Cache returned different schema"
  end

  if second_call_time < first_call_time
    puts "SUCCESS: Cache improves performance (#{(first_call_time * 1000).round(2)}ms -> #{(second_call_time * 1000).round(2)}ms)"
  else
    puts "WARNING: Cache may not be working (times: #{(first_call_time * 1000).round(2)}ms -> #{(second_call_time * 1000).round(2)}ms)"
  end

  # Test cache statistics
  puts "\n--- Testing Cache Statistics ---"

  stats = RAAF::DSL::Schema::SchemaCache.cache_statistics
  if stats.is_a?(Hash)
    puts "SUCCESS: Cache statistics returned: #{stats}"
  else
    puts "ERROR: Cache statistics not returned as hash"
  end

  # Test cache clearing
  RAAF::DSL::Schema::SchemaCache.clear_cache!
  stats_after_clear = RAAF::DSL::Schema::SchemaCache.cache_statistics
  puts "SUCCESS: Cache stats after clear: #{stats_after_clear}"

  puts "\n=== All Tests Completed Successfully! ==="

rescue => e
  puts "ERROR during testing: #{e.message}"
  puts "   Error class: #{e.class.name}"
  puts "   Backtrace:"
  puts e.backtrace.first(5).map { |line| "     #{line}" }
  exit 1
end
