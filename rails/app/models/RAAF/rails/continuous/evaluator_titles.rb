# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # What a scorer is called, in words.
      #
      # Every continuous table reads its scorer column off
      # `evaluator_name`, which is the registry symbol a policy names the
      # evaluator with — `dmu_classification`, `website_url_extraction`. The
      # evaluator class itself declares a title through the
      # `EvaluatorDefinition` DSL, and this is the lookup from the one to the
      # other, so a screen can say "DMU Classification" where the row says
      # `dmu_classification`.
      #
      # A title is a class-level declaration rather than a stored column, so
      # it resolves against whatever is registered right now. An evaluator
      # that has since been renamed or deleted still has result rows, and they
      # keep their slug — which is what actually ran, and is the honest label
      # for a row nothing can be found for.
      #
      # Every lookup degrades to nil rather than raising: a title is a nicety
      # on every screen that reads one, and none of them should 500 because an
      # evaluator file no longer loads.
      #
      # @example
      #   titles = EvaluatorTitles.new
      #   titles["dmu_classification"]  # => "DMU Classification"
      #   titles["nothing_registered"]  # => nil
      class EvaluatorTitles
        def initialize
          @titles = {}
        end

        # @param name [String, Symbol, nil] the registry name a result recorded
        # @return [String, nil] the declared title, or nil when there is none
        def [](name)
          key = name.to_s
          return nil if key.empty?

          @titles.fetch(key) { @titles[key] = resolve(key) }
        end

        # The title, or the slug spelled as words when nothing declares one.
        #
        # @param name [String, Symbol, nil]
        # @return [String] never nil, so a table cell always has something
        def label(name)
          self[name] || name.to_s.tr("_", " ")
        end

        # ── Checks ────────────────────────────────────────────────────────
        #
        # An evaluator's own title names the whole of it. A policy is written
        # in checks — `executive_summary:text_quality` — and each of those
        # carries a name its author gave it too: "Summary Substantial". That is
        # the name a scorer goes by wherever one check is being talked about
        # rather than the evaluator behind it.

        # @param evaluator [String, Symbol, nil] the name a result recorded
        # @param key [String, Symbol] "field:evaluator_type", or the field
        #   alone, which is how a result records what it graded
        # @return [Hash, nil] the declared check
        def check(evaluator, key)
          path, type = key.to_s.split(":", 2)
          declared = checks_for(evaluator).select { |entry| entry[:field_name].to_s == path }
          return declared.find { |entry| entry[:evaluator_type].to_s == type } if type

          # With one check on the field there is nothing to confuse it with.
          # With several and no type to tell them apart, naming it would put
          # another rule's name over these figures.
          declared.first if declared.one?
        end

        # The check's declared name, or the last segment of the key spelled as
        # words: the field ahead of the colon is already the heading it sits
        # under, so `confidence:value_range` falls back to "value range".
        def check_label(evaluator, key)
          check(evaluator, key)&.dig(:display_name).presence ||
            key.to_s.split(":").last.to_s.tr("_", " ")
        end

        private

        # Building these evaluates every field block the evaluator declares, so
        # it happens once per evaluator and never for a screen that asks for no
        # check.
        def checks_for(evaluator)
          key = evaluator.to_s
          return [] if key.empty?

          @checks ||= {}
          @checks.fetch(key) { @checks[key] = declared_checks(key) }
        end

        def declared_checks(evaluator)
          klass = evaluator_class(evaluator)
          return [] unless klass.respond_to?(:evaluated_checks)

          Array(klass.evaluated_checks)
        rescue StandardError
          []
        end

        def resolve(name)
          klass = evaluator_class(name)
          return nil unless klass.respond_to?(:display_name)

          klass.display_name.presence
        rescue StandardError
          nil
        end

        # The class the name stands for. The registry answers for everything
        # an application registered with `evaluator_name`; the custom-evaluator
        # search behind it answers for the rest, since a class that declares no
        # name is registered under the one derived from its constant and a
        # policy may name it either way.
        #
        # The class is asked for its title directly rather than through
        # `EvaluatorDiscovery.get_details`, which would build every check the
        # evaluator declares — a table of twenty scorers would evaluate a
        # hundred field blocks to render twenty words.
        def evaluator_class(name)
          return nil unless defined?(RAAF::Eval::DSL::EvaluatorRegistry)

          RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name.to_sym)
        rescue RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError
          custom_evaluator_class(name)
        end

        def custom_evaluator_class(name)
          return nil unless defined?(RAAF::Eval::Continuous::EvaluatorDiscovery)

          RAAF::Eval::Continuous::EvaluatorDiscovery.find_custom_evaluator_by_name(name)
        end
      end
    end
  end
end
