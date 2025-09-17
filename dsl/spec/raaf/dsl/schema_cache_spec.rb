# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::SchemaCache do
  let(:market_model) do
    double("Market").tap do |model|
      allow(model).to receive(:name).and_return("Market")
    end
  end

  let(:sample_schema) do
    {
      type: :object,
      properties: {
        id: { type: :integer },
        name: { type: :string }
      },
      required: [:name]
    }
  end

  before do
    # Clear cache before each test
    described_class.instance_variable_set(:@cache, {})
    described_class.instance_variable_set(:@cache_timestamps, {})
  end

  describe ".get_schema" do
    context "on first request" do
      it "generates schema and caches it" do
        expect(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
          .with(market_model)
          .once
          .and_return(sample_schema)

        allow(described_class).to receive(:get_model_timestamp)
          .with(market_model)
          .and_return(Time.current)

        result = described_class.get_schema(market_model)

        expect(result).to eq(sample_schema)

        # Verify it's cached
        cache = described_class.instance_variable_get(:@cache)
        expect(cache["Market"]).to eq(sample_schema)
      end

      it "stores cache timestamp" do
        current_time = Time.current
        allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
          .and_return(sample_schema)
        allow(described_class).to receive(:get_model_timestamp)
          .and_return(current_time)

        described_class.get_schema(market_model)

        timestamps = described_class.instance_variable_get(:@cache_timestamps)
        expect(timestamps["Market"]).to be_within(1.second).of(current_time)
      end
    end

    context "on subsequent requests" do
      let(:model_timestamp) { 1.hour.ago }

      before do
        # Set up initial cache
        allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
          .with(market_model)
          .and_return(sample_schema)
        allow(described_class).to receive(:get_model_timestamp)
          .with(market_model)
          .and_return(model_timestamp)

        # Prime the cache
        described_class.get_schema(market_model)
      end

      context "when model hasn't changed" do
        it "returns cached schema without regenerating" do
          expect(RAAF::DSL::SchemaGenerator).not_to receive(:generate_for_model)

          result = described_class.get_schema(market_model)

          expect(result).to eq(sample_schema)
        end
      end

      context "when model has changed" do
        let(:new_timestamp) { Time.current }
        let(:updated_schema) do
          {
            type: :object,
            properties: {
              id: { type: :integer },
              name: { type: :string },
              email: { type: :string, format: :email }
            },
            required: [:name, :email]
          }
        end

        it "regenerates and updates cache" do
          # Model timestamp is newer than cache timestamp
          allow(described_class).to receive(:get_model_timestamp)
            .with(market_model)
            .and_return(new_timestamp)

          expect(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
            .with(market_model)
            .once
            .and_return(updated_schema)

          result = described_class.get_schema(market_model)

          expect(result).to eq(updated_schema)

          # Verify cache is updated
          cache = described_class.instance_variable_get(:@cache)
          expect(cache["Market"]).to eq(updated_schema)
        end

        it "updates cache timestamp" do
          allow(described_class).to receive(:get_model_timestamp)
            .with(market_model)
            .and_return(new_timestamp)

          allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
            .and_return(updated_schema)

          described_class.get_schema(market_model)

          timestamps = described_class.instance_variable_get(:@cache_timestamps)
          expect(timestamps["Market"]).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "with multiple models" do
      let(:product_model) do
        double("Product").tap do |model|
          allow(model).to receive(:name).and_return("Product")
        end
      end

      let(:product_schema) do
        {
          type: :object,
          properties: {
            id: { type: :integer },
            title: { type: :string }
          },
          required: [:title]
        }
      end

      it "caches schemas independently" do
        allow(described_class).to receive(:get_model_timestamp).and_return(Time.current)

        expect(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
          .with(market_model)
          .and_return(sample_schema)

        expect(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
          .with(product_model)
          .and_return(product_schema)

        market_result = described_class.get_schema(market_model)
        product_result = described_class.get_schema(product_model)

        expect(market_result).to eq(sample_schema)
        expect(product_result).to eq(product_schema)

        # Verify both are cached
        cache = described_class.instance_variable_get(:@cache)
        expect(cache["Market"]).to eq(sample_schema)
        expect(cache["Product"]).to eq(product_schema)
      end
    end

    context "error handling" do
      it "handles cache misses gracefully" do
        allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
          .and_raise(StandardError, "Model introspection failed")

        expect {
          described_class.get_schema(market_model)
        }.to raise_error(StandardError, "Model introspection failed")

        # Cache should remain empty
        cache = described_class.instance_variable_get(:@cache)
        expect(cache).to be_empty
      end
    end
  end

  describe ".get_model_timestamp" do
    context "in development environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      end

      it "returns model file modification time" do
        model_file_path = "/path/to/market.rb"
        file_mtime = 1.hour.ago

        allow(described_class).to receive(:model_class_file)
          .with(market_model)
          .and_return(model_file_path)

        allow(File).to receive(:mtime)
          .with(model_file_path)
          .and_return(file_mtime)

        result = described_class.send(:get_model_timestamp, market_model)

        expect(result).to eq(file_mtime)
      end

      it "handles missing model files gracefully" do
        allow(described_class).to receive(:model_class_file)
          .with(market_model)
          .and_return("/path/to/missing.rb")

        allow(File).to receive(:mtime)
          .and_raise(Errno::ENOENT, "No such file")

        # Should not raise error, fallback to epoch time
        result = described_class.send(:get_model_timestamp, market_model)

        expect(result).to be_a(Time)
      end
    end

    context "in production environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "returns application boot timestamp" do
        boot_timestamp = 1.day.ago
        allow(Rails.application.config).to receive(:cache_classes_timestamp)
          .and_return(boot_timestamp)

        result = described_class.send(:get_model_timestamp, market_model)

        expect(result).to eq(boot_timestamp)
      end

      it "handles missing cache_classes_timestamp gracefully" do
        allow(Rails.application.config).to receive(:cache_classes_timestamp)
          .and_return(nil)

        result = described_class.send(:get_model_timestamp, market_model)

        expect(result).to be_a(Time)
      end
    end
  end

  describe ".model_class_file" do
    it "determines model file path from class name" do
      result = described_class.send(:model_class_file, market_model)

      expect(result).to include("market.rb")
      expect(result).to include("app/models")
    end

    it "handles namespaced models" do
      namespaced_model = double("NamespacedModel").tap do |model|
        allow(model).to receive(:name).and_return("Ai::Market::Analysis")
      end

      result = described_class.send(:model_class_file, namespaced_model)

      expect(result).to include("ai/market/analysis.rb")
    end
  end

  describe "memory management" do
    it "doesn't accumulate excessive memory" do
      initial_cache_size = described_class.instance_variable_get(:@cache).size

      # Generate schemas for many models
      100.times do |i|
        model = double("Model#{i}").tap do |m|
          allow(m).to receive(:name).and_return("Model#{i}")
        end

        allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
          .with(model)
          .and_return({ type: :object, properties: {} })

        allow(described_class).to receive(:get_model_timestamp)
          .with(model)
          .and_return(Time.current)

        described_class.get_schema(model)
      end

      final_cache_size = described_class.instance_variable_get(:@cache).size

      # Should cache all models but not grow excessively in memory
      expect(final_cache_size).to eq(initial_cache_size + 100)

      # Basic memory check - each cached schema should be reasonable size
      cache = described_class.instance_variable_get(:@cache)
      total_size = cache.values.map(&:to_s).sum(&:length)
      expect(total_size).to be < 1_000_000 # Less than 1MB for 100 simple schemas
    end
  end

  describe "thread safety" do
    it "handles concurrent cache access" do
      allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
        .with(market_model)
        .and_return(sample_schema)

      allow(described_class).to receive(:get_model_timestamp)
        .with(market_model)
        .and_return(Time.current)

      # Simulate concurrent access
      threads = 10.times.map do
        Thread.new do
          described_class.get_schema(market_model)
        end
      end

      results = threads.map(&:value)

      # All threads should get the same result
      expect(results).to all(eq(sample_schema))

      # Schema generator should only be called once due to caching
      expect(RAAF::DSL::SchemaGenerator).to have_received(:generate_for_model).once
    end
  end

  describe "performance" do
    context "cache hits" do
      before do
        # Prime the cache
        allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
          .with(market_model)
          .and_return(sample_schema)

        allow(described_class).to receive(:get_model_timestamp)
          .with(market_model)
          .and_return(1.hour.ago)

        described_class.get_schema(market_model)
      end

      it "returns cached schemas very quickly" do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        1000.times do
          described_class.get_schema(market_model)
        end

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        expect(elapsed).to be < 0.001 # Less than 1ms for 1000 cache hits
      end
    end

    context "cache hit rate" do
      it "achieves high cache hit rate in typical usage" do
        models = 10.times.map do |i|
          double("Model#{i}").tap do |model|
            allow(model).to receive(:name).and_return("Model#{i}")
          end
        end

        # Set up schemas for all models
        models.each do |model|
          allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model)
            .with(model)
            .and_return(sample_schema)

          allow(described_class).to receive(:get_model_timestamp)
            .with(model)
            .and_return(1.hour.ago)
        end

        # Simulate typical usage - mostly repeated requests
        generation_count = 0
        allow(RAAF::DSL::SchemaGenerator).to receive(:generate_for_model) do |model|
          generation_count += 1
          sample_schema
        end

        total_requests = 0

        # Mixed access pattern
        100.times do
          model = models.sample # Random model
          described_class.get_schema(model)
          total_requests += 1
        end

        cache_hit_rate = ((total_requests - generation_count).to_f / total_requests) * 100
        expect(cache_hit_rate).to be > 90 # >90% cache hit rate
      end
    end
  end
end