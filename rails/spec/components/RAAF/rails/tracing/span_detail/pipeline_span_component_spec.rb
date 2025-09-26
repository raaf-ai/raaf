# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanDetail::PipelineSpanComponent, type: :component do
  let(:base_span_attributes) do
    {
      "span_id" => "span_123",
      "trace_id" => "trace_456",
      "name" => "DataProcessingPipeline",
      "kind" => "pipeline",
      "status" => "success",
      "duration_ms" => 2500
    }
  end

  let(:span) { double("SpanRecord", **base_span_attributes, span_attributes: span_attributes, start_time: Time.now - 2.5, end_time: Time.now) }
  let(:component) { described_class.new(span: span) }

  describe "#view_template" do
    context "with comprehensive pipeline data" do
      let(:span_attributes) do
        {
          "pipeline" => {
            "name" => "MarketDiscoveryPipeline",
            "status" => "completed",
            "stages" => [
              {
                "name" => "DataAnalysis",
                "status" => "success",
                "duration_ms" => 800,
                "input" => { "query" => "market research" },
                "output" => { "markets" => ["enterprise", "startup"] }
              },
              {
                "name" => "MarketScoring",
                "status" => "success",
                "duration_ms" => 600,
                "agent" => "ScoringAgent",
                "scoring_criteria" => ["market_size", "competition", "fit"]
              },
              {
                "name" => "SearchTermGeneration",
                "status" => "success",
                "duration_ms" => 1100,
                "terms_generated" => 42
              }
            ],
            "data_flow" => [
              {
                "description" => "Initial market analysis",
                "input" => { "company_data": "company_123" },
                "output" => { "markets": ["enterprise", "startup"] }
              },
              {
                "description" => "Market scoring",
                "input" => { "markets": ["enterprise", "startup"] },
                "output" => { "scored_markets": [{"name": "enterprise", "score": 85}] }
              },
              {
                "description" => "Search term generation",
                "input" => { "scored_markets": [{"name": "enterprise", "score": 85}] },
                "output" => { "search_terms": ["CTO", "VP Engineering"] }
              }
            ],
            "metadata" => {
              "total_agents" => 3,
              "pipeline_version" => "v2.1",
              "execution_mode" => "sequential",
              "retry_attempts" => 0
            },
            "results" => {
              "markets_discovered" => 2,
              "total_search_terms" => 42,
              "overall_success" => true,
              "performance_metrics" => {
                "total_time_ms" => 2500,
                "avg_stage_time_ms" => 833
              }
            }
          }
        }
      end

      it "renders pipeline overview with execution status" do
        render_inline(component)
        
        expect(rendered_component).to have_css(".bg-purple-50")
        expect(rendered_component).to have_css(".bi-diagram-3")
        expect(rendered_component).to have_content("Pipeline Execution")
        expect(rendered_component).to have_content("Pipeline: MarketDiscoveryPipeline")
        expect(rendered_component).to have_content("Stages: 3")
        expect(rendered_component).to have_content("Status: completed")
      end

      it "renders pipeline status badge with correct color" do
        render_inline(component)
        
        # Should have completed status badge in green
        expect(rendered_component).to have_css(".bg-green-100.text-green-800")
        expect(rendered_component).to have_content("Completed")
      end

      it "renders stage execution timeline" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#stage-execution-content")
        expect(rendered_component).to have_content("Stage Execution")
        
        # Should show all stages
        expect(rendered_component).to have_content("DataAnalysis")
        expect(rendered_component).to have_content("MarketScoring")
        expect(rendered_component).to have_content("SearchTermGeneration")
        
        # Should show stage statuses
        expect(rendered_component).to have_content("SUCCESS").at_least(3).times
      end

      it "renders stage indicators with proper status colors" do
        render_inline(component)
        
        # Should have success indicators (green circles with numbers)
        expect(rendered_component).to have_css(".bg-green-500.text-white")
        expect(rendered_component).to have_content("1")
        expect(rendered_component).to have_content("2")
        expect(rendered_component).to have_content("3")
      end

      it "renders data flow sequence" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#data-flow-content")
        expect(rendered_component).to have_content("Data Flow")
        
        # Should show flow steps
        expect(rendered_component).to have_content("Initial market analysis")
        expect(rendered_component).to have_content("Market scoring")
        expect(rendered_component).to have_content("Search term generation")
        
        # Should show input/output data
        expect(rendered_component).to have_content("Input: company_data")
        expect(rendered_component).to have_content("Output: markets")
      end

      it "renders pipeline metadata section" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#pipeline-metadata-content")
        expect(rendered_component).to have_content("Pipeline Metadata")
        expect(rendered_component).to have_content("Total Agents")
        expect(rendered_component).to have_content("3")
        expect(rendered_component).to have_content("Pipeline Version")
        expect(rendered_component).to have_content("v2.1")
        expect(rendered_component).to have_content("Execution Mode")
        expect(rendered_component).to have_content("sequential")
      end

      it "renders step results section (initially collapsed)" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#step-results-content.hidden")
        expect(rendered_component).to have_content("Step Results")
      end

      it "includes expand/collapse functionality" do
        render_inline(component)
        
        # Should have stimulus controller
        expect(rendered_component).to have_css("[data-controller='span-detail']")
        
        # Should have toggle buttons with proper data attributes
        expect(rendered_component).to have_css("[data-action='click->span-detail#toggleSection']")
        expect(rendered_component).to have_css(".toggle-icon")
      end
    end

    context "with minimal pipeline data" do
      let(:span_attributes) do
        {
          "pipeline" => {
            "name" => "SimplePipeline",
            "status" => "running"
          }
        }
      end

      it "renders basic pipeline information" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Pipeline Execution")
        expect(rendered_component).to have_content("Pipeline: SimplePipeline")
        expect(rendered_component).to have_content("Status: running")
        expect(rendered_component).to have_content("Stages: 0")
      end

      it "shows running status badge" do
        render_inline(component)
        
        expect(rendered_component).to have_css(".bg-blue-100.text-blue-800")
        expect(rendered_component).to have_content("Running")
      end

      it "does not render empty sections" do
        render_inline(component)
        
        expect(rendered_component).not_to have_css("#stage-execution-content")
        expect(rendered_component).not_to have_css("#data-flow-content")
        expect(rendered_component).not_to have_css("#step-results-content")
      end
    end

    context "with failed pipeline data" do
      let(:span_attributes) do
        {
          "pipeline" => {
            "name" => "FailedPipeline",
            "status" => "failed",
            "stages" => [
              {
                "name" => "Stage1",
                "status" => "success"
              },
              {
                "name" => "Stage2",
                "status" => "failed"
              }
            ]
          }
        }
      end

      it "shows failed status correctly" do
        render_inline(component)
        
        expect(rendered_component).to have_css(".bg-red-100.text-red-800")
        expect(rendered_component).to have_content("Failed")
      end

      it "shows mixed stage statuses" do
        render_inline(component)
        
        # Should have success indicator for first stage
        expect(rendered_component).to have_css(".bg-green-500.text-white")
        
        # Should have failed indicator for second stage
        expect(rendered_component).to have_css(".bg-red-500.text-white")
      end
    end

    context "with running pipeline showing animation" do
      let(:span_attributes) do
        {
          "pipeline" => {
            "stages" => [
              {
                "name" => "CurrentStage",
                "status" => "running"
              }
            ]
          }
        }
      end

      it "shows animated running indicator" do
        render_inline(component)
        
        # Should have animated indicator with arrow
        expect(rendered_component).to have_css(".animate-pulse")
        expect(rendered_component).to have_css(".bi-arrow-right")
      end
    end

    context "with alternative data structure (steps instead of stages)" do
      let(:span_attributes) do
        {
          "steps" => [
            { "name" => "Step1", "status" => "completed" },
            { "name" => "Step2", "status" => "pending" }
          ]
        }
      end

      it "handles steps as alternative to stages" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Pipeline Execution")
        expect(rendered_component).to have_content("Stages: 2")
        expect(rendered_component).to have_content("Step1")
        expect(rendered_component).to have_content("Step2")
      end
    end

    context "with no pipeline data" do
      let(:span_attributes) { {} }

      it "renders with defaults" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Pipeline Execution")
        expect(rendered_component).to have_content("Pipeline: Unknown Pipeline")
        expect(rendered_component).to have_content("Status: success")
        expect(rendered_component).to have_content("Stages: 0")
      end
    end

    context "with different pipeline statuses" do
      %w[success completed failed error running in_progress paused waiting].each do |status|
        context "when status is #{status}" do
          let(:span_attributes) do
            {
              "pipeline" => {
                "status" => status
              }
            }
          end

          it "renders appropriate status badge color" do
            render_inline(component)
            
            case status
            when "success", "completed"
              expect(rendered_component).to have_css(".bg-green-100.text-green-800")
            when "failed", "error"
              expect(rendered_component).to have_css(".bg-red-100.text-red-800")
            when "running", "in_progress"
              expect(rendered_component).to have_css(".bg-blue-100.text-blue-800")
            when "paused", "waiting"
              expect(rendered_component).to have_css(".bg-yellow-100.text-yellow-800")
            end
            
            expect(rendered_component).to have_content(status.titleize)
          end
        end
      end
    end
  end

  describe "data extraction methods" do
    let(:span_attributes) do
      {
        "pipeline" => {
          "name" => "TestPipeline",
          "status" => "completed",
          "stages" => [{ "name" => "Stage1" }],
          "data_flow" => [{ "step" => "flow1" }],
          "metadata" => { "version" => "v1.0" },
          "results" => { "count" => 5 }
        }
      }
    end

    it "extracts pipeline name correctly" do
      expect(component.send(:pipeline_name)).to eq("TestPipeline")
    end

    it "extracts pipeline status correctly" do
      expect(component.send(:pipeline_status)).to eq("completed")
    end

    it "extracts pipeline stages correctly" do
      expect(component.send(:pipeline_stages)).to eq([{ "name" => "Stage1" }])
    end

    it "calculates total stages correctly" do
      expect(component.send(:total_stages)).to eq(1)
    end

    it "extracts data flow correctly" do
      expect(component.send(:data_flow)).to eq([{ "step" => "flow1" }])
    end

    it "extracts pipeline metadata correctly" do
      metadata = component.send(:pipeline_metadata)
      expect(metadata["version"]).to eq("v1.0")
      expect(metadata["total_duration_ms"]).to eq(2500)
    end

    it "extracts step results correctly" do
      expect(component.send(:step_results)).to eq({ "count" => 5 })
    end
  end

  describe "debug mode" do
    context "in development environment" do
      let(:span_attributes) { { "some" => "data" } }

      before { allow(Rails.env).to receive(:development?).and_return(true) }

      it "shows debug raw attributes section" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#raw-attributes-content")
        expect(rendered_component).to have_content("Debug: Raw Attributes")
      end
    end
  end

  describe "data truncation" do
    let(:span_attributes) { {} }
    
    it "truncates long data appropriately" do
      long_string = "a" * 100
      truncated = component.send(:truncate_data, long_string)
      expect(truncated).to eq("#{'a' * 50}...")
    end

    it "does not truncate short data" do
      short_string = "short"
      truncated = component.send(:truncate_data, short_string)
      expect(truncated).to eq("short")
    end

    it "handles non-string data" do
      hash_data = { key: "value" }
      truncated = component.send(:truncate_data, hash_data)
      expect(truncated).to include("key")
      expect(truncated).to include("value")
    end
  end
end