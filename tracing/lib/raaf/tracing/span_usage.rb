# frozen_string_literal: true

require "raaf/usage/cost_calculator"

module RAAF

  module Tracing

    # Reads token usage and cost off a span, whatever shape it was recorded in.
    #
    # Usage reaches the database by several routes and every one of them picks
    # its own key. Agent spans emit top-level +input_tokens+ / +output_tokens+ /
    # +total_tokens+ with the model under +agent.model+. +LLMCollector+ emits
    # +llm.tokens.*+ as strings, using the literal "N/A" for a count it did not
    # get. +LLMSpanWrapper+ emits +llm.usage.*+, in either the input/output or
    # the prompt/completion vocabulary. Payloads that came through the alert
    # engine nest the counts under a +usage+ hash. And since
    # +ActiveRecordProcessor+ started copying the counts into native columns
    # there is a faster route that covers only spans written after that change
    # shipped, or backfilled since.
    #
    # A reader that hard-codes one of those shapes reports zero for all the
    # others, which is how a dashboard ends up showing an empty token column
    # above a table of spans that every one recorded its tokens. This module is
    # the one place that knows them all, so a reader asks here instead of
    # digging into the payload itself.
    #
    # @example Reading a persisted span
    #   RAAF::Tracing::SpanUsage.for_span(span)
    #   # => { input: 2832, output: 1569, total: 5747, model: "gemini-2.5-flash" }
    #
    # @example Costing it
    #   RAAF::Tracing::SpanUsage.cost_for_span(span) # => 0.004774
    module SpanUsage

      # Model placeholders the tracer emits when a field was not set. Recorded
      # as a value rather than omitted, so they have to be rejected explicitly.
      MODEL_PLACEHOLDERS = %w[N/A n/a unknown].freeze

      # Attribute keys carrying the input token count, most specific first.
      #
      # +llm.tokens.input+ is what +LLMCollector+ emits today; the
      # +llm.usage.*+ pair comes from +LLMSpanWrapper+. Cache-read tokens are
      # deliberately absent — the provider already counts them inside input.
      INPUT_KEYS = ["input_tokens", "llm.usage.input_tokens", "llm.usage.prompt_tokens",
                    "llm.tokens.input"].freeze

      # Attribute keys carrying the output token count, most specific first.
      OUTPUT_KEYS = ["output_tokens", "llm.usage.output_tokens", "llm.usage.completion_tokens",
                     "llm.tokens.output"].freeze

      # Attribute keys carrying the total token count, most specific first.
      TOTAL_KEYS = ["total_tokens", "llm.usage.total_tokens", "llm.tokens.total"].freeze

      # Attribute keys carrying the model name, most specific first.
      MODEL_KEYS = ["agent.model", "llm.request.model", "llm.model", "model"].freeze

      # Span kinds that buy nothing themselves. A job span brackets a run; the
      # spend belongs to the spans inside it, each of which reports its own.
      UNBILLED_KINDS = %w[job].freeze

      # Spans charged per call rather than per token. `search` is the kind a
      # hand-rolled provider sets; `component.type` is what RAAF's own search
      # components record, and it is the axis the spans index already filters
      # on.
      PER_CALL_KINDS = %w[search].freeze
      PER_CALL_TYPES = %w[search].freeze

      # Where a per-call charge is recorded, in cents. Written by the component
      # that made the call rather than by the tracer, so more than one spelling
      # is in the field.
      FEE_CENT_KEYS = ["cost_cents", "search.cost_cents", "component.cost_cents"].freeze

      # Who charged it. A flat fee means nothing without the name beside it,
      # and it is what a per-call span has instead of a model.
      PROVIDER_KEYS = ["provider", "search.provider"].freeze

      # Where a component says what it is, and what it is called.
      COMPONENT_TYPE_KEY = "component.type"
      COMPONENT_NAME_KEY = "component.name"

      # Keys read from a nested +usage+ hash, by the field they resolve.
      NESTED_USAGE_KEYS = {
        input: %w[input_tokens prompt_tokens],
        output: %w[output_tokens completion_tokens],
        total: %w[total_tokens]
      }.freeze

      class << self

        # Token usage and model recorded in a span attributes payload.
        #
        # @param attributes [Hash, nil] Span attributes, string or symbol keyed
        # @return [Hash] +{ input:, output:, total:, model: }+, nil where absent
        def from_attributes(attributes)
          {
            input: token(attributes, INPUT_KEYS, :input),
            output: token(attributes, OUTPUT_KEYS, :output),
            total: token(attributes, TOTAL_KEYS, :total),
            model: model(attributes)
          }
        end

        # Token usage and model for a span, preferring the native columns.
        #
        # The columns are indexed and cheap, but they were added late and no
        # backfill can be assumed, so a nil column falls through to the payload
        # rather than being reported as "no tokens". Works on a persisted record
        # or on an in-memory +Span+, which exposes the same accessors.
        #
        # @param span [#input_tokens, #span_attributes] Span or span record
        # @return [Hash] +{ input:, output:, total:, model: }+, nil where absent
        def for_span(span)
          payload = from_attributes(attributes_of(span))

          { input: token_column(span, :input_tokens) || payload[:input],
            output: token_column(span, :output_tokens) || payload[:output],
            total: token_column(span, :total_tokens) || payload[:total],
            model: clean_model(column(span, :agent_model)) || payload[:model] }
        end

        # Total tokens a span consumed, however it recorded them.
        #
        # Prefers the reported total over input + output because providers that
        # bill for tokens they do not itemise only report them in the total.
        #
        # @param span [#input_tokens, #span_attributes] Span or span record
        # @return [Integer, nil] Token count, or nil when the span has no usage
        def total_tokens_for_span(span)
          total_tokens(for_span(span))
        end

        # @param usage [Hash] Result of {for_span} or {from_attributes}
        # @return [Integer, nil] Token count, or nil when the span has no usage
        def total_tokens(usage)
          return usage[:total] if usage[:total]

          summed = usage[:input].to_i + usage[:output].to_i
          summed.positive? ? summed : nil
        end

        # Output tokens the provider actually bills for.
        #
        # Gemini 2.5 charges thinking tokens at the output rate but reports them
        # in +thoughtsTokenCount+, outside +candidatesTokenCount+ — so the only
        # trace of them is the gap between the total and input + output. On the
        # spans in a production database that gap averages ~3,100 tokens per
        # gemini-2.5-flash call, which is more than the reported output. Costing
        # +output+ alone charges nothing for the majority of the answer.
        #
        # @param usage [Hash] Result of {for_span} or {from_attributes}
        # @return [Integer] Billable output tokens
        def billable_output(usage)
          input = usage[:input].to_i
          output = usage[:output].to_i
          total = usage[:total]

          return output unless total && total > input + output

          total - input
        end

        # Cost in USD of the usage a span recorded.
        #
        # @param span [#input_tokens, #span_attributes] Span or span record
        # @return [Float, nil] Cost, or nil with no usage or no pricing for the model
        def cost_for_span(span)
          cost(for_span(span))
        end

        # Cost in USD of a usage hash.
        #
        # @param usage [Hash] Result of {for_span} or {from_attributes}
        # @return [Float, nil] Cost, or nil with no usage or no pricing for the model
        def cost(usage)
          cost_breakdown(usage)&.fetch(:total_cost)
        end

        # Cost in USD of a usage hash, split into its input and output halves.
        #
        # @param usage [Hash] Result of {for_span} or {from_attributes}
        # @return [Hash, nil] +{ input_cost:, output_cost:, total_cost: }+, or
        #   nil with no usage or no pricing for the model
        def cost_breakdown(usage)
          model = usage[:model]
          return nil unless model
          return nil unless total_tokens(usage)

          pricing = pricing_for(model)
          return nil unless pricing

          input_cost = (usage[:input].to_i / 1_000_000.0) * pricing[:input].to_f
          output_cost = (billable_output(usage) / 1_000_000.0) * pricing[:output].to_f

          { input_cost: input_cost.round(6),
            output_cost: output_cost.round(6),
            total_cost: (input_cost + output_cost).round(6) }
        end

        # How a span is billed.
        #
        # Cost does not arrive by one route any more than usage does. A model
        # charges per token; a search provider charges per query and reports no
        # tokens at all, so pricing it off a token count bills it as free; and a
        # job charges nothing, because it is a bracket around the spans that do.
        # A reader that assumes tokens reports the first correctly and the other
        # two as zero, which is how a cost page comes to omit an entire class of
        # spend while looking complete.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [Symbol] +:tokens+, +:cost+ or +:none+
        def billing_mode(span)
          kind = kind_of(span)
          return :none if UNBILLED_KINDS.include?(kind)
          return :cost if PER_CALL_KINDS.include?(kind) || per_call_component?(span)

          :tokens
        end

        # Whether a figure counted in tokens belongs beside this span at all.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [Boolean]
        def billed_in_tokens?(span)
          billing_mode(span) == :tokens
        end

        # The flat fee a span recorded for one call, in USD.
        #
        # @param span [#span_attributes] Span or span record
        # @return [Float, nil] Fee, or nil when none was recorded
        def fee_for_span(span)
          cents = first_present(span, FEE_CENT_KEYS)

          cents && (cents.to_f / 100.0)
        end

        # What a span put on the bill, in whatever unit it is billed in.
        #
        # This is the figure to sum. A per-call span answers with its recorded
        # fee, falling back to its token cost for a provider that answers with a
        # model rather than a price list; a token-priced span answers with its
        # token cost; an unbilled span answers with nothing.
        #
        # Nil is not zero here either — an unpriced model and a search whose
        # component recorded no fee both have an unknown cost, and a total that
        # counts them as free understates itself silently.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [Float, nil] Spend in USD, or nil when unknown or unbilled
        def spend_for_span(span)
          case billing_mode(span)
          when :cost then fee_for_span(span) || cost_for_span(span)
          when :tokens then cost_for_span(span)
          end
        end

        # What to file a span's spend under: its model, or — for a span with no
        # model because it is not billed by one — whoever charged it.
        #
        # @param span [#kind, #span_attributes] Span or span record
        # @return [String, nil]
        def billed_as(span)
          return for_span(span)[:model] if billed_in_tokens?(span)

          provider_for_span(span)
        end

        # The provider named on a per-call span.
        #
        # @param span [#span_attributes] Span or span record
        # @return [String, nil]
        def provider_for_span(span)
          named = first_present(span, PROVIDER_KEYS)
          return named.to_s if named

          # Nothing named itself, so fall back to what the component is called:
          # `Ai::SearchProviders::ScrapingBee` is a provider name with a
          # namespace in front of it.
          component = lookup(attributes_of(span), COMPONENT_NAME_KEY).to_s.split("::").last

          component.to_s.empty? ? nil : component
        end

        # Whether pricing exists for the model a span ran on.
        #
        # Separates "this span cost nothing" from "nobody knows what it cost",
        # which a bare nil cost cannot express.
        #
        # @param usage [Hash] Result of {for_span} or {from_attributes}
        # @return [Boolean]
        def priced?(usage)
          model = usage[:model]
          return false unless model

          !pricing_for(model).nil?
        end

        # Drop the memoised pricing table, so the next lookup consults
        # +CostCalculator+ again. For tests and for a process that wants to pick
        # up refreshed pricing without restarting.
        #
        # @return [void]
        def reset_pricing_cache!
          @pricing_cache = nil
        end

        private

        # Pricing for a model, memoised for the life of the process.
        #
        # Costing a page of spans asks for the same handful of models thousands
        # of times, and +CostCalculator.get_pricing+ is not a cheap constant
        # lookup: it consults +PricingDataManager+, which re-attempts its
        # Helicone fetch on every call for as long as that fetch keeps failing.
        # Without this cache one dashboard render is one blocking HTTP attempt
        # per span. A nil result is cached too — an unpriced model is the case
        # that would otherwise retry hardest.
        def pricing_for(model)
          @pricing_cache ||= {}
          return @pricing_cache[model] if @pricing_cache.key?(model)

          @pricing_cache[model] = RAAF::Usage::CostCalculator.get_pricing(model)
        end

        # A span's kind, downcased, or "" for a shape that carries none.
        def kind_of(span)
          span.respond_to?(:kind) ? span.kind.to_s.downcase : ""
        end

        def per_call_component?(span)
          PER_CALL_TYPES.include?(lookup(attributes_of(span), COMPONENT_TYPE_KEY).to_s)
        end

        # The first of +keys+ the span actually recorded a value for.
        def first_present(span, keys)
          attrs = attributes_of(span)
          keys.each do |key|
            value = lookup(attrs, key)
            return value unless value.nil? || value.to_s.strip.empty?
          end

          nil
        end

        # Attributes payload of a span record or an in-memory span.
        def attributes_of(span)
          if span.respond_to?(:span_attributes)
            span.span_attributes
          elsif span.respond_to?(:attributes)
            span.attributes
          end
        end

        # Read a native column, tolerating records written before it existed
        # and models whose schema never grew one.
        def column(span, name)
          span.respond_to?(name) ? span.public_send(name) : nil
        end

        # Read a native token column as a non-negative integer.
        def token_column(span, name)
          to_token(column(span, name))
        end

        # First resolvable token count across the flat keys, then the nested hash.
        def token(attributes, keys, nested_field)
          keys.each do |key|
            value = to_token(lookup(attributes, key))
            return value if value
          end

          NESTED_USAGE_KEYS.fetch(nested_field).each do |key|
            value = to_token(lookup(lookup(attributes, "usage"), key))
            return value if value
          end

          nil
        end

        def model(attributes)
          MODEL_KEYS.each do |key|
            value = clean_model(lookup(attributes, key))
            return value if value
          end

          nil
        end

        # Read a key from an attributes hash, tolerating string or symbol keys.
        def lookup(attributes, key)
          return nil unless attributes.is_a?(Hash)

          attributes[key].nil? ? attributes[key.to_sym] : attributes[key]
        end

        # Coerce a token value to a non-negative integer, or nil if not numeric.
        def to_token(value)
          return nil if value.nil?
          return value if value.is_a?(Integer)

          str = value.to_s.strip
          str.match?(/\A\d+\z/) ? str.to_i : nil
        end

        # Clean a model value, rejecting placeholders like "N/A".
        def clean_model(value)
          return nil if value.nil?

          str = value.to_s.strip
          return nil if str.empty? || MODEL_PLACEHOLDERS.include?(str)

          str.slice(0, 100)
        end

      end

    end

  end

end
