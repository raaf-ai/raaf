# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/config"

RSpec.describe RAAF::DSL::IntelligentStreaming::Config do
  describe "#initialize" do
    context "with valid parameters" do
      it "creates a config with stream_size and array_field" do
        config = described_class.new(stream_size: 100, over: :items)

        expect(config.stream_size).to eq(100)
        expect(config.array_field).to eq(:items)
        expect(config.incremental).to be(false)
      end

      it "creates a config with incremental delivery enabled" do
        config = described_class.new(stream_size: 50, incremental: true)

        expect(config.stream_size).to eq(50)
        expect(config.array_field).to be_nil
        expect(config.incremental).to be(true)
      end

      it "defaults incremental to false" do
        config = described_class.new(stream_size: 100)

        expect(config.incremental).to be(false)
      end
    end

    context "with invalid parameters" do
      it "raises ArgumentError for non-integer stream_size" do
        expect {
          described_class.new(stream_size: "100")
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end

      it "raises ArgumentError for zero stream_size" do
        expect {
          described_class.new(stream_size: 0)
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end

      it "raises ArgumentError for negative stream_size" do
        expect {
          described_class.new(stream_size: -10)
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end
    end
  end

  describe "configuration blocks" do
    let(:config) { described_class.new(stream_size: 100, over: :items) }

    describe "#skip_if" do
      it "stores the skip_if block" do
        skip_block = proc { |record| record[:processed] }
        config.skip_if(&skip_block)

        expect(config.blocks[:skip_if]).to eq(skip_block)
      end

      it "does nothing without a block" do
        config.skip_if

        expect(config.blocks[:skip_if]).to be_nil
      end
    end

    describe "#load_existing" do
      it "stores the load_existing block" do
        load_block = proc { |record| { cached: true } }
        config.load_existing(&load_block)

        expect(config.blocks[:load_existing]).to eq(load_block)
      end
    end

    describe "#persist_each_stream" do
      it "stores the persist_each_stream block" do
        persist_block = proc { |results| save_to_db(results) }
        config.persist_each_stream(&persist_block)

        expect(config.blocks[:persist_each_stream]).to eq(persist_block)
      end
    end

    describe "#on_stream_start" do
      it "stores the on_stream_start hook" do
        start_hook = proc { |num, total, data| puts "Starting #{num}/#{total}" }
        config.on_stream_start(&start_hook)

        expect(config.blocks[:on_stream_start]).to eq(start_hook)
      end
    end

    describe "#on_stream_complete" do
      context "with incremental: false" do
        it "accepts a block with 1 parameter" do
          complete_hook = proc { |all_results| puts "Done: #{all_results.size}" }
          expect { config.on_stream_complete(&complete_hook) }.not_to raise_error
          expect(config.blocks[:on_stream_complete]).to eq(complete_hook)
        end

        it "accepts a block with variable parameters (-1 arity)" do
          complete_hook = proc { |*args| puts "Done" }
          expect { config.on_stream_complete(&complete_hook) }.not_to raise_error
        end

        it "raises error for block with wrong arity" do
          complete_hook = proc { |a, b, c| puts "Wrong" }
          expect {
            config.on_stream_complete(&complete_hook)
          }.to raise_error(ArgumentError, /expects 1 parameter/)
        end
      end

      context "with incremental: true" do
        let(:config) { described_class.new(stream_size: 100, incremental: true) }

        it "accepts a block with 3 parameters" do
          complete_hook = proc { |num, total, results| puts "Stream #{num}/#{total}" }
          expect { config.on_stream_complete(&complete_hook) }.not_to raise_error
          expect(config.blocks[:on_stream_complete]).to eq(complete_hook)
        end

        it "accepts a block with variable parameters (-1 arity)" do
          complete_hook = proc { |*args| puts "Done" }
          expect { config.on_stream_complete(&complete_hook) }.not_to raise_error
        end

        it "raises error for block with wrong arity" do
          complete_hook = proc { |a| puts "Wrong" }
          expect {
            config.on_stream_complete(&complete_hook)
          }.to raise_error(ArgumentError, /expects 3 parameters/)
        end
      end
    end

    describe "#on_stream_error" do
      it "stores the on_stream_error hook" do
        error_hook = proc { |num, total, error, context| log_error(error) }
        config.on_stream_error(&error_hook)

        expect(config.blocks[:on_stream_error]).to eq(error_hook)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid configuration" do
      config = described_class.new(stream_size: 100)
      expect(config.valid?).to be(true)
    end

    it "returns true for large stream sizes" do
      config = described_class.new(stream_size: 10_000)
      expect(config.valid?).to be(true)
    end
  end

  describe "#to_h" do
    it "returns configuration as a hash" do
      config = described_class.new(stream_size: 100, over: :companies, incremental: true)
      config.skip_if { |r| r[:done] }
      config.load_existing { |r| cache[r[:id]] }
      config.persist_each_stream { |results| save(results) }

      hash = config.to_h

      expect(hash).to eq({
        stream_size: 100,
        array_field: :companies,
        incremental: true,
        has_skip_if: true,
        has_load_existing: true,
        has_persist: true
      })
    end

    it "shows false for unset blocks" do
      config = described_class.new(stream_size: 50)

      hash = config.to_h

      expect(hash).to eq({
        stream_size: 50,
        array_field: nil,
        incremental: false,
        has_skip_if: false,
        has_load_existing: false,
        has_persist: false
      })
    end
  end
end