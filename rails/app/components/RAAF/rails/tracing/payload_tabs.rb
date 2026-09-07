# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The inspector's tab set, shared by the trace screen and the span page.
      #
      # A span's payload is several separate things — what the agent was told,
      # what it was asked, what it answered — and they are long. Stacked into
      # one Payload tab they scrolled past each other: reading a response meant
      # paging through a system prompt that had not changed in weeks, and
      # comparing a prompt with its answer meant scrolling between them rather
      # than switching between them. So each part that a span actually recorded
      # gets its own tab, and a span that recorded two shows two.
      #
      # Both screens built this list separately, and the span page already
      # reached across into the trace screen's constant for the section
      # definitions. One module, so the two cannot drift.
      #
      module PayloadTabs
        # The attributes that hold a message, in the order a reader wants them:
        # what the span was told, what it was asked, what it answered. RAAF's
        # processors write the dotted keys; the bare ones are what a hand-rolled
        # tool tends to set, and both are checked so neither shape is invisible.
        #
        # `masked` marks a payload that can carry customer data — it is blurred
        # until asked for, rather than dropped.
        PAYLOAD_SECTIONS = [
          { id: "system", label: "System", tone: :pipeline, masked: false,
            keys: %w[agent.system_instructions instructions system_prompt] },
          # Unmasked, unlike the prompt below it. A veil here would cover the
          # first tab a search span opens on while the hits it produced stay
          # legible in the next tab, which protects nothing and hides the one
          # line that explains the rest of the span.
          { id: "query", label: "Query", tone: :tool, masked: false,
            keys: %w[query search.query search_query] },
          { id: "prompt", label: "Prompt", tone: :agent, masked: true,
            keys: %w[agent.initial_user_prompt input messages prompt] },
          { id: "arguments", label: "Arguments", tone: :tool, masked: true,
            keys: %w[tool_arguments arguments job.arguments] },
          { id: "response", label: "Response", tone: :llm, masked: false,
            keys: %w[agent.final_agent_response llm.response.content output response
                     completion result.tool_result result.final_result result] }
        ].freeze

        # The attributes holding the whole exchange, message by message. RAAF
        # writes the dotted key; the bare one is what a hand-rolled tracer
        # tends to set.
        #
        # The sections above show three excerpts of this: the agent's
        # configured instructions, the *first* user message and the *last*
        # assistant one. That is the whole of a single-turn run, and nothing
        # like a run with tools -- its intermediate turns, its tool calls and
        # their results live only here. It is not even the whole of a simple
        # run for a DSL agent, whose collector writes no
        # `agent.system_instructions` at all: for those the system prompt the
        # provider was actually sent exists nowhere but in this attribute, and
        # until it had a tab of its own it was readable only as a wall of JSON
        # in the Attributes tab.
        CONVERSATION_KEYS = %w[agent.conversation_messages conversation_messages].freeze

        CONVERSATION_TAB = { id: "conversation", label: "Conversation" }.freeze

        # How each role is captioned. The tones and the veils match the
        # sections above, so the same content reads the same way whether it is
        # met as an excerpt or in the transcript: a system prompt is a
        # pipeline colour and open, what was asked is veiled, what came back
        # is not. A role this hash does not know is veiled, because the one
        # thing worse than blurring a harmless message is publishing a
        # customer's name behind the tracer's back.
        CONVERSATION_ROLES = {
          "system" => { tone: :pipeline, masked: false },
          "developer" => { tone: :pipeline, masked: false },
          "user" => { tone: :agent, masked: true },
          "assistant" => { tone: :llm, masked: false },
          "tool" => { tone: :tool, masked: true }
        }.freeze

        UNKNOWN_ROLE = { tone: nil, masked: true }.freeze

        # Tabs that are a set of named values rather than a body of text: a
        # label per fact, and the attributes it can have been written under.
        #
        # A span gets one of these when it recorded any of its facts, with a
        # row per value it actually has -- no span records all of them. Every
        # key here was read only by the per-kind components on the span page,
        # which meant a handoff's source and target, a pipeline's mode, and the
        # settings an agent ran under were invisible on the screen every span
        # link actually opens.
        FACT_SECTIONS = [
          { id: "handoff", label: "Handoff", facts: [
            ["From", %w[handoff.source_agent]],
            ["To", %w[handoff.target_agent]],
            ["Reason", %w[handoff.reason]],
            ["Type", %w[handoff.type handoff_type]],
            ["Succeeded", %w[handoff.success]],
            ["Conversation", %w[handoff.conversation_id]],
            ["At", %w[handoff.timestamp]],
            ["Context", %w[handoff.context]]
          ] },
          { id: "pipeline", label: "Pipeline", facts: [
            ["Name", %w[pipeline.name pipeline_name]],
            ["Mode", %w[pipeline.execution_mode]],
            ["Agents", %w[pipeline.total_agents]],
            ["Status", %w[result.execution_status]],
            ["Flow", %w[pipeline.execution_flow]],
            ["Structure", %w[pipeline.flow_structure]],
            ["Metrics", %w[pipeline.metrics]]
          ] },
          # A job's own bookkeeping. Written on every job span this tracer
          # produces and read by nothing before this, so what queue a run sat
          # in and how many times it had already been attempted were legible
          # only as JSON.
          { id: "job", label: "Job", facts: [
            ["Class", %w[job.class]],
            ["Queue", %w[job.queue]],
            ["Job id", %w[job.id]],
            ["Attempt", %w[job.executions]],
            ["Enqueued", %w[job.enqueued_at]],
            ["Scheduled", %w[job.scheduled_at]],
            ["Backend id", %w[job.provider_job_id]],
            ["Status", %w[result.status]]
          ] },
          # The call a hand-instrumented span made. `custom` spans are the
          # second largest kind here and most of them are an HTTP request.
          { id: "request", label: "Request", facts: [
            ["Method", %w[http.method]],
            ["Host", %w[http.host]],
            ["URL", %w[http.url]],
            ["Status", %w[http.status http.status_code]]
          ] },
          { id: "execution", label: "Execution", facts: [
            ["Duration", %w[tool.duration.ms]],
            ["Retries", %w[tool.retry.count]],
            ["Backoff", %w[tool.retry.total_backoff_ms]],
            ["Result size", %w[result.size.bytes]]
          ] },
          # Last, because it is reference rather than narrative: the reader
          # comes to it after seeing what the span did, to find out under what
          # settings it did it. The model is not here -- the accounting tab and
          # the header both already name it.
          { id: "config", label: "Configuration", facts: [
            ["Provider", %w[agent.provider llm.provider]],
            ["Temperature", %w[agent.temperature llm.temperature]],
            ["Top P", %w[agent.top_p llm.top_p]],
            ["Max tokens", %w[agent.max_tokens llm.max_tokens]],
            ["Max turns", %w[agent.max_turns]],
            ["Frequency penalty", %w[agent.frequency_penalty llm.frequency_penalty]],
            ["Presence penalty", %w[agent.presence_penalty llm.presence_penalty]],
            ["Tool choice", %w[agent.tool_choice]],
            ["Parallel tool calls", %w[agent.parallel_tool_calls]],
            ["Tools", %w[agent.tools_count]],
            ["Handoffs", %w[agent.handoffs_count]],
            ["Streaming", %w[llm.stream]],
            ["Response format", %w[agent.response_format]]
          ] }
        ].freeze

        # Attributes the inspector already shows outside the payload: the
        # figures in its header, the name and kind in its title, and the
        # counts in its accounting tab. The Attributes tab exists to show what
        # nothing else does, and listing these would make it a second, worse
        # copy of the frame drawn around it -- ten of the twenty-three rows on
        # a plain agent span.
        FRAME_KEYS = %w[
          duration_ms success
          input_tokens output_tokens total_tokens
          component.type component.name
          agent.name agent_name agent.model
        ].freeze

        # What the tracer writes for a setting that was never set. Recorded as
        # a value rather than omitted, so a Configuration tab that did not
        # reject these would be a column of "N/A" -- six of the thirteen rows
        # on a plain agent span.
        SETTING_PLACEHOLDERS = ["n/a", "unknown", "null", "nil", "{}", "[]"].freeze

        # A search span records its hits one attribute per field per position:
        # `result.0.title`, `result.0.url`, `result.0.snippet`. Flattened like
        # that they match none of the sections above, so a provider search used
        # to arrive at the inspector with nothing to show — which is the one
        # thing anybody opens a search span to read. Folded back into rows here.
        RESULT_PREFIX = "result"

        # The fields a hit can carry, and what each is for: +url+ makes the
        # title a link, +score+ is the provider's own ranking, and a hit with
        # neither +snippet+ nor +snippets+ shows its title alone.
        RESULT_FIELDS = %w[title url snippet snippets score].freeze

        # A provider returning more hits than this has misunderstood the
        # question; the cap is only here so a malformed attribute set cannot
        # spin the loop that walks the positions.
        RESULT_LIMIT = 250

        # Offered only to a span that reported a failure. It used to be on
        # every span, on the argument that "no error" is information — but a
        # trace of forty healthy spans is forty Error tabs that all say the
        # same nothing, and a strip that names Error on every span stops
        # marking the one span where it means something.
        ERROR_TAB = { id: "error", label: "Error" }.freeze

        # The raw record, which every span has.
        RAW_TAB = { id: "raw", label: "Raw" }.freeze

        # The accounting tab sits between them, and is the other tab a span
        # can decline: see {SpanAccounting}. Its id is what it was when
        # the panel only ever held tokens, so links already written against
        # `?tab=tokens` still land on it whatever it is now called.
        ACCOUNTING_TAB_ID = "tokens"

        # What the single payload tab was called. Links written before the
        # split still arrive with it, and they open on the first section rather
        # than falling through to whatever the default happens to be.
        LEGACY_PAYLOAD_TAB = "payload"

        private

        # Everything the span recorded, as tabs: the sections it matched, its
        # search hits, and — when it matched none of them — its attributes.
        #
        # The fallback is what keeps the inspector honest. The sections know
        # the shapes RAAF's own processors write, and a span written by
        # anything else (a service tracing an API call by hand, a component
        # with its own vocabulary) matches none of them. Reporting "no payload
        # captured" over a span carrying sixty attributes says the span is
        # empty when the reader is looking straight at the screen it should
        # have been shown on.
        #
        # @param attrs [Hash, nil] Span attributes
        # @return [Array<Hash>] :id, :label and one of :body, :results, :pairs
        def payload_messages_from(attrs)
          attrs ||= {}

          payload = section_messages(attrs) + conversation_messages(attrs)
          results = results_message(attrs)
          payload << results if results

          facts = fact_messages(attrs)
          rest = attributes_message(attrs, except: claimed_keys(attrs))

          payload + facts + (rest ? [rest] : [])
        end

        # Every attribute some other tab already reads.
        #
        # Recomputed rather than collected while building, because a message
        # carries only what PayloadBlock may be handed -- an extra key on one
        # would reach the markup as an HTML attribute.
        def claimed_keys(attrs)
          sections = PAYLOAD_SECTIONS.filter_map do |section|
            section[:keys].find { |candidate| attrs[candidate].present? }
          end

          facts = FACT_SECTIONS.flat_map do |section|
            section[:facts].filter_map { |_, keys| keys.find { |key| recorded?(attrs[key]) } }
          end

          # The hits the Results tab folded back together, which are one
          # attribute per field per position and would otherwise fill the
          # Attributes tab with three hundred rows of the same three names.
          hits = attrs.keys.grep(/\A#{RESULT_PREFIX}\.\d+\./) if results_message(attrs)

          # Claimed even when the transcript is empty: `"[]"` is what the
          # collector writes for a span that recorded no messages, and an
          # Attributes row saying so is a row saying nothing. A value that
          # does not parse is *not* claimed -- the Conversation tab cannot
          # render it, and dropping it from Attributes too would delete it
          # from the screen.
          conversation = conversation_from(attrs)&.first

          sections + facts + Array(hits) + Array(conversation) + FRAME_KEYS
        end

        # One pairs message per fact section the span recorded anything for.
        def fact_messages(attrs)
          FACT_SECTIONS.filter_map do |section|
            pairs = section[:facts].filter_map do |label, keys|
              key = keys.find { |candidate| recorded?(attrs[candidate]) }
              [label, stringify_payload(attrs[key])] if key
            end.to_h

            next if pairs.empty?

            { id: section[:id], label: section[:label], pairs: pairs }
          end
        end

        # Whether the span said anything by this attribute. See
        # {SETTING_PLACEHOLDERS}: absence is written down here, not left out.
        def recorded?(value)
          return false if value.nil?

          text = value.to_s.strip
          !text.empty? && !SETTING_PLACEHOLDERS.include?(text.downcase)
        end

        # The span's conversation, as one PayloadBlock per message.
        #
        # Several messages carrying the same id is how the inspector shows
        # more than one block under a tab -- it selects every message whose id
        # matches, and renders them in order.
        def conversation_messages(attrs)
          _key, messages = conversation_from(attrs)

          Array(messages).flat_map { |message| conversation_blocks(message) }
        end

        # The attribute the conversation was written under and the messages in
        # it, or nil when the span recorded no conversation it can render.
        #
        # @return [Array(String, Array), nil] the key and its messages
        def conversation_from(attrs)
          CONVERSATION_KEYS.each do |key|
            next if attrs[key].blank?

            messages = parse_conversation(attrs[key])
            return [key, messages] if messages.is_a?(::Array)
          end

          nil
        end

        def parse_conversation(value)
          return value if value.is_a?(::Array)

          parsed = ::JSON.parse(value.to_s)
          parsed if parsed.is_a?(::Array)
        rescue ::JSON::ParserError
          nil
        end

        # One message, as the blocks it is worth reading as.
        #
        # Usually one. An assistant turn that both said something and called a
        # tool becomes two, because its prose and its arguments are different
        # things to read and stacking them in one pre would print a sentence
        # against a JSON object.
        def conversation_blocks(message)
          return [] unless message.is_a?(::Hash)

          role = (message["role"] || message[:role]).to_s
          style = CONVERSATION_ROLES.fetch(role, UNKNOWN_ROLE)
          role = "message" if role.empty?
          content = message["content"] || message[:content]
          calls = message["tool_calls"] || message[:tool_calls]

          blocks = []
          blocks << conversation_block(conversation_role(role, message), content, style) if content.present?
          blocks << conversation_block("#{role} · tool calls", calls, style) if calls.present?
          blocks
        end

        def conversation_block(role, value, style)
          { id: CONVERSATION_TAB[:id], label: CONVERSATION_TAB[:label],
            role: role, body: stringify_payload(value),
            tone: style[:tone], masked: style[:masked] }
        end

        # A tool result says which tool it came back from; without the name a
        # transcript of six of them is six blocks captioned "tool".
        def conversation_role(role, message)
          name = message["name"] || message[:name]

          name.present? ? "#{role} · #{name}" : role
        end

        # One message per section the span actually recorded.
        #
        # Only the first key of a section is used: `output` and `result` are
        # usually the same value written twice, and showing it twice helps
        # nobody.
        def section_messages(attrs)
          PAYLOAD_SECTIONS.filter_map do |section|
            key = section[:keys].find { |candidate| attrs[candidate].present? }
            next unless key

            { id: section[:id],
              label: section[:label],
              role: key,
              body: stringify_payload(attrs[key]),
              masked: section[:masked],
              tone: section[:tone] }
          end
        end

        # The span's search hits, as rows.
        #
        # Unmasked, unlike the query beside it: a query is composed from
        # whatever the run was working on and can name a customer, while the
        # hits are public pages that anyone can fetch. Blurring them would put
        # a click in front of the one thing this tab exists to show.
        def results_message(attrs)
          hits = search_results_from(attrs)
          return nil if hits.empty?

          { id: "results", label: "Results", results: hits }
        end

        # Walks `result.0.*`, `result.1.*` … until a position holds nothing.
        #
        # A gap ends the walk rather than being skipped: the writers emit
        # contiguous positions, so the first empty one is the end of the list
        # and not a hole in it. Scanning past it would mean reading every
        # attribute of every span to find out there was nothing there.
        #
        # @return [Array<Hash>] :title, :url, :snippet, :score
        def search_results_from(attrs)
          (0...RESULT_LIMIT).each_with_object([]) do |index, hits|
            fields = RESULT_FIELDS.each_with_object({}) do |field, found|
              value = attrs["#{RESULT_PREFIX}.#{index}.#{field}"]
              found[field.to_sym] = value if value.present?
            end
            break hits if fields.empty?

            hits << { title: fields[:title], url: fields[:url],
                      score: fields[:score],
                      snippet: snippet_from(fields) }
          end
        end

        # One readable excerpt per hit. Providers write either a single
        # `snippet` or a `snippets` list, and some write both — the singular
        # wins, and the list is joined only when it is all there is.
        def snippet_from(fields)
          return fields[:snippet] if fields[:snippet].is_a?(::String)

          Array(fields[:snippets]).map(&:to_s).reject(&:empty?).join(" … ").presence ||
            fields[:snippet]&.to_s.presence
        end

        # Everything the span recorded that no other tab named, sorted, with
        # structured values printed as JSON the way the Raw tab prints them.
        #
        # This was the last resort, offered only to a span whose vocabulary
        # this module did not recognise at all. But a span it does recognise
        # is not therefore fully shown: an agent span has thirty-two
        # attributes and the tabs name eight of them, so the remaining
        # twenty-four -- the model settings, the DSL metadata, the workflow it
        # belonged to -- were readable only by scrolling the Raw JSON. The tab
        # is now what its name says on every span, and the span that matched
        # nothing still gets all of its attributes here, because nothing else
        # claimed any.
        #
        # @param except [Array<String>] keys another tab already shows
        def attributes_message(attrs, except: [])
          pairs = attrs.except(*except)
                       .reject { |_, value| value.nil? || value.to_s.empty? }
                       .sort
                       .to_h { |key, value| [key, stringify_payload(value)] }
          return nil if pairs.empty?

          { id: "attributes", label: "Attributes", pairs: pairs }
        end

        # The tabs to offer for a span, payload sections first.
        #
        # A span that recorded no payload at all still gets one tab to say so,
        # rather than opening on its accounting — which answers a question
        # nobody asked of a span they clicked to read.
        #
        # @param messages [Array<Hash>] Result of {payload_messages_from}
        # @param accounting [String, nil] What to call the accounting tab, from
        #   +SpanAccounting#accounting_label+. Nil drops it, for a span that is
        #   not billed at all.
        # @param error [Boolean] Whether the span reported a failure. Only then
        #   is an Error tab offered.
        # @return [Array<Hash>] :id, :label
        def payload_tab_definitions(messages, accounting: "Tokens & cost", error: false)
          # Uniq because a tab can be built from more than one message: the
          # Conversation tab is a block per message and would otherwise name
          # itself once per turn.
          sections = messages.map { |message| message.slice(:id, :label) }.uniq
          sections = [{ id: LEGACY_PAYLOAD_TAB, label: "Payload" }] if sections.empty?
          fixed = []
          fixed << ERROR_TAB if error
          fixed << { id: ACCOUNTING_TAB_ID, label: accounting } if accounting

          sections + fixed + [RAW_TAB]
        end

        # Which tab this request is showing.
        #
        # An explicit choice wins. Failing that a span that failed opens on its
        # error, because that is why the reader clicked it. Otherwise it opens
        # on the first thing the span recorded — which is also where a link to
        # a tab this span does not offer lands, so an `?tab=error` bookmark
        # written when every span had one still opens on something.
        #
        # @param requested [String, nil] The tab asked for in the URL
        # @param definitions [Array<Hash>] Result of {payload_tab_definitions}
        # @param failed [Boolean] Whether the span errored or was cancelled
        # @return [String] A tab id from +definitions+
        def resolve_tab(requested, definitions, failed:)
          requested = requested.to_s
          opening = definitions.first[:id]

          return requested if definitions.any? { |tab| tab[:id] == requested }
          return opening if requested == LEGACY_PAYLOAD_TAB

          failed && definitions.any? { |tab| tab[:id] == ERROR_TAB[:id] } ? ERROR_TAB[:id] : opening
        end

        # A payload value as text. Pretty JSON for anything structured, the
        # string itself for a string, and +to_s+ for whatever cannot be
        # generated — a payload is worth showing imperfectly rather than not
        # showing at all.
        def stringify_payload(value)
          return ::JSON.pretty_generate(value) unless value.is_a?(::String)

          pretty_json(value) || value
        rescue StandardError
          value.to_s
        end

        # A string that already holds JSON, re-printed with its structure
        # showing. The tracer records a response format, a tool's arguments
        # and a structured answer as the single line the provider sent, and a
        # response schema on one line is a schema nobody reads. Text that does
        # not parse — prose that happens to open with a brace — is left
        # exactly as it was recorded.
        def pretty_json(text)
          trimmed = text.strip
          return nil unless trimmed.start_with?("{", "[")

          ::JSON.pretty_generate(::JSON.parse(trimmed))
        rescue ::JSON::ParserError
          nil
        end
      end
    end
  end
end
