# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Prototype
        ##
        # PROTOTYPE — throwaway. Number formatting shared by the three
        # variants. Formatting only: no layout crosses this module, so each
        # variant stays free to throw its whole structure away.
        #
        module Figures
          private

          def usd(amount, places: 2)
            "$#{Kernel.format("%.#{places}f", amount.to_f)}"
          end

          def count(value)
            value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
          end

          def pct(part, whole, places: 1)
            return "—" if whole.to_f.zero?

            "#{Kernel.format("%.#{places}f", (part.to_f / whole) * 100)}%"
          end

          def provider_label(name)
            name.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
          end

          def short_agent(name)
            name.to_s.split("::").last.presence || "—"
          end

          def clock(time)
            time.strftime("%d %b %H:%M:%S")
          end

          # A provider call that returned nothing is the failure this screen
          # exists to surface, so it gets its own tone everywhere.
          def yield_tone(results)
            results.to_i.zero? ? :bad : :ok
          end
        end
      end
    end
  end
end
