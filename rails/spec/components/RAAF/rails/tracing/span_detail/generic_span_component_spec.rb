# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanDetail::GenericSpanComponent, type: :component do
  let(:base_span_attributes) do
    {
      "span_id" => "span_123",
      "trace_id" => "trace_456",
      "name" => "CustomSpan",
      "kind" => "unknown",
      "status" => "success",
      "duration_ms" => 150
    }
  end

  let(:span) { double("SpanRecord", **base_span_attributes, span_attributes: span_attributes, start_time: Time.now - 0.15, end_time: Time.now) }
  let(:component) { described_class.new(span: span) }

  describe "#view_template" do
    context "with comprehensive attribute data" do
      let(:span_attributes) do
        {
          "custom_name" => "TestCustomSpan",
          "execution_mode" => "async",
          "model_version" => "v2.1",
          "user_id" => 12345,
          "active" => true,
          "disabled" => false,
          "description" => nil,
          "metadata" => {
            "created_at" => "2023-10-01",
            "version" => "1.0.0",
            "environment" => "production"
          },
          "input_data" => {
            "query" => "search term",
            "filters" => ["active", "published"],
            "options" => { "limit" => 10, "sort" => "created_at" }
          },
          "timing_info" => {
            "queue_time_ms" => 50,
            "processing_time_ms" => 100
          },
          "results" => {
            "count" => 25,
            "items" => ["item1", "item2", "item3"],
            "has_more" => true
          },
          "error_context" => {
            "retry_count" => 0,
            "last_error" => nil
          },
          "custom_field" => "custom_value",
          "tags" => ["processing", "search", "user-initiated"]
        }
      end

      it "renders generic overview with unknown span indication" do
        render_inline(component)
        
        expect(rendered_component).to have_css(".bg-gray-50")
        expect(rendered_component).to have_css(".bi-question-circle")
        expect(rendered_component).to have_content("Unknown Span Type")
        expect(rendered_component).to have_content("Kind: unknown")
        expect(rendered_component).to have_content("This span type is not specifically supported yet")
      end

      it "renders generic status badge with correct color" do
        render_inline(component)
        
        expect(rendered_component).to have_css(".bg-green-100.text-green-800")
        expect(rendered_component).to have_content("Success")
      end

      it "renders universal span overview" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Span Overview")
        expect(rendered_component).to have_content("span_123")
        expect(rendered_component).to have_content("trace_456")
        expect(rendered_component).to have_content("CustomSpan")
      end

      it "renders enhanced timing details" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Timing Information")
        expect(rendered_component).to have_content("Start Time")
        expect(rendered_component).to have_content("End Time")
        expect(rendered_component).to have_content("Duration")
      end

      it "renders grouped raw attributes" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#raw-attributes-content")
        expect(rendered_component).to have_content("Raw Attributes (#{span_attributes.keys.count} items)")
        
        # Should show attribute groups
        expect(rendered_component).to have_content("Metadata")
        expect(rendered_component).to have_content("Execution")
        expect(rendered_component).to have_content("Data")
        expect(rendered_component).to have_content("Other")
      end

      it "categorizes attributes into logical groups" do
        render_inline(component)
        
        # Metadata group
        expect(rendered_component).to have_content("custom_name")
        expect(rendered_component).to have_content("model_version")
        
        # Execution group
        expect(rendered_component).to have_content("execution_mode")
        expect(rendered_component).to have_content("async")
        
        # Data group
        expect(rendered_component).to have_content("input_data")
        expect(rendered_component).to have_content("results")
        
        # Timing group
        expect(rendered_component).to have_content("timing_info")
      end

      it "renders attribute values with proper formatting" do
        render_inline(component)
        
        # String values
        expect(rendered_component).to have_content("TestCustomSpan")
        
        # Numeric values with proper styling
        expect(rendered_component).to have_content("12345")
        expect(rendered_component).to have_css(".bg-blue-50")
        
        # Boolean values with badges
        expect(rendered_component).to have_css(".bg-green-100.text-green-800") # for true
        expect(rendered_component).to have_css(".bg-red-100.text-red-800") # for false
        
        # Null values
        expect(rendered_component).to have_content("null")
        expect(rendered_component).to have_css(".text-gray-400")
      end

      it "handles complex nested data structures" do
        render_inline(component)
        
        # Hash objects should show object indicators
        expect(rendered_component).to have_content("Object (3 keys)")
        expect(rendered_component).to have_content("Object (3 keys)")
        
        # Arrays should show array indicators
        expect(rendered_component).to have_content("Array (2 items)")
        expect(rendered_component).to have_content("Array (3 items)")
      end

      it "includes expand/collapse functionality for attributes" do
        render_inline(component)
        
        # Should have stimulus controller
        expect(rendered_component).to have_css("[data-controller='span-detail']")
        
        # Should have toggle buttons
        expect(rendered_component).to have_css("[data-action='click->span-detail#toggleSection']")
        expect(rendered_component).to have_css(".toggle-icon")
      end

      it "provides copy functionality for JSON data" do
        render_inline(component)
        
        expect(rendered_component).to have_css("[data-action='click->span-detail#copyJson']")
        expect(rendered_component).to have_content("Copy")
      end

      context "when attributes should be expanded" do
        let(:span_attributes) { { "simple" => "value", "count" => 42 } }

        before { allow(Rails.env).to receive(:development?).and_return(true) }

        it "expands attributes by default for few attributes" do
          render_inline(component)
          
          # Should not have hidden class when expanded
          expect(rendered_component).not_to have_css("#raw-attributes-content.hidden")
        end
      end
    end

    context "with long string values" do
      let(:span_attributes) do
        {
          "long_description" => "a" * 150,
          "short_description" => "short text"
        }
      end

      it "truncates long string values with show more functionality" do
        render_inline(component)
        
        # Should show truncated version
        expect(rendered_component).to have_content("a" * 100 + "...")
        
        # Should have "Show More" button
        expect(rendered_component).to have_css("[data-action='click->span-detail#toggleValue']")
        expect(rendered_component).to have_content("Show More")
        
        # Short text should not be truncated
        expect(rendered_component).to have_content("short text")
      end
    end

    context "with large arrays" do
      let(:span_attributes) do
        {
          "small_array" => ["item1", "item2"],
          "large_array" => Array.new(10) { |i| "item#{i + 1}" }
        }
      end

      it "handles small and large arrays appropriately" do
        render_inline(component)
        
        # Small array should show all items
        expect(rendered_component).to have_content("item1")
        expect(rendered_component).to have_content("item2")
        
        # Large array should be collapsible
        expect(rendered_component).to have_content("Array (10 items)")
        expect(rendered_component).to have_css("[data-action='click->span-detail#toggleSection']")
      end
    end

    context "with additional data sections" do
      let(:span_attributes) do
        {
          "events" => [{"type" => "start", "timestamp" => "2023-10-01"}],
          "metrics" => {"cpu_usage" => 45.2, "memory_mb" => 128},
          "logs" => ["Started processing", "Completed successfully"],
          "custom" => {"feature_flags" => ["experimental"]}
        }
      end

      it "renders additional data sections when present" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Events")
        expect(rendered_component).to have_content("Metrics")
        expect(rendered_component).to have_content("Logs")
        expect(rendered_component).to have_content("Custom Data")
        
        # Sections should be collapsible and initially collapsed
        expect(rendered_component).to have_css("#additional-events-content.hidden")
        expect(rendered_component).to have_css("#additional-metrics-content.hidden")
      end
    end

    context "with minimal data" do
      let(:span_attributes) { { "simple" => "value" } }

      it "renders basic information with minimal data" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Unknown Span Type")
        expect(rendered_component).to have_content("Kind: unknown")
        expect(rendered_component).to have_content("Raw Attributes (1 items)")
        expect(rendered_component).to have_content("simple")
        expect(rendered_component).to have_content("value")
      end

      it "does not render additional data sections" do
        render_inline(component)
        
        expect(rendered_component).not_to have_content("Events")
        expect(rendered_component).not_to have_content("Metrics")
        expect(rendered_component).not_to have_content("Logs")
        expect(rendered_component).not_to have_content("Custom Data")
      end
    end

    context "with no attributes" do
      let(:span_attributes) { {} }

      it "renders basic span information without attributes" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Unknown Span Type")
        expect(rendered_component).to have_content("Span Overview")
        expect(rendered_component).to have_content("Timing Information")
        expect(rendered_component).not_to have_css("#raw-attributes-content")
      end
    end

    context "with different status values" do
      %w[success ok error failed warning].each do |status|
        context "when status is #{status}" do
          let(:base_span_attributes) { super().merge("status" => status) }
          
          it "renders appropriate status badge color" do
            render_inline(component)
            
            case status
            when "success", "ok"
              expect(rendered_component).to have_css(".bg-green-100.text-green-800")
            when "error", "failed"
              expect(rendered_component).to have_css(".bg-red-100.text-red-800")
            when "warning"
              expect(rendered_component).to have_css(".bg-yellow-100.text-yellow-800")
            end
            
            expect(rendered_component).to have_content(status.titleize)
          end
        end
      end
    end

    context "with different span kinds" do
      %w[unknown custom experimental deprecated].each do |kind|
        context "when kind is #{kind}" do
          let(:base_span_attributes) { super().merge("kind" => kind) }
          
          it "shows the kind in the overview" do
            render_inline(component)
            
            expect(rendered_component).to have_content("Kind: #{kind}")
          end
        end
      end
    end
  end

  describe "attribute grouping" do
    let(:span_attributes) do
      {
        "name" => "test",
        "execution_mode" => "sync",
        "start_time" => "2023-10-01",
        "input_data" => { "key" => "value" },
        "error_message" => "test error",
        "custom_field" => "custom"
      }
    end

    it "groups attributes correctly" do
      grouped = component.send(:grouped_attributes)
      
      expect(grouped[:metadata]).to include(["name", "test"])
      expect(grouped[:execution]).to include(["execution_mode", "sync"])
      expect(grouped[:timing]).to include(["start_time", "2023-10-01"])
      expect(grouped[:data]).to include(["input_data", { "key" => "value" }])
      expect(grouped[:error]).to include(["error_message", "test error"])
      expect(grouped[:other]).to include(["custom_field", "custom"])
    end
  end

  describe "helper methods" do
    let(:span_attributes) { { "key1" => "value1", "key2" => "value2" } }

    it "correctly identifies when attributes are present" do
      expect(component.send(:has_attributes?)).to be true
    end

    it "correctly counts attributes" do
      expect(component.send(:attribute_count)).to eq 2
    end

    it "determines expansion state correctly" do
      expect(component.send(:should_expand_attributes?)).to be true
    end

    it "truncates text appropriately" do
      long_text = "a" * 200
      truncated = component.send(:truncate, long_text, length: 100)
      expect(truncated).to eq("a" * 100 + "...")
    end

    context "with no attributes" do
      let(:span_attributes) { {} }

      it "correctly identifies when no attributes are present" do
        expect(component.send(:has_attributes?)).to be false
      end

      it "returns zero attribute count" do
        expect(component.send(:attribute_count)).to eq 0
      end
    end
  end

  describe "additional data detection" do
    context "with additional data" do
      let(:span_attributes) { { "events" => [], "metrics" => {} } }

      it "detects additional data correctly" do
        expect(component.send(:has_additional_data?)).to be true
      end
    end

    context "without additional data" do
      let(:span_attributes) { { "simple" => "value" } }

      it "does not detect additional data" do
        expect(component.send(:has_additional_data?)).to be false
      end
    end
  end
end