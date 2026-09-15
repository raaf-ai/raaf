# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Prototype
        ##
        # PROTOTYPE — throwaway. The floating bar that flips between variants.
        #
        # Deliberately not built from the Glass Morph library and deliberately
        # ugly: it must not read as part of the design being judged. Inline
        # styles for the same reason — nothing here should end up in the
        # console stylesheet.
        #
        class Switcher < BaseComponent
          NAMES = {
            "A" => "Call log — one provider call per row",
            "B" => "Spend board — one provider per row",
            "C" => "Run ledger — one buying run per row"
          }.freeze

          def initialize(current:, note: nil)
            @current = current
            @note = note
          end

          def view_template
            return if ::Rails.env.production?

            div(style: bar_style, data: { controller: "prototype-switcher" }) do
              a(href: href(prev_key), style: arrow_style, title: "Previous variant") { "←" }
              span(style: "font-weight:700;letter-spacing:.02em;") { "#{@current} — #{NAMES[@current]}" }
              a(href: href(next_key), style: arrow_style, title: "Next variant") { "→" }
            end

            div(style: note_style) { @note } if @note
            script { raw(safe(keyboard_js)) }
          end

          private

          def keys = NAMES.keys

          def prev_key = keys[(keys.index(@current) - 1) % keys.size]

          def next_key = keys[(keys.index(@current) + 1) % keys.size]

          def href(key) = "/raaf/prototype/search?variant=#{key}"

          def bar_style
            "position:fixed;left:50%;bottom:20px;transform:translateX(-50%);z-index:9999;" \
              "display:flex;align-items:center;gap:14px;padding:10px 16px;border-radius:999px;" \
              "background:#111827;color:#fff;font:600 13px/1 Figtree,system-ui,sans-serif;" \
              "box-shadow:0 10px 30px rgba(0,0,0,.35);border:2px solid #f59e0b;"
          end

          def arrow_style
            "color:#fff;text-decoration:none;font-size:18px;line-height:1;padding:0 6px;opacity:.85;"
          end

          def note_style
            "position:fixed;left:50%;bottom:64px;transform:translateX(-50%);z-index:9999;" \
              "max-width:640px;padding:6px 12px;border-radius:8px;background:rgba(17,24,39,.9);" \
              "color:#fcd34d;font:500 12px/1.45 Figtree,system-ui,sans-serif;text-align:center;"
          end

          def keyboard_js
            <<~JS
              document.addEventListener("keydown", function (event) {
                var tag = (event.target.tagName || "").toLowerCase();
                if (tag === "input" || tag === "textarea" || event.target.isContentEditable) return;
                if (event.key === "ArrowLeft") window.location.href = "#{href(prev_key)}";
                if (event.key === "ArrowRight") window.location.href = "#{href(next_key)}";
              });
            JS
          end
        end
      end
    end
  end
end
