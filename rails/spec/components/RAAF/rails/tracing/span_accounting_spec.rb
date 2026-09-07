# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/object/blank"

require_relative "../../../../../app/components/RAAF/rails/tracing/span_accounting"

module RAAF
  module Rails
    module Tracing
      RSpec.describe SpanAccounting do
        # The module is private API on the two inspector components; this
        # exposes it so the billing rules can be tested without rendering
        # either of them.
        let(:probe_class) do
          Class.new do
            include RAAF::Rails::Tracing::SpanAccounting

            public(*RAAF::Rails::Tracing::SpanAccounting.private_instance_methods(false))
          end
        end

        let(:probe) { probe_class.new }

        # Only the accessors SpanUsage reads. The native token columns are
        # nil here on purpose: a span written before they existed falls
        # through to its attributes, and that is the path worth covering.
        let(:span_class) do
          Struct.new(:span_id, :kind, :span_attributes, keyword_init: true) do
            def input_tokens = nil
            def output_tokens = nil
            def total_tokens = nil
            def agent_model = nil
          end
        end

        # A fresh id per span: the module memoises a span's usage by id, the
        # way both inspectors reach for it several times over one render.
        let(:span) do
          ids = (1..).each
          ->(kind, attrs) { span_class.new(span_id: "s#{ids.next}", kind: kind, span_attributes: attrs) }
        end
        let(:labels) { ->(rows) { rows.map { |row| row[:label] } } }
        let(:value_of) { ->(rows, label) { rows.find { |row| row[:label] == label }&.fetch(:value) } }

        describe "spans priced per token" do
          let(:llm) do
            span.call("llm",
                      "llm.usage.input_tokens" => 1000,
                      "llm.usage.output_tokens" => 500,
                      "llm.usage.total_tokens" => 1500,
                      "llm.request.model" => "gpt-4o")
          end

          it "bills them in tokens" do
            expect(probe.accounting_mode(llm)).to eq(:tokens)
            expect(probe.accounting_label(llm)).to eq("Tokens & cost")
          end

          it "reads usage the span recorded under any of its key shapes" do
            expect(value_of.call(probe.accounting_rows(llm), "Total tokens")).to eq("1.5k")
          end

          it "splits the cost the way the provider bills it" do
            rows = probe.accounting_rows(llm)

            expect(labels.call(rows)).to eq(
              ["Model", "Input tokens", "Output tokens", "Total tokens",
               "Input cost", "Output cost", "Total cost"]
            )
          end

          # Gemini 2.5 bills thinking tokens at the output rate but reports
          # them only as the gap between the total and input + output.
          it "names the tokens a provider billed without itemising" do
            gemini = span.call("llm",
                               "llm.usage.input_tokens" => 2832,
                               "llm.usage.output_tokens" => 1569,
                               "llm.usage.total_tokens" => 5747,
                               "llm.request.model" => "gemini-2.5-flash")

            expect(value_of.call(probe.accounting_rows(gemini), "Thinking tokens")).to eq("1.3k")
          end

          # Nil is not zero: three rows of "—" would say the same thing three
          # times, and $0.000 would say something false.
          it "reports one unknown cost for a model with no pricing" do
            local = span.call("llm", "input_tokens" => 10, "output_tokens" => 5,
                                     "agent.model" => "some-local-model")
            rows = probe.accounting_rows(local)

            expect(labels.call(rows).last(1)).to eq(["Cost"])
            expect(value_of.call(rows, "Cost")).to eq("—")
          end

          it "reports nothing at all for a span that consumed none" do
            expect(probe.accounting_rows(span.call("tool", "tool_arguments" => "{}"))).to be_empty
          end

          it "appends the caller's own rows to a span that has something to say" do
            extra = [{ label: "Trace cost", value: "$1.000" }]

            expect(labels.call(probe.accounting_rows(llm, extra: extra))).to include("Trace cost")
            expect(probe.accounting_rows(span.call("tool", {}), extra: extra)).to be_empty
          end
        end

        describe "spans priced per call" do
          let(:search) do
            span.call("component",
                      "component.type" => "search", "provider" => "tavily",
                      "cost_cents" => 0.5, "query" => "acme")
          end

          it "bills them in cost alone" do
            expect(probe.accounting_mode(search)).to eq(:cost)
            expect(probe.accounting_label(search)).to eq("Cost")
            expect(labels.call(probe.accounting_rows(search))).to eq(%w[Provider Cost])
          end

          it "reads the flat fee the search component recorded" do
            expect(value_of.call(probe.accounting_rows(search), "Cost")).to eq("$0.005")
          end

          # A search span carrying tokens is a provider that answers with a
          # model — Perplexity — and its charge is still what belongs here.
          it "prices a token-backed search off its model" do
            perplexity = span.call("component",
                                   "component.type" => "search",
                                   "provider" => "perplexity",
                                   "input_tokens" => 1000, "output_tokens" => 500,
                                   "agent.model" => "gpt-4o")
            rows = probe.accounting_rows(perplexity)

            expect(labels.call(rows)).to eq(%w[Provider Cost])
            expect(value_of.call(rows, "Cost")).not_to eq("—")
          end

          it "names the component when no provider attribute was set" do
            brave = span.call("component", "component.type" => "search",
                                           "component.name" => "Search::BraveProvider")

            expect(value_of.call(probe.accounting_rows(brave), "Provider")).to eq("BraveProvider")
          end

          it "says so rather than guessing when nobody recorded a charge" do
            bare = span.call("search", "query" => "acme")

            expect(value_of.call(probe.accounting_rows(bare), "Cost")).to eq("—")
          end
        end

        describe "spans that are not billed" do
          let(:job) { span.call("job", "job.class" => "EnrichJob", "job.arguments" => "[]") }

          it "gives a job no accounting of its own" do
            expect(probe.accounting_mode(job)).to eq(:none)
            expect(probe.accounting_label(job)).to be_nil
            expect(probe.accounting_rows(job)).to be_empty
          end

          it "leaves it out of a summary bar rather than reporting a zero" do
            expect(probe.accounting_stat(job)).to be_nil
            expect(probe.accounting_meta(job)).to be_nil
          end
        end

        describe "#billed_in_tokens?" do
          it "lets a caller keep a token total away from a cost-only panel" do
            search = span.call("component", "component.type" => "search", "cost_cents" => 1)
            job = span.call("job", "job.class" => "EnrichJob")
            llm = span.call("llm", "total_tokens" => 100, "agent.model" => "gpt-4o")

            expect(probe.billed_in_tokens?(search)).to be(false)
            expect(probe.billed_in_tokens?(job)).to be(false)
            expect(probe.billed_in_tokens?(llm)).to be(true)
          end
        end

        describe "#accounting_stat" do
          it "headlines a token-priced span with its token count" do
            llm = span.call("llm", "total_tokens" => 5747, "agent.model" => "gpt-4o")

            expect(probe.accounting_stat(llm))
              .to eq(icon: "coin", label: "tokens", value: "5.7k")
          end

          it "headlines a per-call span with its charge" do
            search = span.call("search", "cost_cents" => 1)

            expect(probe.accounting_stat(search))
              .to eq(icon: "cash", label: "cost", value: "$0.010")
          end
        end
      end
    end
  end
end
