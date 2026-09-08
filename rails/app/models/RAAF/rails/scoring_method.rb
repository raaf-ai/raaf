# frozen_string_literal: true

module RAAF
  module Rails
    ##
    # What did the scoring: a model that was asked for an opinion, a statistic
    # taken across runs, or a rule computed from the output.
    #
    # Every eval screen prints scores and until now none of them said which of
    # those a number was. The three read alike — a bar between 0 and 1 — and
    # mean different things: a judge's 0.7 is a second opinion that can be
    # argued with and costs a model call, a rule's 0.7 is arithmetic that will
    # give the same answer tomorrow. A reader deciding whether to trust a
    # verdict, or asking why a policy is expensive, needs the difference in
    # front of them.
    #
    # The type is declared per check on the evaluator and written onto each
    # result when it is scored, so this reads it back off the row rather than
    # asking the evaluator class what it would say today.
    #
    module ScoringMethod
      # Several checks behind one number, and they are not all the same kind.
      MIXED = "mixed"

      module_function

      # @param check [Hash, nil] one declared check, string or symbol keyed
      # @return [String, nil] its type, or nil where it declares none
      def type_of(check)
        return nil unless check.is_a?(Hash)

        value = (check[:check_type] || check["check_type"]).to_s
        return nil if value.empty? || value == "unknown"

        value
      end

      # The one type a set of checks shares, or {MIXED} where they differ.
      #
      # @param checks [Array<Hash>, nil]
      # @return [String, nil] nil where nothing declares a type
      def of_checks(checks)
        types = Array(checks).filter_map { |check| type_of(check) }.uniq
        return nil if types.empty?

        types.one? ? types.first : MIXED
      end

      # How one continuous result was scored.
      #
      # The checks the row itself recorded come first: they are what ran, and
      # they are per field, so a row is typed by the checks behind its own
      # number rather than by whatever else its evaluator does elsewhere.
      # `evaluator_type` is the fallback — it is copied from the policy's
      # evaluator config, where an evaluator that runs one judge among four
      # rules is still declared rule_based.
      #
      # @param result [#details, #evaluator_type]
      # @param judged [Boolean] the caller found a judge transcript on the row.
      #   Only consulted where the checks say nothing: a recorded call is proof
      #   a model was asked, which no declaration can outrank.
      # @return [String, nil]
      def for_result(result, judged: false)
        of_checks(declared_checks(result)) ||
          (judged ? "llm_judge" : nil) ||
          result.evaluator_type.to_s.presence
      end

      # The checks a continuous result recorded for itself. Written as JSON,
      # so the keys come back as strings.
      #
      # @return [Array<Hash>]
      def declared_checks(result)
        stored = result.details&.dig("declared_checks") || result.details&.dig(:declared_checks)
        stored.is_a?(Array) ? stored.grep(Hash) : []
      end
    end
  end
end
