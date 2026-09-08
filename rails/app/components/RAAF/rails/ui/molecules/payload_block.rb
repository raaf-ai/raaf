# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # PayloadBlock — one message of a span's payload.
        #
        # A role caption with its token count, then the body in mono. When the
        # body is masked it is blurred and a RedactionVeil covers it; the
        # `raaf-payload--masked` modifier is what applies the blur, so the text
        # is never assembled differently for the two states.
        #
        # @example
        #   render Molecules::PayloadBlock.new(role: "tool arguments", tokens: "86 tok",
        #                                      body: json, masked: true, tone: :tool)
        #
        class PayloadBlock < Base
          # Role captions borrow the kind palette so a tool payload reads as a
          # tool; anything unrecognised stays muted.
          TONES = %i[agent llm tool handoff guardrail pipeline ok warn bad].freeze

          # @param role [String] "system", "tool arguments", "tool result"…
          # @param body [String] the payload itself
          # @param tokens [String, nil] token count for this message
          # @param masked [Boolean] cover the body with a RedactionVeil
          # @param tone [Symbol, nil] colours the role caption
          # @param veil [Hash] arguments forwarded to RedactionVeil
          # @param id [String, nil] used for the reveal checkbox; derived when omitted
          def initialize(role:, body:, tokens: nil, masked: false, tone: nil, veil: {},
                         id: nil, class: nil, **attrs)
            @role = role
            @body = body
            @tokens = tokens
            @masked = masked
            @tone = tone
            @veil = veil
            @id = id
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-payload", @class), **@attrs) do
              caption
              body_block
            end
          end

          private

          # A block whose role is already named above it — by the tab that
          # selected it — passes no role, and then the caption is a line that
          # says nothing, so there is none.
          def caption
            return if @role.blank? && @tokens.blank?

            div(class: "raaf-payload-head") do
              span(class: tokens("raaf-payload-role", role_tone)) { @role } if @role.present?
              span(class: "raaf-payload-rule")
              render Atoms::Mono.new(@tokens, tone: :muted, class: "raaf-payload-tokens") if @tokens
            end
          end

          def role_tone
            modifier("raaf-payload-role", @tone, TONES)
          end

          # The checkbox comes before the payload so a sibling selector can
          # lift the blur when it is checked; it is the whole reveal mechanism,
          # and there is no script behind it.
          def body_block
            div(class: tokens("raaf-payload-body", { "raaf-payload-body--masked" => @masked })) do
              input(type: "checkbox", id: reveal_id, class: "raaf-veil-toggle") if @masked
              pre(class: "raaf-payload-pre") { @body.to_s }
              render Molecules::RedactionVeil.new(for_id: reveal_id, **@veil) if @masked
            end
          end

          def reveal_id
            @reveal_id ||= @id || "raaf-reveal-#{@role.to_s.parameterize}-#{object_id}"
          end
        end
      end
    end
  end
end
