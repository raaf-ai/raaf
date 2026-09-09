# frozen_string_literal: true

require "spec_helper"
require "json"
require "active_support/core_ext/object/blank"

require_relative "../../../../../app/components/RAAF/rails/tracing/payload_tabs"

module RAAF
  module Rails
    module Tracing
      RSpec.describe PayloadTabs do
        # The module is private API on the two inspector components; this
        # exposes it so the tab logic can be tested without rendering either.
        let(:subject_class) do
          Class.new do
            include RAAF::Rails::Tracing::PayloadTabs

            def messages(attrs)
              payload_messages_from(attrs)
            end

            def tabs(messages, accounting: "Tokens & cost", error: false)
              payload_tab_definitions(messages, accounting: accounting, error: error)
            end
          end
        end

        let(:tabs_for) do
          lambda do |attrs, accounting: "Tokens & cost", error: false|
            probe = subject_class.new
            probe.tabs(probe.messages(attrs), accounting: accounting, error: error).map { |tab| tab[:id] }
          end
        end
        let(:messages_for) { ->(attrs) { subject_class.new.messages(attrs) } }

        describe "the shapes RAAF's own processors write" do
          it "gives each recorded section its own tab, in reading order" do
            attrs = { "instructions" => "be brief", "input" => "hello", "output" => "hi" }

            expect(tabs_for.call(attrs)).to eq(%w[system prompt response tokens raw])
          end

          it "offers a single Payload tab for a span that recorded nothing" do
            expect(tabs_for.call({})).to eq(%w[payload tokens raw])
          end
        end

        describe "search spans" do
          let(:attrs) do
            { "component.type" => "search",
              "query" => "acme latex importers",
              "result_count" => 2,
              "result.0.title" => "Acme BV", "result.0.url" => "https://example.com/acme",
              "result.0.snippet" => "Importer of latex goods", "result.0.score" => 0.82,
              "result.1.title" => "Acme profile", "result.1.url" => "https://example.com/profile" }
          end

          it "shows the query and the hits as tabs of their own" do
            # `result_count` matches no section and is not part of the frame,
            # so it lands in Attributes -- which is where anything the other
            # tabs do not name belongs.
            expect(tabs_for.call(attrs)).to eq(%w[query results attributes tokens raw])
          end

          it "keeps the accounting tab's id when the panel is renamed for it" do
            tabs = subject_class.new.tabs(subject_class.new.messages(attrs), accounting: "Cost")

            expect(tabs.find { |tab| tab[:id] == "tokens" }[:label]).to eq("Cost")
          end

          it "folds the indexed attributes back into ranked rows" do
            results = messages_for.call(attrs).find { |message| message[:results] }[:results]

            expect(results).to eq(
              [{ title: "Acme BV", url: "https://example.com/acme",
                 score: 0.82, snippet: "Importer of latex goods" },
               { title: "Acme profile", url: "https://example.com/profile",
                 score: nil, snippet: nil }]
            )
          end

          it "joins a snippets list when that is all the provider wrote" do
            results = messages_for.call(
              "result.0.url" => "https://example.com",
              "result.0.snippets" => %w[first second]
            ).find { |message| message[:results] }[:results]

            expect(results.first[:snippet]).to eq("first … second")
          end

          it "stops at the first empty position rather than scanning past a gap" do
            results = messages_for.call(
              "result.0.title" => "kept", "result.2.title" => "unreachable"
            ).find { |message| message[:results] }[:results]

            expect(results.map { |hit| hit[:title] }).to eq(["kept"])
          end

          it "leaves the query unmasked, so the tab it opens on is readable" do
            query = messages_for.call(attrs).find { |message| message[:id] == "query" }

            expect(query[:masked]).to be(false)
          end
        end

        describe "the conversation a span recorded" do
          # A DSL agent, which is what the collector in tracing/ writes for
          # every agent built with the DSL: no `agent.system_instructions`
          # anywhere, so the system prompt the provider was actually sent
          # exists only inside the transcript.
          let(:transcript) do
            [{ "role" => "system", "content" => "Name: Filter\nInstructions: be brief" },
             { "role" => "user", "content" => "## Product\nBryxx" },
             { "role" => "assistant", "content" => '{"scored":[]}' }]
          end
          let(:attrs) do
            { "agent.conversation_messages" => JSON.generate(transcript),
              "agent.initial_user_prompt" => "## Product\nBryxx",
              "agent.final_agent_response" => '{"scored":[]}',
              "agent.conversation_stats" => '{"total_messages":3}' }
          end

          it "gives the transcript a tab of its own" do
            expect(tabs_for.call(attrs)).to eq(%w[prompt response conversation attributes tokens raw])
          end

          # It used to land in Attributes, where a 7kB line of JSON was both
          # the first row of that tab and the only place this span's system
          # prompt appeared.
          it "takes the transcript out of the Attributes tab" do
            pairs = messages_for.call(attrs).find { |message| message[:id] == "attributes" }[:pairs]

            expect(pairs.keys).to eq(["agent.conversation_stats"])
          end

          it "names the tab once however many messages it holds" do
            blocks = messages_for.call(attrs).select { |message| message[:id] == "conversation" }

            expect(blocks.map { |block| block[:role] }).to eq(%w[system user assistant])
          end

          it "veils what was asked and leaves what was said open" do
            blocks = messages_for.call(attrs).select { |message| message[:id] == "conversation" }

            expect(blocks.map { |block| block[:masked] }).to eq([false, true, false])
          end

          # The turns between the first user message and the last assistant
          # one are recorded nowhere else: `agent.initial_user_prompt` and
          # `agent.final_agent_response` are the two ends of the run, and
          # `agent.tool_executions` names the calls without their ordering.
          it "shows a tool loop's calls and results in the order they happened" do
            loop_attrs = { "agent.conversation_messages" => JSON.generate(
              [{ "role" => "user", "content" => "weather in Tokyo?" },
               { "role" => "assistant", "content" => "Looking.",
                 "tool_calls" => [{ "id" => "c1",
                                    "function" => { "name" => "get_weather", "arguments" => "{}" } }] },
               { "role" => "tool", "name" => "get_weather", "content" => "sunny" },
               { "role" => "assistant", "content" => "Sunny." }]
            ) }

            roles = messages_for.call(loop_attrs).map { |message| message[:role] }

            expect(roles).to eq(["user", "assistant", "assistant · tool calls",
                                 "tool · get_weather", "assistant"])
          end

          it "offers no tab for a span that recorded an empty transcript" do
            expect(tabs_for.call({ "agent.conversation_messages" => "[]", "input" => "hi" }))
              .to eq(%w[prompt tokens raw])
          end

          # Claimed even then, because "[]" as an Attributes row says nothing.
          it "keeps an empty transcript out of the Attributes tab too" do
            expect(messages_for.call("agent.conversation_messages" => "[]", "input" => "hi")
                     .none? { |message| message[:id] == "attributes" }).to be(true)
          end

          # Truncation is a real failure mode here -- the collector writes the
          # whole conversation as one attribute, and a storage cap cuts it
          # mid-object. Dropping it from Attributes as well would take it off
          # the screen entirely.
          it "leaves a transcript that does not parse in the Attributes tab" do
            pairs = messages_for.call("agent.conversation_messages" => '[{"role":"user","cont')
                                .find { |message| message[:id] == "attributes" }[:pairs]

            expect(pairs.keys).to eq(["agent.conversation_messages"])
          end

          it "reads the bare key a hand-rolled tracer writes" do
            expect(tabs_for.call({ "conversation_messages" => JSON.generate(transcript) }))
              .to eq(%w[conversation tokens raw])
          end
        end

        # The guardrail renderer that used to serve these spans read them from
        # the span page, which no longer exists. Its vocabulary moves here so
        # the inspector names the filter's verdict rather than leaving it to be
        # picked out of a list of raw attributes.
        describe "guardrail spans" do
          it "names what the filter decided rather than listing raw attributes" do
            attrs = { "guardrail.name" => "pii_filter",
                      "guardrail.triggered" => true,
                      "guardrail.reasoning" => "matched an IBAN" }

            expect(tabs_for.call(attrs)).to eq(%w[guardrail tokens raw])
          end

          # The one attribute a guardrail span can hold customer data in. A
          # pairs row has no veil, so it stays where it already is rather than
          # being named on a tab that would publish it.
          it "leaves the blocked content in the Attributes tab" do
            attrs = { "guardrail.name" => "pii_filter",
                      "guardrail.blocked_content" => "NL91 ABNA 0417 1643 00" }

            expect(tabs_for.call(attrs)).to eq(%w[guardrail attributes tokens raw])
          end

          it "reads a filter that recorded nothing but its verdict" do
            pairs = messages_for.call("guardrail.name" => "pii_filter",
                                      "guardrail.triggered" => false).first[:pairs]

            expect(pairs).to eq("Guardrail" => "pii_filter", "Triggered" => "false")
          end

          # A guardrail that passed writes `false`, which is the answer the
          # reader came for. Dropping it would leave the tab saying only which
          # filter ran.
          it "keeps the guardrail attributes out of the Attributes tab" do
            attrs = { "guardrail.name" => "pii_filter", "guardrail.triggered" => false,
                      "ted.query" => "acme" }

            expect(tabs_for.call(attrs)).to eq(%w[guardrail attributes tokens raw])
            pairs = messages_for.call(attrs).find { |m| m[:id] == "attributes" }[:pairs]
            expect(pairs.keys).to eq(["ted.query"])
          end
        end

        describe "spans whose vocabulary has no section" do
          let(:attrs) do
            { "http.url" => "https://api.example.com/v3/notices/search",
              "ted.query" => 'winner-name~("CLS-Tex")',
              "ted.notice_count" => 4,
              "component.name" => nil }
          end

          it "shows the attributes rather than claiming the span is empty" do
            # `http.url` is the Request tab's, so this span is read as a call
            # it made plus the vocabulary only it uses.
            expect(tabs_for.call(attrs)).to eq(%w[request attributes tokens raw])
          end

          it "sorts the pairs and drops the blank ones" do
            pairs = messages_for.call(attrs).find { |message| message[:id] == "attributes" }[:pairs]

            expect(pairs.keys).to eq(["ted.notice_count", "ted.query"])
          end

          # The tab used to be a last resort, offered only to a span that
          # matched nothing at all -- which meant a span that matched one
          # section was treated as fully shown while the rest of what it
          # recorded stayed legible only as Raw JSON.
          it "holds what the other tabs did not name, beside them" do
            expect(tabs_for.call({ "output" => "done", "ted.query" => "acme" }))
              .to eq(%w[response attributes tokens raw])
          end

          it "is absent when every attribute is already named by another tab" do
            expect(tabs_for.call({ "instructions" => "be brief", "output" => "done" }))
              .to eq(%w[system response tokens raw])
          end

          # The header prints the duration and the kind, the accounting tab
          # prints the token counts, and the title prints the name. Repeating
          # them here would be a second copy of the frame around the panel.
          it "leaves out what the inspector already shows outside the payload" do
            attrs = { "output" => "done", "duration_ms" => 1234, "total_tokens" => 99,
                      "component.type" => "agent", "agent.name" => "Researcher" }

            expect(tabs_for.call(attrs)).to eq(%w[response tokens raw])
          end
        end

        describe "a value the tracer recorded as a line of JSON" do
          it "prints a response format with its structure showing" do
            schema = '{"type":"json_schema","json_schema":{"name":"scored","strict":true}}'
            pairs = messages_for.call("agent.response_format" => schema).first[:pairs]

            expect(pairs["Response format"]).to eq(<<~JSON.chomp)
              {
                "type": "json_schema",
                "json_schema": {
                  "name": "scored",
                  "strict": true
                }
              }
            JSON
          end

          it "leaves text that only looks like JSON exactly as it was recorded" do
            body = messages_for.call("output" => "{ not json, just a brace").first[:body]

            expect(body).to eq("{ not json, just a brace")
          end

          it "leaves a plain sentence alone" do
            body = messages_for.call("output" => "all done").first[:body]

            expect(body).to eq("all done")
          end
        end

        describe "a span that is not billed at all" do
          it "is offered no accounting tab" do
            expect(tabs_for.call({ "job.arguments" => "[]" }, accounting: nil))
              .to eq(%w[arguments raw])
          end

          it "sends a link to the dropped tab to the first section instead" do
            probe = subject_class.new
            definitions = probe.tabs(probe.messages("job.arguments" => "[]"), accounting: nil)

            expect(probe.send(:resolve_tab, "tokens", definitions, failed: false)).to eq("arguments")
          end
        end

        describe "a span that reported a failure" do
          it "is the only one offered an Error tab" do
            attrs = { "output" => "hi" }

            expect(tabs_for.call(attrs, error: true)).to eq(%w[response error tokens raw])
            expect(tabs_for.call(attrs)).to eq(%w[response tokens raw])
          end
        end

        describe "#resolve_tab" do
          let(:probe) { subject_class.new }
          let(:messages) { probe.messages("query" => "acme", "result.0.title" => "Acme") }
          let(:definitions) { probe.tabs(messages) }
          let(:failing) { probe.tabs(messages, error: true) }
          let(:resolve) do
            ->(requested, failed, tabs = definitions) { probe.send(:resolve_tab, requested, tabs, failed: failed) }
          end

          it "honours an explicit choice" do
            expect(resolve.call("results", false)).to eq("results")
          end

          it "opens a failed span on its error" do
            expect(resolve.call(nil, true, failing)).to eq("error")
          end

          it "opens a healthy span on its payload, whatever the link asked for" do
            expect(resolve.call("error", false)).to eq("query")
          end

          it "sends a link written before the tabs split to the first section" do
            expect(resolve.call("payload", false)).to eq("query")
          end
        end
      end
    end
  end
end
