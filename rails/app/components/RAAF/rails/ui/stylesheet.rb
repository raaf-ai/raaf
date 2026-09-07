# frozen_string_literal: true

require "digest"

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

          # A short content hash, for a URL that can be cached forever.
          #
          # The stylesheet is served at a path carrying this, so a browser may
          # keep it until the CSS itself changes — at which point the path
          # changes with it and the old copy is simply never asked for again.
          # In development it is recomputed per request along with {call}, so
          # editing a component's CSS produces a new URL on the next reload.
          #
          # @return [String] 16 hex characters
          def digest
            @digest = nil if reload?
            @digest ||= ::Digest::SHA256.hexdigest(call)[0, 16]
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
