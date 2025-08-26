# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe "Pipeline Schema Support" do
  let(:mock_schema_block) do
    proc do
      { 
        type: "object",
        properties: {
          test_field: { type: "string", required: true },
          data: { type: "array", items: { type: "string" } }
        }
      }
    end
  end

  describe "Pipeline DSL" do
    let(:test_pipeline_class) do
      Class.new(RAAF::Pipeline) do
        pipeline_schema do
          { 
            type: "object",
            properties: {
              test_field: { type: "string", required: true },
              data: { type: "array", items: { type: "string" } }
            }
          }
        end
        
        # Skip validation for test
        skip_validation!
      end
    end

    it "allows defining pipeline schema" do
      expect(test_pipeline_class.pipeline_schema_block).to be_a(Proc)
    end

    it "provides schema to pipeline instances" do
      pipeline = test_pipeline_class.new
      schema_result = pipeline.pipeline_schema.call
      
      expect(schema_result).to include(
        type: "object",
        properties: hash_including(
          test_field: { type: "string", required: true },
          data: { type: "array", items: { type: "string" } }
        )
      )
    end
  end

  describe "Agent Schema Injection" do
    let(:mock_agent_class) do
      Class.new do
        include RAAF::DSL::ContextAccess
        include RAAF::Logger
        
        def initialize(**kwargs)
          @pipeline_schema = nil
        end
        
        def inject_pipeline_schema(schema_block)
          @pipeline_schema = schema_block
        end
        
        def build_schema
          if @pipeline_schema
            @pipeline_schema.call
          else
            { type: "object", properties: {} }
          end
        end
        
        def run
          { success: true, schema_used: build_schema }
        end

        def self.requirements_met?(context)
          true
        end
      end
    end

    let(:test_pipeline_class) do
      agent_class = mock_agent_class
      Class.new(RAAF::Pipeline) do
        pipeline_schema do
          { 
            type: "object",
            properties: {
              shared_field: { type: "string", required: true }
            }
          }
        end
        
        # Mock flow with our test agent
        define_method(:execute_chain) do |chain, context|
          agent_instance = agent_class.new
          
          # Simulate the schema injection
          if pipeline_schema && agent_instance.respond_to?(:inject_pipeline_schema)
            agent_instance.inject_pipeline_schema(pipeline_schema)
          end
          
          agent_instance.run
        end
        
        skip_validation!
      end
    end

    it "injects schema into agents during execution" do
      pipeline = test_pipeline_class.new
      result = pipeline.run
      
      expect(result[:schema_used]).to include(
        type: "object",
        properties: hash_including(
          shared_field: { type: "string", required: true }
        )
      )
    end
  end
end