# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Avatar — an initials disc for an agent, tool or user.
        #
        # @example
        #   render Atoms::Avatar.new("Research Agent", size: :md)
        #
        class Avatar < Base
          SIZES = %i[md lg].freeze

          # @param name [String] the name initials are derived from
          # @param size [Symbol, nil] :md or :lg
          # @param initials [String, nil] override the derived initials
          def initialize(name, size: nil, initials: nil, class: nil, **attrs)
            @name = name
            @size = size
            @initials = initials
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: css, title: @name, **@attrs) { initials }
          end

          private

          def css
            tokens("raaf-avatar", modifier("raaf-avatar", @size, SIZES), @class)
          end

          # First letters of the first two words, e.g. "Research Agent" => "RA".
          def initials
            return @initials if @initials

            @name.to_s.split(/[\s_-]+/).reject(&:empty?).first(2).map { |word| word[0] }.join.upcase
          end
        end
      end
    end
  end
end
