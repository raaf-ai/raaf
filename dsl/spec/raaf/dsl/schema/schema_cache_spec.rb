# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Schema::SchemaCache do
  let(:test_model_class) do
    Class.new do
      def self.name
        "TestModel"
      end

      def self.columns
        [
          double(:column, name: "id", type: :integer, null: false, limit: nil),
          double(:column, name: "name", type: :string, null: false, limit: 255)
        ]
      end

      def self.reflect_on_all_associations
        []
      end

      def self.validators
        []
      end
    end
  end

  let(:expected_schema) do
    {
      type: :object,
      properties: {
        id: { type: :integer },
        name: { type: :string, maxLength: 255 }
      },
      required: [:name]
    }
  end

  before do
    # Clear cache before each test
    described_class.clear_cache!

    # Mock Rails for schema cache tests
    unless defined?(Rails)
      rails_double = double('Rails')
      stub_const('Rails', rails_double)
    end

    # Mock Rails.logger
    logger_double = double('Logger')
    allow(logger_double).to receive(:debug)
    allow(Rails).to receive(:logger).and_return(logger_double)

    # Mock Rails.root
    root_double = double('Pathname')
    allow(root_double).to receive(:join).and_return(root_double)
    allow(Rails).to receive(:root).and_return(root_double)

    # Mock Rails.env
    env_double = double('Env')
    allow(env_double).to receive(:development?).and_return(false)
    allow(Rails).to receive(:env).and_return(env_double)

    # Mock Rails.application for production environment tests
    app_double = double('Application')
    config_double = double('Config')
    allow(config_double).to receive(:respond_to?).with(:cache_classes_timestamp).and_return(true)
    allow(config_double).to receive(:cache_classes_timestamp).and_return(Time.current)
    allow(app_double).to receive(:config).and_return(config_double)
    allow(Rails).to receive(:application).and_return(app_double)
  end

  describe ".get_schema" do
    it "generates schema on first request" do
      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_return(expected_schema)

      result = described_class.get_schema(test_model_class)

      expect(result).to eq(expected_schema)
      expect(RAAF::DSL::Schema::SchemaGenerator).to have_received(:generate_for_model).once
    end

    it "returns cached schema on subsequent requests" do
      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_return(expected_schema)

      # First request
      described_class.get_schema(test_model_class)

      # Second request
      result = described_class.get_schema(test_model_class)

      expect(result).to eq(expected_schema)
      expect(RAAF::DSL::Schema::SchemaGenerator).to have_received(:generate_for_model).once
    end

    it "caches schemas for different models separately" do
      second_model_class = Class.new do
        def self.name
          "SecondModel"
        end

        def self.columns
          []
        end

        def self.reflect_on_all_associations
          []
        end

        def self.validators
          []
        end
      end

      second_schema = { type: :object, properties: {}, required: [] }

      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_return(expected_schema)

      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(second_model_class)
        .and_return(second_schema)

      result1 = described_class.get_schema(test_model_class)
      result2 = described_class.get_schema(second_model_class)

      expect(result1).to eq(expected_schema)
      expect(result2).to eq(second_schema)
      expect(RAAF::DSL::Schema::SchemaGenerator).to have_received(:generate_for_model).twice
    end
  end

  describe "cache invalidation" do
    context "in development environment" do
      before do
        env_double = double('Env')
        allow(env_double).to receive(:development?).and_return(true)
        allow(Rails).to receive(:env).and_return(env_double)
        allow(described_class).to receive(:model_class_file).and_return("/path/to/model.rb")
      end

      it "invalidates cache when model file timestamp changes" do
        old_time = Time.current - 1.hour
        new_time = Time.current + 1.hour  # Make sure new_time is significantly newer

        # Set up the File.mtime mock to return old_time first, then new_time
        call_count = 0
        allow(File).to receive(:mtime).with("/path/to/model.rb") do
          call_count += 1
          call_count <= 1 ? old_time : new_time
        end

        allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
          .with(test_model_class)
          .and_return(expected_schema)

        # First request - cache miss, should store with Time.current (which is between old_time and new_time)
        described_class.get_schema(test_model_class)

        # Second request - File.mtime now returns new_time (future), should invalidate cache
        described_class.get_schema(test_model_class)

        expect(RAAF::DSL::Schema::SchemaGenerator).to have_received(:generate_for_model).twice
      end

      it "uses cache when model file timestamp hasn't changed" do
        file_time = Time.current

        allow(File).to receive(:mtime).with("/path/to/model.rb").and_return(file_time)
        allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
          .with(test_model_class)
          .and_return(expected_schema)

        # Two requests with same timestamp
        described_class.get_schema(test_model_class)
        described_class.get_schema(test_model_class)

        expect(RAAF::DSL::Schema::SchemaGenerator).to have_received(:generate_for_model).once
      end
    end

    context "in production environment" do
      before do
        env_double = double('Env')
        allow(env_double).to receive(:development?).and_return(false)
        allow(Rails).to receive(:env).and_return(env_double)

        app_double = double('Application')
        config_double = double('Config')
        allow(config_double).to receive(:cache_classes_timestamp).and_return(Time.current)
        allow(app_double).to receive(:config).and_return(config_double)
        allow(Rails).to receive(:application).and_return(app_double)
      end

      it "uses application boot time for cache validation" do
        allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
          .with(test_model_class)
          .and_return(expected_schema)

        # Multiple requests should use cache
        described_class.get_schema(test_model_class)
        described_class.get_schema(test_model_class)

        expect(RAAF::DSL::Schema::SchemaGenerator).to have_received(:generate_for_model).once
      end
    end
  end

  describe "thread safety" do
    it "handles concurrent access safely" do
      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_return(expected_schema)

      threads = 10.times.map do
        Thread.new do
          described_class.get_schema(test_model_class)
        end
      end

      results = threads.map(&:value)

      # All threads should get the same result
      expect(results).to all(eq(expected_schema))

      # Schema should only be generated once despite concurrent access
      expect(RAAF::DSL::Schema::SchemaGenerator).to have_received(:generate_for_model).once
    end
  end

  describe ".clear_cache!" do
    it "clears all cached schemas" do
      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_return(expected_schema)

      # Generate and cache schema
      described_class.get_schema(test_model_class)

      # Clear cache
      described_class.clear_cache!

      # Request again - should regenerate
      described_class.get_schema(test_model_class)

      expect(RAAF::DSL::Schema::SchemaGenerator).to have_received(:generate_for_model).twice
    end
  end

  describe ".cache_statistics" do
    it "tracks cache hits and misses" do
      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_return(expected_schema)

      # First request - cache miss
      described_class.get_schema(test_model_class)

      # Second request - cache hit
      described_class.get_schema(test_model_class)

      stats = described_class.cache_statistics

      expect(stats[:hits]).to eq(1)
      expect(stats[:misses]).to eq(1)
      expect(stats[:hit_rate]).to be_within(0.01).of(0.5)
    end

    it "calculates hit rate correctly with no requests" do
      stats = described_class.cache_statistics

      expect(stats[:hits]).to eq(0)
      expect(stats[:misses]).to eq(0)
      expect(stats[:hit_rate]).to eq(0.0)
    end
  end

  describe "memory management" do
    it "keeps memory usage within reasonable bounds" do
      # Generate schemas for multiple models
      10.times do |i|
        model_class = Class.new do
          define_singleton_method(:name) { "TestModel#{i}" }
          define_singleton_method(:columns) { [] }
          define_singleton_method(:reflect_on_all_associations) { [] }
          define_singleton_method(:validators) { [] }
        end

        allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
          .with(model_class)
          .and_return({ type: :object, properties: {}, required: [] })

        described_class.get_schema(model_class)
      end

      stats = described_class.cache_statistics

      # Cache should contain schemas for all models
      expect(stats[:cached_models]).to eq(10)

      # Memory usage should be reasonable (less than 1MB for 10 simple schemas)
      expect(stats[:estimated_memory_kb]).to be < 1024
    end
  end

  describe "error handling" do
    it "handles schema generation errors gracefully" do
      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_raise(StandardError, "Schema generation failed")

      expect {
        described_class.get_schema(test_model_class)
      }.to raise_error(StandardError, "Schema generation failed")

      # Error should not corrupt cache state
      stats = described_class.cache_statistics
      expect(stats[:errors]).to eq(1)
    end

    it "handles missing model class gracefully" do
      expect {
        described_class.get_schema(nil)
      }.to raise_error(ArgumentError, "Model class cannot be nil")
    end

    it "handles file system errors in development" do
      env_double = double('Env')
      allow(env_double).to receive(:development?).and_return(true)
      allow(Rails).to receive(:env).and_return(env_double)
      allow(described_class).to receive(:model_class_file).and_raise(StandardError, "File system error")
      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_return(expected_schema)

      # Should fallback to always regenerating on file system errors
      result = described_class.get_schema(test_model_class)
      expect(result).to eq(expected_schema)
    end
  end

  describe "performance" do
    it "cache lookup completes in under 1ms" do
      allow(RAAF::DSL::Schema::SchemaGenerator).to receive(:generate_for_model)
        .with(test_model_class)
        .and_return(expected_schema)

      # Prime the cache
      described_class.get_schema(test_model_class)

      # Measure cache lookup time
      start_time = Time.current
      100.times { described_class.get_schema(test_model_class) }
      elapsed = (Time.current - start_time) * 1000 # Convert to ms

      expect(elapsed).to be < 100 # 100 lookups in under 100ms = <1ms per lookup
    end
  end
end