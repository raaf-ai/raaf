# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      ##
      # Base class for every Glass Morph component.
      #
      # Components are deliberately thin: they own their markup and their class
      # list, and nothing else. All styling lives in the matching stylesheet
      # under `app/assets/stylesheets/RAAF/ui/`, one file per
      # component, so a visual change is made in exactly one place.
      #
      # Two conventions hold throughout the library:
      #
      # * **Variants are class modifiers, never inline styles.** A component
      #   takes symbols (`variant: :primary`, `size: :sm`) and maps them onto
      #   BEM-ish modifier classes.
      # * **Callers may always pass extra classes and arbitrary HTML
      #   attributes.** Every component accepts `class:` and `**attrs` and
      #   merges them, so a component never has to be forked to add a Stimulus
      #   target or a `data-` hook.
      #
      class Base < Phlex::HTML
        # Builds a class attribute from any mix of strings, symbols, arrays and
        # conditional hashes, dropping blanks and duplicates.
        #
        # @example
        #   tokens("raaf-badge", "raaf-badge--sm", { "is-active" => active? })
        #   # => "raaf-badge raaf-badge--sm is-active"
        #
        # Returns nil when nothing survives, so Phlex omits the attribute
        # rather than emitting `class=""`.
        #
        # @return [String, nil]
        def tokens(*values)
          list = values.flatten.flat_map do |value|
            case value
            when Hash then value.filter_map { |token, on| token if on }
            when nil, false then []
            else value
            end
          end.map(&:to_s).reject(&:empty?).uniq

          list.empty? ? nil : list.join(" ")
        end

        # Maps a variant symbol onto its modifier class.
        #
        # A variant the component does not understand is a mistake at the call
        # site, and this used to answer it with nil — so the component rendered
        # as its bare base and nothing said otherwise. A wrong tone became no
        # tone, which is a quiet wrong colour rather than a failure. The policy
        # form printed its validation errors as bare text that way for as long
        # as it passed `:danger` to an Alert whose vocabulary is `error`.
        #
        # So it raises where a developer or CI will see it, and keeps the old
        # silence in production, where a missing modifier is cosmetic and
        # raising would turn it into a blank screen in front of a user.
        #
        # A nil variant is not a mistake: every component reads it as "no
        # modifier" and most callers pass one.
        #
        # @param base [String] the component's block class, e.g. "raaf-badge"
        # @param variant [Symbol, String, nil]
        # @param allowed [Array<Symbol>] variants this component understands
        # @raise [ArgumentError] outside production, when the variant is not in
        #   +allowed+
        # @return [String, nil] the modifier class, or nil for no variant
        def modifier(base, variant, allowed)
          return nil if variant.nil?

          key = variant.to_s.tr("_", "-").to_sym
          return "#{base}--#{key}" if allowed.include?(key)

          raise_unknown_variant(base, variant, allowed) unless production?

          nil
        end

        # `private def` rather than a bare `private`, which would also capture
        # `slot` below and quietly narrow a helper the whole library calls.
        private def raise_unknown_variant(base, variant, allowed)
          raise ArgumentError,
                "#{self.class.name || 'component'} was given #{variant.inspect} for " \
                "#{base}, which understands #{allowed.map(&:to_s).join(', ')}"
        end

        # Defined outside a Rails boot too: the style guide and a handful of
        # specs load these components with no application around them.
        private def production?
          defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.production?
        end

        # Renders a slot that may be a block, a component or a plain string.
        def slot(content = nil, &block)
          if block
            yield
          elsif content.respond_to?(:view_template)
            render content
          elsif content
            plain content.to_s
          end
        end
      end
    end
  end
end
