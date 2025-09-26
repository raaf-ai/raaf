# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanDetail::GuardrailSpanComponent, type: :component do
  let(:base_span_attributes) do
    {
      "span_id" => "span_123",
      "trace_id" => "trace_456",
      "name" => "SecurityFilter",
      "kind" => "guardrail",
      "status" => "success"
    }
  end

  let(:span) { double("SpanRecord", **base_span_attributes, span_attributes: span_attributes) }
  let(:component) { described_class.new(span: span) }

  describe "#view_template" do
    context "with comprehensive guardrail data" do
      let(:span_attributes) do
        {
          "guardrail" => {
            "filter_name" => "ContentSecurityFilter",
            "status" => "blocked",
            "results" => {
              "pii_check" => {
                "status" => "fail",
                "score" => 0.85,
                "details" => "Personal information detected in content"
              },
              "toxicity_check" => {
                "status" => "pass",
                "score" => 0.12,
                "details" => "Content within acceptable toxicity levels"
              },
              "profanity_check" => {
                "status" => "warn",
                "score" => 0.45,
                "details" => "Mild profanity detected"
              }
            },
            "reasoning" => "Content blocked due to PII detection. The system identified potential personal information including email addresses and phone numbers.",
            "policy" => {
              "name" => "Enterprise Security Policy v2.1",
              "applied_rules" => ["pii_protection", "toxicity_filter"],
              "threshold" => 0.8,
              "action" => "block"
            },
            "blocked_content" => {
              "original_length" => 456,
              "sanitized" => true,
              "blocked_sections" => ["email: john@example.com", "phone: 555-0123"]
            }
          }
        }
      end

      it "renders guardrail overview with security status" do
        render_inline(component)
        
        expect(rendered_component).to have_css(".bg-orange-50")
        expect(rendered_component).to have_css(".bi-shield-exclamation")
        expect(rendered_component).to have_content("Security Guardrail")
        expect(rendered_component).to have_content("Filter: ContentSecurityFilter")
        expect(rendered_component).to have_content("Status: blocked")
        expect(rendered_component).to have_content("Policy: Enterprise Security Policy v2.1")
      end

      it "renders security status badge with correct color" do
        render_inline(component)
        
        # Should have blocked status badge in red
        expect(rendered_component).to have_css(".bg-red-100.text-red-800")
        expect(rendered_component).to have_content("Blocked")
      end

      it "renders filter results table with all checks" do
        render_inline(component)
        
        # Should have filter results section
        expect(rendered_component).to have_css("#filter-results-content")
        expect(rendered_component).to have_content("Filter Results")
        
        # Should show table with check results
        expect(rendered_component).to have_content("Pii Check")
        expect(rendered_component).to have_content("Toxicity Check")
        expect(rendered_component).to have_content("Profanity Check")
        
        # Should show scores and statuses
        expect(rendered_component).to have_content("85.0%")
        expect(rendered_component).to have_content("12.0%")
        expect(rendered_component).to have_content("45.0%")
        expect(rendered_component).to have_content("FAIL")
        expect(rendered_component).to have_content("PASS")
        expect(rendered_component).to have_content("WARN")
      end

      it "renders security reasoning section" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#security-reasoning-content")
        expect(rendered_component).to have_content("Security Reasoning")
        expect(rendered_component).to have_content("Content blocked due to PII detection")
        expect(rendered_component).to have_content("email addresses and phone numbers")
      end

      it "renders policy details section" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#policy-details-content")
        expect(rendered_component).to have_content("Policy Applied")
        expect(rendered_component).to have_content("Enterprise Security Policy v2.1")
        expect(rendered_component).to have_content("pii_protection")
        expect(rendered_component).to have_content("toxicity_filter")
      end

      it "renders blocked content section (initially collapsed)" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#blocked-content-content.hidden")
        expect(rendered_component).to have_content("Blocked Content")
        expect(rendered_component).to have_css(".bg-red-50")
      end

      it "includes expand/collapse functionality" do
        render_inline(component)
        
        # Should have stimulus controller
        expect(rendered_component).to have_css("[data-controller='span-detail']")
        
        # Should have toggle buttons
        expect(rendered_component).to have_css("[data-action='click->span-detail#toggleSection']")
        expect(rendered_component).to have_css(".toggle-icon")
      end
    end

    context "with minimal guardrail data" do
      let(:span_attributes) do
        {
          "filter" => {
            "name" => "BasicFilter",
            "status" => "allowed"
          }
        }
      end

      it "renders basic guardrail information" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Security Guardrail")
        expect(rendered_component).to have_content("Filter: BasicFilter")
        expect(rendered_component).to have_content("Status: allowed")
        expect(rendered_component).to have_css(".bg-green-100.text-green-800")
      end

      it "does not render empty sections" do
        render_inline(component)
        
        expect(rendered_component).not_to have_css("#filter-results-content")
        expect(rendered_component).not_to have_css("#security-reasoning-content")
        expect(rendered_component).not_to have_css("#policy-details-content")
      end
    end

    context "with malformed guardrail data" do
      let(:span_attributes) do
        {
          "guardrail" => {
            "results" => "invalid_data",
            "reasoning" => nil,
            "policy" => []
          }
        }
      end

      it "handles invalid data gracefully" do
        expect { render_inline(component) }.not_to raise_error
        
        expect(rendered_component).to have_content("Security Guardrail")
        expect(rendered_component).to have_content("Filter: Unknown Filter")
      end
    end

    context "with no guardrail data" do
      let(:span_attributes) { {} }

      it "renders basic guardrail information with defaults" do
        render_inline(component)
        
        expect(rendered_component).to have_content("Security Guardrail")
        expect(rendered_component).to have_content("Filter: Unknown Filter")
        expect(rendered_component).to have_content("Status: success")
        expect(rendered_component).to have_content("Policy: Default")
      end
    end

    context "with different security statuses" do
      %w[blocked denied allowed passed flagged warning].each do |status|
        context "when status is #{status}" do
          let(:span_attributes) do
            {
              "guardrail" => {
                "status" => status
              }
            }
          end

          it "renders appropriate status badge color" do
            render_inline(component)
            
            case status
            when "blocked", "denied"
              expect(rendered_component).to have_css(".bg-red-100.text-red-800")
            when "allowed", "passed"
              expect(rendered_component).to have_css(".bg-green-100.text-green-800")
            when "flagged", "warning"
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
        "guardrail" => {
          "filter_name" => "TestFilter",
          "status" => "blocked",
          "results" => { "test" => "result" },
          "reasoning" => "Test reasoning",
          "policy" => { "name" => "Test Policy" },
          "blocked_content" => { "content" => "blocked" }
        }
      }
    end

    it "extracts filter name correctly" do
      expect(component.send(:filter_name)).to eq("TestFilter")
    end

    it "extracts filter status correctly" do
      expect(component.send(:filter_status)).to eq("blocked")
    end

    it "extracts filter results correctly" do
      expect(component.send(:filter_results)).to eq({ "test" => "result" })
    end

    it "extracts security reasoning correctly" do
      expect(component.send(:security_reasoning)).to eq("Test reasoning")
    end

    it "extracts policy applied correctly" do
      expect(component.send(:policy_applied)).to eq({ "name" => "Test Policy" })
    end

    it "extracts blocked content correctly" do
      expect(component.send(:blocked_content)).to eq({ "content" => "blocked" })
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

    context "when RAAF_DEBUG is enabled" do
      let(:span_attributes) { { "some" => "data" } }

      around do |example|
        old_debug = ENV["RAAF_DEBUG"]
        ENV["RAAF_DEBUG"] = "true"
        example.run
        ENV["RAAF_DEBUG"] = old_debug
      end

      it "shows debug raw attributes section" do
        render_inline(component)
        
        expect(rendered_component).to have_css("#raw-attributes-content")
        expect(rendered_component).to have_content("Debug: Raw Attributes")
      end
    end
  end
end