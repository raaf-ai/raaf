# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"
require "phlex/testing/view_helper"

# Load the component files
require_relative "../../../../../app/components/RAAF/rails/tracing/base_component"
require_relative "../../../../../app/components/RAAF/rails/tracing/span_detail_base"

module RAAF
  module Rails
    module Tracing
      RSpec.describe SpanDetailBase, type: :component do
        include Phlex::Testing::ViewHelper

        let(:base_span_attributes) do
          {
            "function" => {
              "name" => "test_function",
              "input" => { "query" => "test query" },
              "output" => { "result" => "success" }
            }
          }
        end

        let(:mock_span) do
          double("Span",
            span_id: "span_123",
            trace_id: "trace_456",
            parent_id: "parent_789",
            name: "Test Span",
            kind: "tool",
            status: "success",
            start_time: Time.parse("2025-09-25 10:00:00 UTC"),
            end_time: Time.parse("2025-09-25 10:00:00.150 UTC"),
            duration_ms: 150,
            span_attributes: base_span_attributes,
            depth: 1
          )
        end

        # Create a concrete test class since SpanDetailBase is abstract
        let(:test_component_class) do
          Class.new(SpanDetailBase) do
            def view_template
              div(class: "test-wrapper") do
                render_span_overview
                render_timing_details
              end
            end
          end
        end

        let(:component) { test_component_class.new(span: mock_span) }

        describe "initialization" do
          it "accepts span as keyword argument" do
            expect { test_component_class.new(span: mock_span) }.not_to raise_error
          end

          it "accepts optional trace parameter" do
            mock_trace = double("Trace", workflow_name: "Test Workflow")
            expect { test_component_class.new(span: mock_span, trace: mock_trace) }.not_to raise_error
          end

          it "accepts additional options" do
            expect { test_component_class.new(span: mock_span, custom_option: "value") }.not_to raise_error
          end
        end

        describe "#render_span_overview" do
          it "renders overview section with span details" do
            output = render(component)
            expect(output).to include("Overview")
            expect(output).to include("span_123")
            expect(output).to include("trace_456")
            expect(output).to include("parent_789")
            expect(output).to include("Test Span")
          end

          it "shows 'None' for missing parent_id" do
            allow(mock_span).to receive(:parent_id).and_return(nil)
            output = render(component)
            expect(output).to include("None")
          end

          it "includes depth information" do
            output = render(component)
            expect(output).to include("1")
          end
        end

        describe "#render_timing_details" do
          it "renders timing information section" do
            output = render(component)
            expect(output).to include("Timing Information")
            expect(output).to include("2025-09-25 10:00:00.000")
            expect(output).to include("150ms")
          end

          it "handles nil timestamps" do
            allow(mock_span).to receive(:start_time).and_return(nil)
            allow(mock_span).to receive(:end_time).and_return(nil)
            output = render(component)
            expect(output).to include("N/A")
          end
        end

        describe "#format_timestamp" do
          let(:time) { Time.parse("2025-09-25 10:00:00.123 UTC") }
          let(:component_instance) { test_component_class.new(span: mock_span) }

          it "formats timestamps correctly" do
            result = component_instance.send(:format_timestamp, time)
            expect(result).to eq("2025-09-25 10:00:00.123")
          end

          it "returns N/A for nil timestamps" do
            result = component_instance.send(:format_timestamp, nil)
            expect(result).to eq("N/A")
          end
        end

        describe "#render_duration_badge" do
          let(:component_instance) { test_component_class.new(span: mock_span) }

          it "renders green badge for fast durations" do
            # We need to create a simple component to test the badge rendering
            badge_component = Class.new(SpanDetailBase) do
              def view_template
                render_duration_badge(50)
              end
            end

            output = render(badge_component.new(span: mock_span))
            expect(output).to include("bg-green-100")
            expect(output).to include("50ms")
          end

          it "renders yellow badge for medium durations" do
            badge_component = Class.new(SpanDetailBase) do
              def view_template
                render_duration_badge(500)
              end
            end

            output = render(badge_component.new(span: mock_span))
            expect(output).to include("bg-yellow-100")
            expect(output).to include("500ms")
          end

          it "renders red badge for slow durations" do
            badge_component = Class.new(SpanDetailBase) do
              def view_template
                render_duration_badge(2000)
              end
            end

            output = render(badge_component.new(span: mock_span))
            expect(output).to include("bg-red-100")
            expect(output).to include("2000ms")
          end

          it "handles nil duration" do
            badge_component = Class.new(SpanDetailBase) do
              def view_template
                render_duration_badge(nil)
              end
            end

            output = render(badge_component.new(span: mock_span))
            expect(output).to include("N/A")
          end
        end

        describe "#render_json_section" do
          let(:test_data) { { "key" => "value", "number" => 42 } }

          let(:json_component) do
            Class.new(SpanDetailBase) do
              def initialize(span:, data:)
                super(span: span)
                @test_data = data
              end

              def view_template
                render_json_section("Test Data", @test_data)
              end
            end
          end

          it "renders JSON section with formatted data" do
            component = json_component.new(span: mock_span, data: test_data)
            output = render(component)
            expect(output).to include("Test Data")
            expect(output).to include('"key"')
            expect(output).to include('"value"')
          end

          it "handles collapsed state" do
            component = json_component.new(span: mock_span, data: test_data)
            output = render(component)
            expect(output).to include("section-test-data-span_123")
            expect(output).to include("bi-chevron-right")
          end

          it "returns early for nil data" do
            component = json_component.new(span: mock_span, data: nil)
            output = render(component)
            expect(output.strip).to be_empty
          end
        end

        describe "#format_json_display" do
          let(:component_instance) { test_component_class.new(span: mock_span) }

          it "formats hash as pretty JSON" do
            data = { "key" => "value" }
            result = component_instance.send(:format_json_display, data)
            expect(result).to include('"key"')
            expect(result).to include('"value"')
          end

          it "formats array as pretty JSON" do
            data = ["item1", "item2"]
            result = component_instance.send(:format_json_display, data)
            expect(result).to include('"item1"')
            expect(result).to include('"item2"')
          end

          it "parses JSON strings" do
            json_string = '{"parsed": true}'
            result = component_instance.send(:format_json_display, json_string)
            expect(result).to include('"parsed"')
            expect(result).to include('true')
          end

          it "returns original string for invalid JSON" do
            invalid_json = "not json"
            result = component_instance.send(:format_json_display, invalid_json)
            expect(result).to eq("not json")
          end

          it "returns N/A for nil" do
            result = component_instance.send(:format_json_display, nil)
            expect(result).to eq("N/A")
          end

          it "converts other types to string" do
            result = component_instance.send(:format_json_display, 42)
            expect(result).to eq("42")
          end
        end

        describe "#extract_span_attribute" do
          let(:component_instance) { test_component_class.new(span: mock_span) }

          it "extracts nested attributes" do
            result = component_instance.send(:extract_span_attribute, "function")
            expect(result).to eq(base_span_attributes["function"])
          end

          it "returns nil for missing attributes" do
            result = component_instance.send(:extract_span_attribute, "missing")
            expect(result).to be_nil
          end
        end

        # Task 5.2 - Enhanced timing functionality tests
        describe "#render_performance_metrics" do
          let(:performance_component) do
            Class.new(SpanDetailBase) do
              def view_template
                render_performance_metrics
              end
            end
          end

          it "renders performance metrics for spans with duration" do
            component = performance_component.new(span: mock_span)
            output = render(component)
            expect(output).to include("Performance Metrics")
            expect(output).to include("Throughput")
            expect(output).to include("Category")
            expect(output).to include("Speed")
            expect(output).to include("Intensity")
          end

          it "returns early when no duration available" do
            allow(mock_span).to receive(:duration_ms).and_return(nil)
            component = performance_component.new(span: mock_span)
            output = render(component)
            expect(output.strip).to be_empty
          end
        end

        describe "#render_timing_comparisons" do
          let(:timing_component) do
            Class.new(SpanDetailBase) do
              def view_template
                render_timing_comparisons
              end
            end
          end

          it "renders timing comparisons when parent_id present" do
            component = timing_component.new(span: mock_span, trace: double("Trace"))
            output = render(component)
            expect(output).to include("Timing Comparisons")
            expect(output).to include("vs Typical")
          end

          it "includes trace comparisons when trace available" do
            mock_trace = double("Trace", workflow_name: "Test Workflow")
            component = timing_component.new(span: mock_span, trace: mock_trace)
            output = render(component)
            expect(output).to include("% of Total Trace")
          end
        end

        describe "performance calculation helpers" do
          let(:component_instance) { test_component_class.new(span: mock_span) }

          describe "#calculate_throughput" do
            it "calculates operations per second correctly" do
              result = component_instance.send(:calculate_throughput)
              expect(result).to eq(6.67) # 1000 / 150ms
            end

            it "returns N/A for zero duration" do
              allow(mock_span).to receive(:duration_ms).and_return(0)
              result = component_instance.send(:calculate_throughput)
              expect(result).to eq("N/A")
            end
          end

          describe "#performance_category" do
            it "returns correct category for fast spans" do
              allow(mock_span).to receive(:duration_ms).and_return(50)
              result = component_instance.send(:performance_category)
              expect(result).to eq("Excellent")
            end

            it "returns correct category for slow spans" do
              allow(mock_span).to receive(:duration_ms).and_return(2000)
              result = component_instance.send(:performance_category)
              expect(result).to eq("Slow")
            end
          end

          describe "#relative_speed_indicator" do
            it "returns appropriate emoji for fast spans" do
              allow(mock_span).to receive(:duration_ms).and_return(25)
              result = component_instance.send(:relative_speed_indicator)
              expect(result).to eq("⚡ Lightning")
            end

            it "returns appropriate emoji for very slow spans" do
              allow(mock_span).to receive(:duration_ms).and_return(6000)
              result = component_instance.send(:relative_speed_indicator)
              expect(result).to eq("🐌 Very Slow")
            end
          end
        end

        # Task 5.4 - Performance optimization tests
        describe "large data handling" do
          let(:large_data) { { "key" => "x" * 15000 } } # Large data over threshold
          let(:small_data) { { "key" => "small value" } }

          describe "#calculate_data_size" do
            let(:component_instance) { test_component_class.new(span: mock_span) }

            it "calculates size for hash data" do
              result = component_instance.send(:calculate_data_size, small_data)
              expect(result).to be > 0
            end

            it "calculates size for large data correctly" do
              result = component_instance.send(:calculate_data_size, large_data)
              expect(result).to be > 10000
            end

            it "calculates size for string data" do
              result = component_instance.send(:calculate_data_size, "test string")
              expect(result).to eq(11)
            end
          end

          describe "#format_data_size" do
            let(:component_instance) { test_component_class.new(span: mock_span) }

            it "formats small sizes in characters" do
              result = component_instance.send(:format_data_size, 500)
              expect(result).to eq("500 chars")
            end

            it "formats medium sizes in KB" do
              result = component_instance.send(:format_data_size, 5000)
              expect(result).to eq("5.0K chars")
            end

            it "formats large sizes in MB" do
              result = component_instance.send(:format_data_size, 2_000_000)
              expect(result).to eq("2.0M chars")
            end
          end

          describe "#render_json_section with performance optimizations" do
            let(:large_json_component) do
              Class.new(SpanDetailBase) do
                def initialize(span:, data:)
                  super(span: span)
                  @test_data = data
                end

                def view_template
                  render_json_section("Test Data", @test_data)
                end
              end
            end

            it "shows performance warning for large data" do
              component = large_json_component.new(span: mock_span, data: large_data)
              output = render(component)
              expect(output).to include("Large")
              expect(output).to include("Large data set")
            end

            it "shows normal view for small data" do
              component = large_json_component.new(span: mock_span, data: small_data)
              output = render(component)
              expect(output).not_to include("Large data set")
            end
          end

          describe "#truncate_large_data" do
            let(:component_instance) { test_component_class.new(span: mock_span) }

            it "truncates large hash data" do
              large_hash = (1..20).map { |i| ["key#{i}", "value#{i}"] }.to_h
              result = component_instance.send(:truncate_large_data, large_hash, max_items: 5)
              expect(result.keys.count).to eq(5)
              expect(result).to include("key1" => "value1", "key5" => "value5")
            end

            it "truncates large array data" do
              large_array = (1..20).to_a
              result = component_instance.send(:truncate_large_data, large_array, max_items: 3)
              expect(result).to eq([1, 2, 3])
            end

            it "truncates long string data" do
              long_string = "x" * 2000
              result = component_instance.send(:truncate_large_data, long_string)
              expect(result.length).to eq(1000)
              expect(result).to eq("x" * 1000)
            end
          end
        end

        # Task 5.3 - Responsive design tests
        describe "responsive design features" do
          describe "#render_span_overview with mobile classes" do
            it "includes mobile-responsive classes" do
              output = render(component)
              expect(output).to include("px-3")        # Mobile padding
              expect(output).to include("sm:px-4")     # Tablet padding
              expect(output).to include("lg:px-6")     # Desktop padding
              expect(output).to include("flex-col")    # Mobile column layout
              expect(output).to include("sm:flex-row") # Desktop row layout
            end

            it "includes responsive grid classes" do
              output = render(component)
              expect(output).to include("grid-cols-1")    # Mobile single column
              expect(output).to include("sm:grid-cols-2") # Tablet two columns
              expect(output).to include("lg:grid-cols-3") # Desktop three columns
            end
          end

          describe "#render_span_hierarchy_navigation mobile optimization" do
            it "includes mobile-optimized navigation classes" do
              output = render(component)
              expect(output).to include("flex-wrap")      # Allow wrapping on mobile
              expect(output).to include("overflow-x-auto") # Horizontal scroll
              expect(output).to include("gap-1")          # Smaller gap on mobile
              expect(output).to include("sm:gap-2")       # Larger gap on desktop
              expect(output).to include("text-xs")        # Smaller text on mobile
              expect(output).to include("sm:text-sm")     # Normal text on desktop
            end

            it "hides labels on mobile" do
              output = render(component)
              expect(output).to include("hidden sm:inline") # Labels hidden on mobile
            end
          end

          describe "#render_detail_item mobile styling" do
            let(:detail_component) do
              Class.new(SpanDetailBase) do
                def view_template
                  render_detail_item("Test Label", "Test Value")
                end
              end
            end

            it "includes mobile background and responsive styling" do
              component = detail_component.new(span: mock_span)
              output = render(component)
              expect(output).to include("bg-gray-50")         # Mobile background
              expect(output).to include("sm:bg-transparent")  # No background on desktop
              expect(output).to include("break-all")          # Break long text on mobile
              expect(output).to include("sm:break-normal")    # Normal text wrapping on desktop
            end
          end
        end

        # Badge rendering tests
        describe "helper badge methods" do
          let(:component_instance) { test_component_class.new(span: mock_span) }

          describe "#render_status_badge" do
            let(:badge_component) do
              Class.new(SpanDetailBase) do
                def initialize(span:, status:)
                  super(span: span)
                  @test_status = status
                end

                def view_template
                  render_status_badge(@test_status)
                end
              end
            end

            it "renders success status with green styling" do
              component = badge_component.new(span: mock_span, status: "success")
              output = render(component)
              expect(output).to include("bg-green-100")
              expect(output).to include("text-green-800")
              expect(output).to include("Success")
            end

            it "renders error status with red styling" do
              component = badge_component.new(span: mock_span, status: "error")
              output = render(component)
              expect(output).to include("bg-red-100")
              expect(output).to include("text-red-800")
              expect(output).to include("Error")
            end

            it "renders unknown status with default styling" do
              component = badge_component.new(span: mock_span, status: nil)
              output = render(component)
              expect(output).to include("bg-gray-100")
              expect(output).to include("unknown")
            end
          end

          describe "#render_kind_badge" do
            let(:kind_badge_component) do
              Class.new(SpanDetailBase) do
                def initialize(span:, kind:)
                  super(span: span)
                  @test_kind = kind
                end

                def view_template
                  render_kind_badge(@test_kind)
                end
              end
            end

            it "renders tool kind with purple styling" do
              component = kind_badge_component.new(span: mock_span, kind: "tool")
              output = render(component)
              expect(output).to include("bg-purple-100")
              expect(output).to include("text-purple-800")
              expect(output).to include("Tool")
            end

            it "renders agent kind with blue styling" do
              component = kind_badge_component.new(span: mock_span, kind: "agent")
              output = render(component)
              expect(output).to include("bg-blue-100")
              expect(output).to include("text-blue-800")
              expect(output).to include("Agent")
            end
          end

          describe "#time_ago_in_words" do
            it "formats recent time correctly" do
              recent_time = Time.now - 30
              result = component_instance.send(:time_ago_in_words, recent_time)
              expect(result).to include("seconds")
            end

            it "formats minutes correctly" do
              minutes_ago = Time.now - 300 # 5 minutes
              result = component_instance.send(:time_ago_in_words, minutes_ago)
              expect(result).to include("minutes")
            end

            it "formats hours correctly" do
              hours_ago = Time.now - 7200 # 2 hours
              result = component_instance.send(:time_ago_in_words, hours_ago)
              expect(result).to include("hours")
            end

            it "handles nil time" do
              result = component_instance.send(:time_ago_in_words, nil)
              expect(result).to eq("unknown")
            end
          end
        end
      end
    end
  end
end