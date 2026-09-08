# frozen_string_literal: true

require "digest"

module RAAF
  module Rails
    module Ui
      ##
      # Assembles the console's Stimulus controllers into one ES module.
      #
      # The same delivery problem {Stylesheet} solves, for the other half of
      # the front end: the dashboard is a mountable engine and cannot assume
      # the host application's asset pipeline, so it serves its own JavaScript
      # from its own route rather than asking every host to wire a manifest.
      #
      # The controllers used to live in a heredoc inside BaseLayout — roughly
      # 1,200 lines of JavaScript in a Ruby file, re-sent with every document
      # and unreachable to any tool that reads JavaScript. Splitting them into
      # files needs somewhere for the files to be assembled, which is here.
      #
      # Concatenation rather than module resolution is deliberate. Serving each
      # file separately would mean a URL per controller, a digest per URL and
      # relative-import resolution against a digested path. The whole bundle is
      # under 40 kB, so it is one file, and the files inside it share one
      # module scope: no `import`/`export` between them, the single Stimulus
      # import in +runtime/stimulus.js+, and every class in scope by the time
      # +boot/register.js+ names it.
      #
      # Order is therefore load-bearing, which is what LAYERS declares.
      #
      module Javascript
        ROOT = ::File.expand_path("../../../../assets/javascripts/RAAF/console", __dir__)

        # The runtime imports Stimulus and starts the application; support
        # defines what the controllers share; boot registers them, so it can
        # only run once every class above it exists.
        LAYERS = %w[runtime support controllers boot].freeze

        class << self
          # @return [String] the whole console bundle, as one ES module
          #
          # Cached, except in development, where editing a controller should
          # show up on the next reload without restarting the server.
          def call
            @call = nil if reload?
            @call ||= build
          end

          # A short content hash, for a URL that can be cached forever.
          #
          # Serves the same purpose as {Stylesheet.digest}: the bundle is
          # served at a path carrying this, so a browser may keep it until the
          # JavaScript itself changes, at which point the path changes with it.
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

          # Alphabetical within a layer. Controllers do not reference each
          # other, so their order among themselves carries no meaning and a
          # stable one keeps the digest from moving when nothing changed.
          def paths_for(layer)
            ::Dir.glob(::File.join(ROOT, layer, "*.js")).sort
          end

          def section(path)
            relative = path.delete_prefix("#{ROOT}/")
            "// >>> #{relative}\n#{::File.read(path)}"
          end
        end
      end
    end
  end
end
