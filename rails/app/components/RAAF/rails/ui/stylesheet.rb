# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      ##
      # Assembles the component stylesheets into one document.
      #
      # The dashboard is a mountable engine, so it cannot assume the host
      # application's asset pipeline (Sprockets, Propshaft, importmap or none
      # at all). Rather than ask every host to wire up a manifest, the layout
      # inlines the CSS in a single `<style>` element. The files stay split one
      # per component on disk; this class is only the delivery mechanism.
      #
      # Order matters: tokens define the custom properties everything else
      # reads, base sets the ground, then atoms, molecules and organisms in
      # ascending specificity.
      #
      module Stylesheet
        ROOT = ::File.expand_path("../../../../assets/stylesheets/RAAF/ui", __dir__)
        LAYERS = %w[generic atoms molecules organisms utilities].freeze

        # Files whose order within their layer is significant.
        GENERIC_ORDER = %w[tokens base].freeze

        class << self
          # @return [String] every component stylesheet, concatenated
          #
          # Cached, except in development, where a stylesheet edit should show
          # up on the next reload without restarting the server.
          def call
            @call = nil if reload?
            @call ||= build
          end

          private

          def reload?
            defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.development?
          end

          def build
            LAYERS.flat_map { |layer| paths_for(layer) }
                  .map { |path| section(path) }
                  .join("\n")
          end

          def paths_for(layer)
            paths = ::Dir.glob(::File.join(ROOT, layer, "*.css")).sort
            return paths unless layer == "generic"

            paths.sort_by { |path| GENERIC_ORDER.index(::File.basename(path, ".css")) || GENERIC_ORDER.size }
          end

          def section(path)
            relative = path.delete_prefix("#{ROOT}/")
            "/* >>> #{relative} */\n#{::File.read(path)}"
          end
        end
      end
    end
  end
end
