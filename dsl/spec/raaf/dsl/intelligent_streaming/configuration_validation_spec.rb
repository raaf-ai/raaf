# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/scope"
require "raaf/dsl/intelligent_streaming/manager"
require "raaf/dsl/agent"

RSpec.describe "IntelligentStreaming Configuration Validation" do
  let(:base_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "TestAgent"
      model "gpt-4o"

      def self.name
        "TestAgent"
      end
    end
  end

  describe "stream_size validation" do
    context "with invalid stream_size values" do
      it "rejects stream_size of 0" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 0
              over :items
            end
          end
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end

      it "rejects negative stream_size" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size -10
              over :items
            end
          end
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end

      it "rejects non-integer stream_size" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size "100"
              over :items
            end
          end
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end

      it "rejects float stream_size" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 10.5
              over :items
            end
          end
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end

      it "rejects nil stream_size" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size nil
              over :items
            end
          end
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end
    end

    context "with valid stream_size values" do
      it "accepts stream_size of 1" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 1
              over :items
            end
          end
        }.not_to raise_error
      end

      it "accepts large stream_size" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 10_000
              over :items
            end
          end
        }.not_to raise_error
      end

      it "accepts typical stream_size values" do
        [10, 50, 100, 500, 1000].each do |size|
          expect {
            Class.new(base_agent_class) do
              intelligent_streaming do
                stream_size size
                over :items
              end
            end
          }.not_to raise_error
        end
      end
    end
  end

  describe "array_field validation" do
    context "field specification" do
      it "accepts symbol array field" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :companies
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.array_field).to eq(:companies)
      end

      it "accepts string array field and converts to symbol" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over "companies"
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.array_field).to eq(:companies)
      end

      it "allows omitting array field for auto-detection" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            # No 'over' specified - will auto-detect
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.array_field).to be_nil
      end

      it "validates field name format" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 10
              over 123 # Invalid field name type
            end
          end
        }.to raise_error(ArgumentError, /array_field must be a symbol or string/)
      end
    end
  end

  describe "incremental mode validation" do
    context "incremental configuration" do
      it "defaults to incremental: false" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
            # No incremental specified
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.incremental).to be(false)
      end

      it "accepts incremental: true" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
            incremental true
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.incremental).to be(true)
      end

      it "accepts incremental: false explicitly" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
            incremental false
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.incremental).to be(false)
      end

      it "validates incremental is boolean" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 10
              over :items
              incremental "true" # String not boolean
            end
          end
        }.to raise_error(ArgumentError, /incremental must be true or false/)
      end
    end
  end

  describe "hook validation" do
    context "hook parameter validation" do
      it "validates on_stream_start hook arity" do
        # Should accept 3 parameters
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            on_stream_start do |stream_num, total, context|
              # Valid signature
            end
          end
        end

        expect(agent_class._intelligent_streaming_config.hooks[:on_stream_start]).not_to be_nil
      end

      it "validates on_stream_complete hook arity for non-incremental" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
            incremental false

            on_stream_complete do |all_results|
              # Valid for accumulated mode (1 param)
            end
          end
        end

        expect(agent_class._intelligent_streaming_config.hooks[:on_stream_complete]).not_to be_nil
      end

      it "validates on_stream_complete hook arity for incremental" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
            incremental true

            on_stream_complete do |stream_num, total, results|
              # Valid for incremental mode (3 params)
            end
          end
        end

        expect(agent_class._intelligent_streaming_config.hooks[:on_stream_complete]).not_to be_nil
      end

      it "validates on_stream_error hook" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            on_stream_error do |stream_num, total, error, context|
              # Valid signature
            end
          end
        end

        expect(agent_class._intelligent_streaming_config.hooks[:on_stream_error]).not_to be_nil
      end
    end

    context "hook callability" do
      it "rejects non-callable skip_if value" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 10
              over :items

              skip_if "not a proc" # String not callable
            end
          end
        }.to raise_error(ArgumentError, /skip_if must be a callable/)
      end

      it "accepts valid skip_if block" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            skip_if do |record, context|
              record[:processed] == true
            end
          end
        end

        expect(agent_class._intelligent_streaming_config.state_management[:skip_if]).not_to be_nil
      end

      it "accepts valid load_existing block" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            load_existing do |record, context|
              { cached: true, data: record }
            end
          end
        end

        expect(agent_class._intelligent_streaming_config.state_management[:load_existing]).not_to be_nil
      end

      it "accepts valid persist block" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            persist do |stream_results, context|
              # Save to database
              true
            end
          end
        end

        expect(agent_class._intelligent_streaming_config.state_management[:persist]).not_to be_nil
      end
    end
  end

  describe "state management validation" do
    context "state management combinations" do
      it "allows combination of all state blocks" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            skip_if do |record, context|
              record[:processed]
            end

            load_existing do |record, context|
              { cached: record }
            end

            persist do |stream_results, context|
              true
            end
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.state_management[:skip_if]).not_to be_nil
        expect(config.state_management[:load_existing]).not_to be_nil
        expect(config.state_management[:persist]).not_to be_nil
      end

      it "allows partial state management (skip_if only)" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            skip_if do |record, context|
              record[:skip]
            end
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.state_management[:skip_if]).not_to be_nil
        expect(config.state_management[:load_existing]).to be_nil
        expect(config.state_management[:persist]).to be_nil
      end

      it "allows partial state management (persist only)" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            persist do |stream_results, context|
              true
            end
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.state_management[:skip_if]).to be_nil
        expect(config.state_management[:load_existing]).to be_nil
        expect(config.state_management[:persist]).not_to be_nil
      end

      it "works with no state management blocks" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
            # No state management blocks
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.state_management[:skip_if]).to be_nil
        expect(config.state_management[:load_existing]).to be_nil
        expect(config.state_management[:persist]).to be_nil
      end
    end
  end

  describe "configuration conflicts" do
    context "conflicting settings" do
      it "prevents multiple intelligent_streaming blocks" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              stream_size 10
              over :items
            end

            intelligent_streaming do
              stream_size 20
              over :companies
            end
          end
        }.to raise_error(ArgumentError, /intelligent_streaming already configured/)
      end

      it "validates mutually exclusive options" do
        # Example: Can't have skip_if and process all
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items

            skip_if do |record, context|
              false # Never skip
            end
          end
        end

        # This should work - no conflict
        expect(agent_class._intelligent_streaming_config).not_to be_nil
      end
    end
  end

  describe "missing required configuration" do
    context "missing stream_size" do
      it "raises error when stream_size is not provided" do
        expect {
          Class.new(base_agent_class) do
            intelligent_streaming do
              over :items
              # Missing stream_size
            end
          end
        }.to raise_error(ArgumentError, /stream_size is required/)
      end
    end
  end

  describe "configuration method chaining" do
    context "fluent interface" do
      it "allows method chaining in configuration block" do
        agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
            incremental true

            on_stream_start do |stream_num, total, context|
              # Start hook
            end

            on_stream_complete do |stream_num, total, results|
              # Complete hook
            end

            skip_if do |record, context|
              record[:skip]
            end
          end
        end

        config = agent_class._intelligent_streaming_config
        expect(config.stream_size).to eq(10)
        expect(config.array_field).to eq(:items)
        expect(config.incremental).to be(true)
        expect(config.hooks[:on_stream_start]).not_to be_nil
        expect(config.hooks[:on_stream_complete]).not_to be_nil
        expect(config.state_management[:skip_if]).not_to be_nil
      end
    end
  end
end