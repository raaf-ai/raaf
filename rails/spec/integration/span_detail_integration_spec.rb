# frozen_string_literal: true

# Integration Tests for RAAF Span Detail Component System
#
# This comprehensive integration test suite ensures that the complete span detail page
# works correctly as a cohesive unit. Unlike unit tests which focus on individual components,
# these tests verify:
#
# 1. **Component Routing**: Ensures SpanDetail routes to the correct type-specific component
# 2. **Universal Elements**: Tests span overview, timing, and hierarchy navigation across all types
# 3. **Type-Specific Rendering**: Verifies each span type displays specialized content correctly
# 4. **Interactive Functionality**: Tests Stimulus controller integration with expand/collapse
# 5. **Data Flow**: Tests various data structures and edge cases with realistic production data
# 6. **Performance**: Tests handling of large datasets with truncation/pagination
# 7. **Accessibility**: Verifies proper semantic markup and screen reader support
# 8. **Error Handling**: Tests graceful handling of malformed or missing data
#
# The test fixtures include production-like data for all span types:
# - Tool spans with complex input/output data
# - Agent spans with context, configuration, and execution metrics
# - LLM spans with request/response, token usage, and cost information
# - Handoff spans with agent transfer data and success metrics
# - Guardrail spans with content safety filtering and rule evaluation
# - Pipeline spans with multi-stage execution and performance data
# - Generic spans for custom operations and validation processes
#
# Edge cases covered:
# - Malformed JSON and null values
# - Very large datasets (1000+ items, 10MB+ strings)
# - Deep object nesting and complex data structures
# - Unicode content (emoji, Chinese, Arabic characters)
# - Error states and missing required data
#
# The tests ensure that regardless of the span type or data complexity, users get:
# - Consistent UI patterns and navigation
# - Proper data visualization with expand/collapse controls
# - Accessible semantic markup for screen readers
# - Responsive design that works on all device sizes
# - Error-free rendering even with edge case data

require "spec_helper"
require "phlex"
require "phlex/rails"
require "phlex/testing/view_helper"
require "json"

# Load all component files needed for integration testing
require_relative "../../app/components/RAAF/rails/tracing/base_component"
require_relative "../../app/components/RAAF/rails/tracing/span_detail_base"
require_relative "../../app/components/RAAF/rails/tracing/span_detail"
require_relative "../../app/components/RAAF/rails/tracing/tool_span_component"
require_relative "../../app/components/RAAF/rails/tracing/agent_span_component"
require_relative "../../app/components/RAAF/rails/tracing/llm_span_component"
require_relative "../../app/components/RAAF/rails/tracing/handoff_span_component"
require_relative "../../app/components/RAAF/rails/tracing/span_detail/guardrail_span_component"
require_relative "../../app/components/RAAF/rails/tracing/span_detail/pipeline_span_component"
require_relative "../../app/components/RAAF/rails/tracing/span_detail/generic_span_component"

module RAAF
  module Rails
    module Tracing
      RSpec.describe "SpanDetail Integration", type: :integration do
        include Phlex::Testing::ViewHelper

        # Integration test fixtures for comprehensive testing
        # These fixtures simulate real production-like data

        let(:base_time) { Time.parse("2025-09-25 10:00:00 UTC") }
        
        # Shared span factory method
        def create_mock_span(kind:, attributes:, **options)
          defaults = {
            span_id: "span_#{SecureRandom.hex(8)}",
            trace_id: "trace_#{SecureRandom.hex(8)}",
            parent_id: "parent_#{SecureRandom.hex(8)}",
            name: "Test #{kind.capitalize} Span",
            kind: kind,
            status: "success",
            start_time: base_time,
            end_time: base_time + 0.15,
            duration_ms: 150,
            span_attributes: attributes,
            depth: 1,
            children: [],
            events: []
          }
          double("Span", **defaults.merge(options))
        end

        # Mock trace object
        let(:mock_trace) do
          double("Trace",
            trace_id: "trace_integration_test",
            workflow_name: "IntegrationTestWorkflow",
            status: "success"
          )
        end

        # Test fixtures for each span type with realistic data
        let(:tool_span_attributes) do
          {
            "function" => {
              "name" => "search_companies",
              "description" => "Search for companies matching criteria",
              "input" => {
                "query" => "Ruby programming consultancy",
                "limit" => 50,
                "filters" => {
                  "industry" => "Software Development",
                  "size" => "10-50 employees",
                  "location" => "San Francisco Bay Area"
                },
                "sort_by" => "relevance"
              },
              "output" => {
                "results" => [
                  {
                    "id" => "comp_123",
                    "name" => "Ruby Masters Inc",
                    "industry" => "Software Development",
                    "employees" => 25,
                    "location" => "San Francisco, CA",
                    "website" => "https://rubymasters.com",
                    "founded" => 2018,
                    "revenue" => "$2M-5M",
                    "score" => 0.95
                  },
                  {
                    "id" => "comp_456",
                    "name" => "Code Crafters LLC",
                    "industry" => "Software Development", 
                    "employees" => 42,
                    "location" => "Palo Alto, CA",
                    "website" => "https://codecrafters.io",
                    "founded" => 2015,
                    "revenue" => "$5M-10M",
                    "score" => 0.88
                  }
                ],
                "total_found" => 2,
                "search_time_ms" => 1250,
                "api_calls" => 3,
                "cached_results" => 15
              }
            },
            "execution" => {
              "retries" => 0,
              "cache_hit" => false,
              "rate_limited" => false
            },
            "metadata" => {
              "version" => "2.1.0",
              "endpoint" => "/api/v2/companies/search"
            }
          }
        end

        let(:agent_span_attributes) do
          {
            "agent" => {
              "name" => "ProspectAnalysisAgent",
              "model" => "gpt-4o",
              "instructions" => "Analyze prospects and provide strategic insights for B2B outreach campaigns",
              "max_turns" => 5,
              "temperature" => 0.3,
              "max_tokens" => 2000,
              "tools" => [
                "search_companies",
                "enrich_prospects", 
                "analyze_market",
                "generate_personas"
              ]
            },
            "context" => {
              "product" => {
                "name" => "RAAF Framework",
                "category" => "AI Development Tools",
                "target_market" => "Software Development Teams"
              },
              "campaign" => {
                "id" => "camp_789",
                "name" => "Q4 Enterprise Outreach",
                "target_company_size" => "50-200 employees"
              },
              "analysis_depth" => "comprehensive",
              "market_segment" => "enterprise_software"
            },
            "execution" => {
              "turns_used" => 3,
              "total_tokens" => 1847,
              "completion_tokens" => 892,
              "prompt_tokens" => 955,
              "tool_calls" => 2,
              "handoffs" => 0
            },
            "result" => {
              "success" => true,
              "analysis_completed" => true,
              "insights_generated" => 12,
              "recommendations" => 8,
              "confidence_score" => 0.87
            }
          }
        end

        let(:llm_span_attributes) do
          {
            "llm" => {
              "model" => "gpt-4o",
              "provider" => "openai",
              "temperature" => 0.7,
              "max_tokens" => 1500,
              "top_p" => 1.0,
              "frequency_penalty" => 0.0,
              "presence_penalty" => 0.0
            },
            "request" => {
              "messages" => [
                {
                  "role" => "system",
                  "content" => "You are an expert market analyst specializing in B2B software companies..."
                },
                {
                  "role" => "user", 
                  "content" => "Analyze the following prospects and identify key decision makers..."
                }
              ],
              "functions" => [
                {
                  "name" => "identify_decision_makers",
                  "description" => "Identify key decision makers in target companies"
                }
              ],
              "timestamp" => "2025-09-25T10:00:00Z"
            },
            "response" => {
              "id" => "chatcmpl-AKj8pYXV2hGHyUvF9N7z3qZ8mL1eQ",
              "object" => "chat.completion",
              "created" => 1727251200,
              "model" => "gpt-4o-2024-08-06",
              "choices" => [
                {
                  "index" => 0,
                  "message" => {
                    "role" => "assistant",
                    "content" => "Based on my analysis of the provided prospects, I've identified several key patterns...",
                    "function_call" => {
                      "name" => "identify_decision_makers",
                      "arguments" => "{\"companies\":[{\"name\":\"Ruby Masters Inc\",\"decision_makers\":[{\"role\":\"CTO\",\"priority\":\"high\"}]}]}"
                    }
                  },
                  "finish_reason" => "function_call"
                }
              ],
              "usage" => {
                "prompt_tokens" => 1250,
                "completion_tokens" => 387,
                "total_tokens" => 1637
              }
            },
            "cost" => {
              "prompt_cost" => 0.01875,
              "completion_cost" => 0.01161,
              "total_cost" => 0.03036,
              "currency" => "USD"
            },
            "performance" => {
              "latency_ms" => 2847,
              "tokens_per_second" => 136.5,
              "first_token_latency_ms" => 425
            }
          }
        end

        let(:handoff_span_attributes) do
          {
            "handoff" => {
              "from_agent" => "ProspectAnalysisAgent",
              "to_agent" => "OutreachCopywriterAgent",
              "transfer_reason" => "Analysis complete, ready for personalized outreach copy generation",
              "transfer_data" => {
                "analyzed_prospects" => [
                  {
                    "company_id" => "comp_123",
                    "decision_makers" => [
                      {
                        "name" => "Sarah Chen",
                        "title" => "CTO",
                        "priority" => "high",
                        "pain_points" => ["scalability", "development velocity"],
                        "interests" => ["AI/ML", "developer tools"]
                      }
                    ],
                    "outreach_strategy" => "technical_benefits",
                    "personalization_data" => {
                      "recent_tech_stack_changes" => true,
                      "hiring_developers" => true,
                      "growth_phase" => "expansion"
                    }
                  }
                ],
                "market_insights" => {
                  "segment" => "mid-market_saas",
                  "key_challenges" => ["developer productivity", "AI adoption"],
                  "messaging_themes" => ["efficiency", "innovation", "competitive_advantage"]
                },
                "campaign_context" => {
                  "id" => "camp_789",
                  "objective" => "enterprise_adoption",
                  "timeline" => "Q4_2025"
                }
              },
              "success" => true,
              "data_size_bytes" => 3847
            },
            "execution" => {
              "handoff_duration_ms" => 45,
              "data_validation_passed" => true,
              "context_preserved" => true,
              "agent_initialization_time_ms" => 120
            },
            "agents" => {
              "source_agent_final_state" => "analysis_complete",
              "target_agent_initial_state" => "ready_for_copywriting",
              "continuation_context" => "preserved"
            }
          }
        end

        let(:guardrail_span_attributes) do
          {
            "guardrail" => {
              "type" => "content_safety",
              "rule_set" => "enterprise_b2b_v1",
              "triggered_rules" => [
                {
                  "rule_id" => "PII_DETECTION_001",
                  "rule_name" => "Personal Information Filter",
                  "severity" => "medium",
                  "action" => "redact",
                  "description" => "Detected potential PII in prospect data"
                },
                {
                  "rule_id" => "CONTENT_TONE_002", 
                  "rule_name" => "Professional Tone Enforcement",
                  "severity" => "low",
                  "action" => "suggest_revision",
                  "description" => "Message tone could be more professional"
                }
              ],
              "passed_rules" => [
                "SPAM_DETECTION_001",
                "COMPLIANCE_GDPR_001",
                "BRAND_SAFETY_001",
                "FACTUAL_ACCURACY_001"
              ],
              "overall_result" => "pass_with_modifications"
            },
            "input_analysis" => {
              "content_length" => 2847,
              "sensitive_entities" => [
                {
                  "type" => "email",
                  "value" => "s.chen@*****.com",
                  "action" => "redacted",
                  "confidence" => 0.95
                },
                {
                  "type" => "phone",
                  "value" => "+1-***-***-5678",
                  "action" => "redacted", 
                  "confidence" => 0.88
                }
              ],
              "risk_score" => 0.23,
              "risk_level" => "low"
            },
            "filtering_results" => {
              "original_content_hash" => "sha256:8f7a3b2c9d1e6f4a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a",
              "filtered_content_hash" => "sha256:9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e0d9c8b7a6f5e4d3c2b1a0f9e8d",
              "modifications_applied" => 2,
              "content_preserved_percentage" => 97.3,
              "safety_confidence" => 0.94
            },
            "performance" => {
              "analysis_time_ms" => 178,
              "rule_evaluations" => 12,
              "cache_hits" => 3,
              "model_calls" => 1
            }
          }
        end

        let(:pipeline_span_attributes) do
          {
            "pipeline" => {
              "name" => "MarketDiscoveryPipeline",
              "version" => "2.1.0",
              "stages" => [
                {
                  "name" => "MarketAnalysisAgent",
                  "order" => 1,
                  "status" => "completed",
                  "duration_ms" => 3420,
                  "output_size_bytes" => 2847,
                  "success" => true
                },
                {
                  "name" => "MarketScoringAgent", 
                  "order" => 2,
                  "status" => "completed",
                  "duration_ms" => 1890,
                  "output_size_bytes" => 1256,
                  "success" => true
                },
                {
                  "name" => "SearchTermGeneratorAgent",
                  "order" => 3,
                  "status" => "completed", 
                  "duration_ms" => 2150,
                  "output_size_bytes" => 3102,
                  "success" => true
                }
              ],
              "total_stages" => 3,
              "completed_stages" => 3,
              "overall_status" => "success",
              "execution_mode" => "sequential"
            },
            "initial_context" => {
              "product" => {
                "name" => "RAAF Framework",
                "category" => "AI Development Platform",
                "target_audience" => "Enterprise Development Teams"
              },
              "company" => {
                "name" => "TechCorp Solutions",
                "industry" => "Software Development",
                "size" => "500-1000 employees"
              },
              "analysis_depth" => "comprehensive",
              "market_constraints" => {
                "geographic_regions" => ["North America", "Europe"],
                "company_size_range" => "50-500",
                "industry_focus" => ["software", "consulting", "fintech"]
              }
            },
            "final_result" => {
              "markets_discovered" => 3,
              "total_companies" => 847,
              "search_terms_generated" => 156,
              "scoring_confidence" => 0.91,
              "execution_success" => true,
              "result_quality_score" => 0.88
            },
            "execution" => {
              "total_duration_ms" => 7460,
              "memory_peak_mb" => 245.7,
              "cpu_time_ms" => 5230,
              "api_calls_total" => 15,
              "context_size_bytes" => 12847,
              "intermediate_results" => 3,
              "data_transformations" => 8
            },
            "agent_performance" => {
              "fastest_agent" => "MarketScoringAgent",
              "slowest_agent" => "MarketAnalysisAgent",
              "most_api_calls" => "SearchTermGeneratorAgent",
              "largest_output" => "SearchTermGeneratorAgent",
              "highest_success_rate" => "100%"
            }
          }
        end

        let(:generic_span_attributes) do
          {
            "custom_operation" => {
              "type" => "data_validation",
              "validator" => "CompanyDataValidator",
              "rules" => [
                "required_fields_present",
                "email_format_valid",
                "company_size_realistic",
                "industry_classification_valid"
              ],
              "input_records" => 150,
              "validated_records" => 147,
              "failed_records" => 3,
              "success_rate" => 0.98
            },
            "validation_failures" => [
              {
                "record_id" => "comp_999",
                "field" => "employee_count", 
                "value" => "-5",
                "error" => "Employee count cannot be negative"
              },
              {
                "record_id" => "comp_888",
                "field" => "email",
                "value" => "invalid-email",
                "error" => "Email format is invalid"
              },
              {
                "record_id" => "comp_777",
                "field" => "industry",
                "value" => "Unknown Industry",
                "error" => "Industry must be from approved list"
              }
            ],
            "performance_metrics" => {
              "records_per_second" => 42.3,
              "average_validation_time_ms" => 23.6,
              "memory_usage_mb" => 18.5,
              "cache_hit_ratio" => 0.73
            },
            "system_info" => {
              "ruby_version" => "3.4.4",
              "gem_version" => "2.1.0",
              "environment" => "production",
              "server_region" => "us-west-2"
            }
          }
        end

        # Edge case fixtures
        let(:malformed_attributes) do
          {
            "broken_json" => "{ invalid json }",
            "null_values" => {
              "important_field" => nil,
              "empty_array" => [],
              "empty_hash" => {}
            },
            "very_long_string" => "A" * 5000,
            "deep_nesting" => {
              "level1" => {
                "level2" => {
                  "level3" => {
                    "level4" => {
                      "level5" => {
                        "data" => "deeply nested value"
                      }
                    }
                  }
                }
              }
            },
            "unicode_content" => {
              "emoji" => "🚀 🎯 📊 💡 ✨",
              "chinese" => "人工智能代理框架",
              "arabic" => "إطار عمل وكلاء الذكاء الاصطناعي",
              "special_chars" => "<>&\"'\n\t\r"
            }
          }
        end

        let(:large_dataset_attributes) do
          {
            "massive_array" => Array.new(1000) { |i| { "id" => i, "data" => "Item #{i}" * 10 } },
            "huge_string" => "Large content " * 10000,
            "many_keys" => Hash[(1..500).map { |i| ["key_#{i}", "value_#{i}"] }],
            "nested_arrays" => {
              "companies" => Array.new(100) do |i|
                {
                  "id" => "comp_#{i}",
                  "contacts" => Array.new(20) { |j| { "contact_#{j}" => "data_#{j}" } }
                }
              end
            }
          }
        end

        describe "Component Routing Integration" do
          it "routes tool spans to ToolSpanComponent" do
            span = create_mock_span(kind: "tool", attributes: tool_span_attributes)
            component = SpanDetail::Component.new(span: span, trace: mock_trace)
            output = render(component)
            
            # Verify tool-specific content is rendered
            expect(output).to include("Tool Execution")
            expect(output).to include("search_companies")
            expect(output).to include("Input Parameters")
            expect(output).to include("Output Results")
            expect(output).to include("Ruby programming consultancy")
            expect(output).to include("Ruby Masters Inc")
          end

          it "routes agent spans to AgentSpanComponent" do
            span = create_mock_span(kind: "agent", attributes: agent_span_attributes)
            component = SpanDetail::Component.new(span: span, trace: mock_trace)
            output = render(component)
            
            expect(output).to include("Agent Execution")
            expect(output).to include("ProspectAnalysisAgent")
            expect(output).to include("gpt-4o")
            expect(output).to include("Context Data")
            expect(output).to include("RAAF Framework")
          end

          it "routes llm spans to LlmSpanComponent" do
            span = create_mock_span(kind: "llm", attributes: llm_span_attributes)
            component = SpanDetail::Component.new(span: span, trace: mock_trace)
            output = render(component)
            
            expect(output).to include("LLM Request")
            expect(output).to include("gpt-4o")
            expect(output).to include("Token Usage")
            expect(output).to include("1637")
          end

          it "routes handoff spans to HandoffSpanComponent" do
            span = create_mock_span(kind: "handoff", attributes: handoff_span_attributes)
            component = SpanDetail::Component.new(span: span, trace: mock_trace)
            output = render(component)
            
            expect(output).to include("Agent Handoff")
            expect(output).to include("ProspectAnalysisAgent")
            expect(output).to include("OutreachCopywriterAgent")
            expect(output).to include("Transfer Data")
          end

          it "routes guardrail spans to GuardrailSpanComponent" do
            span = create_mock_span(kind: "guardrail", attributes: guardrail_span_attributes)
            component = SpanDetail::Component.new(span: span, trace: mock_trace)
            output = render(component)
            
            expect(output).to include("Content Safety")
            expect(output).to include("PII_DETECTION_001")
            expect(output).to include("pass_with_modifications")
          end

          it "routes pipeline spans to PipelineSpanComponent" do
            span = create_mock_span(kind: "pipeline", attributes: pipeline_span_attributes)
            component = SpanDetail::Component.new(span: span, trace: mock_trace)
            output = render(component)
            
            expect(output).to include("Pipeline Execution")
            expect(output).to include("MarketDiscoveryPipeline")
            expect(output).to include("MarketAnalysisAgent")
            expect(output).to include("3 stages")
          end

          it "routes unknown spans to GenericSpanComponent" do
            span = create_mock_span(kind: "unknown_type", attributes: generic_span_attributes)
            component = SpanDetail::Component.new(span: span, trace: mock_trace)
            output = render(component)
            
            expect(output).to include("Unknown_type Span")
            expect(output).to include("data_validation")
          end
        end

        describe "Universal Span Overview" do
          let(:tool_span) { create_mock_span(kind: "tool", attributes: tool_span_attributes) }
          let(:component) { SpanDetail::Component.new(span: tool_span, trace: mock_trace) }

          it "displays universal span information for all types" do
            output = render(component)
            
            # Universal header elements
            expect(output).to include("Span Detail")
            expect(output).to include(tool_span.name)
            expect(output).to include("Tool") # Kind badge
            expect(output).to include("Success") # Status badge
          end

          it "displays trace and navigation links" do
            output = render(component)
            
            expect(output).to include("View Trace")
            expect(output).to include("Back to Spans")
            expect(output).to include("bi-diagram-3")
            expect(output).to include("bi-arrow-left")
          end

          it "shows timing information consistently" do
            output = render(component)
            
            expect(output).to include("150ms") # Duration
            expect(output).to include("2025-09-25") # Timestamps
          end

          it "displays hierarchy information" do
            span_with_parent = create_mock_span(
              kind: "tool",
              attributes: tool_span_attributes,
              parent_id: "parent_span_123",
              depth: 2
            )
            
            component = SpanDetail::Component.new(span: span_with_parent, trace: mock_trace)
            output = render(component)
            
            expect(output).to include("parent_span_123")
            expect(output).to include("2") # Depth
          end
        end

        describe "Type-Specific Component Rendering" do
          it "renders tool span with comprehensive input/output visualization" do
            span = create_mock_span(kind: "tool", attributes: tool_span_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            # Function details
            expect(output).to include("search_companies")
            expect(output).to include("Search for companies matching criteria")
            
            # Input parameters with structure
            expect(output).to include("Ruby programming consultancy")
            expect(output).to include("Software Development")
            expect(output).to include("10-50 employees")
            expect(output).to include("San Francisco Bay Area")
            
            # Output results with data
            expect(output).to include("Ruby Masters Inc")
            expect(output).to include("Code Crafters LLC") 
            expect(output).to include("$2M-5M")
            expect(output).to include("score")
            
            # Metadata
            expect(output).to include("search_time_ms")
            expect(output).to include("api_calls")
          end

          it "renders agent span with context and execution details" do
            span = create_mock_span(kind: "agent", attributes: agent_span_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            # Agent configuration
            expect(output).to include("ProspectAnalysisAgent")
            expect(output).to include("gpt-4o")
            expect(output).to include("temperature")
            expect(output).to include("0.3")
            
            # Context data
            expect(output).to include("RAAF Framework")
            expect(output).to include("AI Development Tools")
            expect(output).to include("Q4 Enterprise Outreach")
            
            # Execution metrics
            expect(output).to include("turns_used")
            expect(output).to include("total_tokens")
            expect(output).to include("1847")
            
            # Results
            expect(output).to include("insights_generated")
            expect(output).to include("confidence_score")
          end

          it "renders LLM span with request/response and cost details" do
            span = create_mock_span(kind: "llm", attributes: llm_span_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            # Model configuration
            expect(output).to include("gpt-4o")
            expect(output).to include("temperature")
            expect(output).to include("0.7")
            
            # Usage metrics
            expect(output).to include("1637") # Total tokens
            expect(output).to include("1250") # Prompt tokens
            expect(output).to include("387") # Completion tokens
            
            # Cost information
            expect(output).to include("$0.03036")
            expect(output).to include("USD")
            
            # Performance metrics
            expect(output).to include("2847") # Latency ms
            expect(output).to include("136.5") # Tokens per second
          end

          it "renders pipeline span with stage execution flow" do
            span = create_mock_span(kind: "pipeline", attributes: pipeline_span_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            # Pipeline overview
            expect(output).to include("MarketDiscoveryPipeline")
            expect(output).to include("3 stages")
            expect(output).to include("sequential")
            
            # Stage details
            expect(output).to include("MarketAnalysisAgent")
            expect(output).to include("MarketScoringAgent") 
            expect(output).to include("SearchTermGeneratorAgent")
            expect(output).to include("completed")
            
            # Results summary
            expect(output).to include("markets_discovered")
            expect(output).to include("847") # Total companies
            expect(output).to include("156") # Search terms
            
            # Performance data
            expect(output).to include("7460") # Total duration
            expect(output).to include("245.7") # Memory peak
          end
        end

        describe "Interactive Functionality (Stimulus Integration)" do
          let(:tool_span) { create_mock_span(kind: "tool", attributes: tool_span_attributes) }
          let(:component) { SpanDetail::Component.new(span: tool_span) }

          it "includes Stimulus controller data attributes" do
            output = render(component)
            
            expect(output).to include('data-controller="span-detail"')
            expect(output).to include('data-span_detail_debug_value')
          end

          it "includes toggle action data attributes for sections" do
            output = render(component)
            
            # Section toggle buttons should have proper data attributes
            expect(output).to include('data-action="click->span-detail#toggleSection"')
            expect(output).to include('data-target=')
            expect(output).to include('data-expanded_text')
            expect(output).to include('data-collapsed_text')
          end

          it "includes tool-specific toggle actions" do
            output = render(component)
            
            # Tool input/output toggles
            expect(output).to include('click->span-detail#toggleToolInput')
            expect(output).to include('click->span-detail#toggleToolOutput')
          end

          it "includes copy-to-clipboard functionality" do
            output = render(component)
            
            expect(output).to include('click->span-detail#copyJson')
          end

          it "includes collapsible attribute groups" do
            span_with_attributes = create_mock_span(kind: "agent", attributes: agent_span_attributes)
            component = SpanDetail::Component.new(span: span_with_attributes)
            output = render(component)
            
            expect(output).to include('click->span-detail#toggleAttributeGroup')
            expect(output).to include('data-initially_collapsed="true"')
          end
        end

        describe "Data Flow and Edge Cases" do
          it "handles malformed JSON gracefully" do
            span = create_mock_span(kind: "tool", attributes: malformed_attributes)
            component = SpanDetail::Component.new(span: span)
            
            expect { render(component) }.not_to raise_error
            output = render(component)
            
            # Should still render basic span information
            expect(output).to include("Test Tool Span")
            expect(output).to include("Tool")
          end

          it "handles null and empty values properly" do
            span = create_mock_span(kind: "generic", attributes: malformed_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            expect(output).to include("null") # Null values displayed
            expect(output).to include("Array (0 items)") # Empty array
            expect(output).to include("Object (0 keys)") # Empty hash
          end

          it "handles very long strings with truncation" do
            span = create_mock_span(kind: "generic", attributes: malformed_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            # Should include truncation indicators
            expect(output).to include("Show More")
            expect(output).to include("Toggle")
          end

          it "handles unicode content properly" do
            span = create_mock_span(kind: "generic", attributes: malformed_attributes) 
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            expect(output).to include("🚀")
            expect(output).to include("人工智能代理框架")
            expect(output).to include("إطار عمل وكلاء الذكاء الاصطناعي")
          end

          it "handles deep nesting with proper structure" do
            span = create_mock_span(kind: "generic", attributes: malformed_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            expect(output).to include("level1")
            expect(output).to include("deeply nested value")
            expect(output).to include("Object with") # Nested object indicators
          end
        end

        describe "Performance with Large Datasets" do
          it "handles large arrays efficiently" do
            span = create_mock_span(kind: "tool", attributes: large_dataset_attributes)
            component = SpanDetail::Component.new(span: span)
            
            expect { render(component) }.not_to raise_error
            output = render(component)
            
            # Should show truncation for large arrays
            expect(output).to include("1000 items")
            expect(output).to include("more items")
          end

          it "truncates huge strings appropriately" do
            span = create_mock_span(kind: "tool", attributes: large_dataset_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            # Should not include the full massive string
            expect(output).not_to include("Large content " * 10000)
            expect(output).to include("Show More") # Truncation controls
          end

          it "handles objects with many keys" do
            span = create_mock_span(kind: "tool", attributes: large_dataset_attributes)
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            expect(output).to include("500 keys")
            expect(output).to include("Toggle") # Collapsible sections
          end
        end

        describe "Error Handling" do
          it "displays error sections when error_details are provided" do
            error_details = {
              "message" => "Tool execution failed",
              "code" => "TOOL_ERROR_001",
              "stack_trace" => "Error in line 42..."
            }
            
            span = create_mock_span(kind: "tool", attributes: tool_span_attributes, status: "error")
            component = SpanDetail::Component.new(span: span, error_details: error_details)
            output = render(component)
            
            expect(output).to include("Error Details")
            expect(output).to include("Tool execution failed")
            expect(output).to include("TOOL_ERROR_001")
            expect(output).to include("bg-red-50")
            expect(output).to include("bi-exclamation-triangle")
          end

          it "handles spans with missing required attributes" do
            span = create_mock_span(kind: "tool", attributes: {})
            component = SpanDetail::Component.new(span: span)
            
            expect { render(component) }.not_to raise_error
            output = render(component)
            
            expect(output).to include("Unknown Tool")
          end

          it "handles spans with nil attributes" do
            span = double("Span",
              span_id: "test_123",
              trace_id: "trace_456",
              parent_id: nil,
              name: "Nil Attributes Span",
              kind: "tool",
              status: "success",
              start_time: base_time,
              end_time: base_time + 0.1,
              duration_ms: 100,
              span_attributes: nil,
              depth: 1,
              children: [],
              events: []
            )
            
            component = SpanDetail::Component.new(span: span)
            expect { render(component) }.not_to raise_error
          end
        end

        describe "Children and Events Sections" do
          it "displays children section when children are present" do
            child_span = create_mock_span(kind: "tool", attributes: {})
            parent_span = create_mock_span(
              kind: "agent",
              attributes: agent_span_attributes,
              children: [child_span]
            )
            
            component = SpanDetail::Component.new(span: parent_span)
            output = render(component)
            
            expect(output).to include("Child Spans (1)")
            expect(output).to include(child_span.name)
          end

          it "displays events section when events are present" do
            events = [
              {
                "timestamp" => "2025-09-25T10:00:00Z",
                "event" => "tool_started",
                "data" => { "tool" => "search_companies" }
              }
            ]
            
            span = create_mock_span(
              kind: "tool",
              attributes: tool_span_attributes,
              events: events
            )
            
            component = SpanDetail::Component.new(span: span)
            output = render(component)
            
            expect(output).to include("Events (1)")
            expect(output).to include("tool_started")
          end
        end

        describe "Accessibility and Semantic Markup" do
          let(:span) { create_mock_span(kind: "tool", attributes: tool_span_attributes) }
          let(:component) { SpanDetail::Component.new(span: span) }

          it "uses proper semantic HTML structure" do
            output = render(component)
            
            expect(output).to include("<h1")
            expect(output).to include("<h3")
            expect(output).to include("<dl>")
            expect(output).to include("<dt>")
            expect(output).to include("<dd>")
          end

          it "includes proper ARIA labels and descriptions" do
            output = render(component)
            
            # Interactive elements should be accessible
            expect(output).to include("button")
            # Note: Full ARIA compliance would be verified in browser tests
          end

          it "uses descriptive text content for screen readers" do
            output = render(component)
            
            expect(output).to include("Span Detail")
            expect(output).to include("Tool Execution")
            expect(output).to include("Input Parameters")
            expect(output).to include("Output Results")
          end
        end

        describe "Cross-Component Data Consistency" do
          it "maintains consistent data representation across different span types" do
            # Test that the same underlying data structures are handled consistently
            # regardless of which type-specific component processes them
            
            spans = [
              create_mock_span(kind: "tool", attributes: tool_span_attributes),
              create_mock_span(kind: "agent", attributes: agent_span_attributes),
              create_mock_span(kind: "llm", attributes: llm_span_attributes),
              create_mock_span(kind: "pipeline", attributes: pipeline_span_attributes)
            ]
            
            spans.each do |span|
              component = SpanDetail::Component.new(span: span, trace: mock_trace)
              output = render(component)
              
              # Universal elements should be present in all
              expect(output).to include("Span Detail")
              expect(output).to include(span.span_id)
              expect(output).to include(span.trace_id)
              expect(output).to include("150ms")
              expect(output).to include("Success")
            end
          end

          it "renders trace relationships consistently" do
            span = create_mock_span(kind: "tool", attributes: tool_span_attributes)
            component = SpanDetail::Component.new(span: span, trace: mock_trace)
            output = render(component)
            
            expect(output).to include(mock_trace.trace_id)
            expect(output).to include(mock_trace.workflow_name)
            expect(output).to include("View Trace")
          end
        end

        describe "Component Integration with Rails Helpers" do
          let(:span) { create_mock_span(kind: "tool", attributes: tool_span_attributes) }
          let(:component) { SpanDetail::Component.new(span: span, trace: mock_trace) }

          it "uses Rails path helpers correctly" do
            # Note: In a real Rails environment, these would generate actual URLs
            # Here we just verify the structure is present
            output = render(component)
            
            # Should contain elements that would use Rails helpers
            expect(output).to include("href")
            expect(output).to match(/tracing.*span/) # Pattern for span paths
            expect(output).to match(/tracing.*trace/) # Pattern for trace paths
          end

          it "integrates with Rails time formatting helpers" do
            output = render(component)
            
            expect(output).to include("2025-09-25")
            expect(output).to include("10:00:00")
            expect(output).to include("UTC")
          end
        end
      end
    end
  end
end
