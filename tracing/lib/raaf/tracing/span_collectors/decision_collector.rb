# frozen_string_literal: true

require_relative "base_collector"

module RAAF

  module Tracing

    module SpanCollectors

      # Collector for decision model ("System One") calls.
      #
      # A decision call is not a completion. It sends state and typed questions,
      # and gets back a probability per question in one forward pass: no
      # messages, no tool calls, no streamed text. So the attributes worth
      # keeping are different from an LLM span's, and this collector records
      # them under the +decision.+ prefix:
      #
      # - what was asked: the provider, the model, and the question count.
      #   {RAAF::Models::DecisionInterface#decide} adds the question names and
      #   types as span metadata, and the state only when +trace_state+ asks
      #   for it.
      # - what came back: one line per answer, with the number the caller acts
      #   on - a noul's probability, a choice's option, a score's score - and
      #   the confidence beside it.
      # - what it cost: the provider reports an exact figure per call, so the
      #   span records that rather than a token count to be priced later. See
      #   {RAAF::Tracing::SpanUsage::PER_CALL_KINDS}.
      #
      # @example Attributes on a two-question call
      #   attributes["decision.provider"]          # => "OpenRouter"
      #   attributes["decision.model"]             # => "~typesafe/jev-latest"
      #   attributes["decision.result.model"]      # => "typesafe/jev-1.13-20260917"
      #   attributes["decision.tokens.input"]      # => "663"
      #   attributes["decision.cost_cents"]        # => "0.0027846"
      #   JSON.parse(attributes["decision.answers"])
      #   # => {"in_market" => {"type" => "noul", "probability" => 0.95, "confidence" => 0.9}, ...}
      #
      # @see RAAF::Models::DecisionInterface The interface that opens the span
      # @see LLMCollector The equivalent for chat completions
      #
      class DecisionCollector < BaseCollector

        # The provider that answered, as it names itself ("Jev", "OpenRouter",
        # "LLMBacked"). A flat per-call fee means little without it.
        span provider: ->(comp) { comp.respond_to?(:provider_name) ? comp.provider_name : "N/A" }

        # The model the provider asks when the caller names none. The model
        # that actually answered is recorded from the result, because a vendor
        # resolves an alias like +jev-latest+ to a dated build.
        span model: ->(comp) { comp.respond_to?(:model) ? comp.model : "N/A" }

        ##
        # What was asked, under the +decision.+ prefix
        #
        # The questions are not on the provider — they are arguments to one
        # call — so +DecisionInterface+ parks the call in flight where this can
        # read it. A provider outside RAAF that does not expose one still gets
        # its provider and model recorded; it just says nothing about the
        # questions.
        #
        # @param component [Object] The provider being asked
        # @return [Hash{String => Object}]
        #
        def custom_attributes(component)
          attrs = super
          call = component.respond_to?(:traced_decision) ? component.traced_decision : nil
          return attrs unless call

          questions = call[:questions] || {}
          attrs["decision.question_count"] = questions.size

          # Names and types only. A question's instructions are written by the
          # application and routinely quote the record being decided about, so
          # they belong with the state below rather than on every span.
          attrs["decision.questions"] = safe_value(
            questions.map { |name, question| { "name" => name.to_s, "type" => question.type.to_s } }.to_json
          )

          attrs["decision.state"] = safe_value(traced_state(call[:state])) if trace_state?(component)
          attrs
        end

        ##
        # What came back, under the +decision.+ prefix
        #
        # The +result+ DSL is not used here because it prefixes every key it
        # writes with +result.+, and the keys a bill is read from are fixed:
        # {RAAF::Tracing::SpanUsage} looks for +decision.cost_cents+ and
        # +decision.tokens.*+, and would find +result.cost_cents+ nowhere. So
        # these are written out, and +result.type+ and +result.success+ still
        # come from the base implementation.
        #
        # @param component [Object] The provider that answered
        # @param result [Object] The {RAAF::Models::Decision::Result}
        # @return [Hash{String => Object}]
        #
        def custom_result_attributes(component, result)
          attrs = super

          # The model named in the response, which is the one that was billed:
          # a vendor resolves an alias like +jev-latest+ to a dated build.
          attrs["decision.result.model"] = safe_value(result.model.to_s) if result.respond_to?(:model)
          attrs["decision.request_id"] = safe_value(self.class.request_id(result))
          attrs["decision.answer_count"] = safe_value(result.names.size.to_s) if result.respond_to?(:names)

          # One entry per answer: its type, the figure the caller acts on, and
          # the confidence. This is the decision itself, so it is the one thing
          # a span here must carry.
          attrs["decision.answers"] = safe_value(result.to_h.to_json) if result.respond_to?(:to_h)

          # Token counts are recorded for size, not for pricing: the cost below
          # is what a decision span is billed by.
          attrs["decision.tokens.input"] = safe_value(self.class.usage_field(result, "input_tokens"))
          attrs["decision.tokens.output"] = safe_value(self.class.usage_field(result, "output_tokens"))
          attrs["decision.tokens.total"] = safe_value(self.class.usage_field(result, "total_tokens"))

          cost = self.class.usage_value(result, "cost")
          attrs["decision.cost_cents"] = safe_value((cost.to_f * 100).to_s) unless cost.nil?

          attrs
        end

        ##
        # Whether this provider was asked to record the state it decided about
        #
        # @param component [Object] The provider being asked
        # @return [Boolean]
        #
        def trace_state?(component)
          component.respond_to?(:trace_state?) && component.trace_state?
        end

        ##
        # The state as a span records it
        #
        # A String goes in as written; anything else is the JSON the provider
        # would have sent, which is the form worth reading back.
        #
        # @param state [Object] What was decided about
        # @return [String]
        #
        def traced_state(state)
          state.is_a?(String) ? state : state.to_json
        end

        ##
        # The provider's own request id, worth quoting in a support request
        #
        # @param result [Object] The decision result
        # @return [String] The id, or "N/A" when the provider sent none
        #
        def self.request_id(result)
          id = result.respond_to?(:request_id) ? result.request_id : nil

          id.to_s.empty? ? "N/A" : id.to_s
        end

        ##
        # One field of the reported usage, as a string
        #
        # @param result [Object] The decision result
        # @param field [String] The usage field to read
        # @return [String] The value, or "N/A" when the provider reported none
        #
        def self.usage_field(result, field)
          value = usage_value(result, field)

          value.nil? ? "N/A" : value.to_s
        end

        ##
        # One field of the reported usage
        #
        # Usage is the provider's own hash, so it arrives string-keyed from
        # JSON and symbol-keyed from a hand-built result.
        #
        # @param result [Object] The decision result
        # @param field [String] The usage field to read
        # @return [Object, nil] The value, or nil when absent
        #
        def self.usage_value(result, field)
          return unless result.respond_to?(:usage)

          usage = result.usage
          return unless usage.is_a?(Hash)

          usage[field] || usage[field.to_sym]
        end

      end

    end

  end

end
