# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # TitleMeta — a name with a quieter line under it, for the leading cell
        # of a table row.
        #
        # The design uses this wherever a row needs to say what a thing is *and*
        # what makes it interesting without spending a second column on it — a
        # policy and what triggers it, for instance.
        #
        # @example
        #   render Molecules::TitleMeta.new("Prospect scoring quality",
        #                                   "production only")
        #
        class TitleMeta < Base
          TONES = %i[ok warn bad accent].freeze

          # @param title [String]
          # @param meta [String, nil] the second line; omitted when blank
          # @param mono [Boolean] set the title in the mono face
          # @param tone [Symbol, nil] colours the title — the Errors table sets
          #   the exception class in the failure tone, so the row says what it
          #   is before it is read
          def initialize(title, meta = nil, mono: false, tone: nil, class: nil, **attrs)
            @title = title
            @meta = meta
            @mono = mono
            @tone = tone
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-titlemeta", @class), **@attrs) do
              span(class: title_css) { @title }
              span(class: "raaf-titlemeta-meta") { @meta } if @meta.present?
            end
          end

          private

          def title_css
            tokens("raaf-titlemeta-title",
                   modifier("raaf-titlemeta-title", @tone, TONES),
                   { "raaf-mono" => @mono })
          end
        end
      end
    end
  end
end
