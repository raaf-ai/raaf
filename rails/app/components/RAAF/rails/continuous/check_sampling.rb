# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # How often each of a policy's checks actually fires, and on whose say-so.
      #
      # Sampling is configured per check in the editor, and the controller
      # keeps it that way: each evaluator carries `check_sampling_modes`,
      # `check_sample_rates`, `check_sample_every_n` and `check_trigger_modes`,
      # keyed by check name. What it *also* does on save is force the policy's
      # own `sampling_mode` to `every_n` and set the policy-level
      # `sample_every_n` to the minimum across every check.
      #
      # The list's Sample column and the detail's Configuration row printed
      # that synthesised minimum. A policy with one check at 1/10 and one at
      # 1/100 read "1/10" on the list and "every 10th span" on the detail —
      # wrong for one of the two — and the 1/100 check was invisible anywhere
      # outside the edit form.
      #
      # These read the per-check values instead, and say "varies" rather than
      # picking one of them when the checks disagree.
      #
      # A check that declares no sampling of its own inherits the policy's,
      # because that is what actually runs: EvaluationPolicy#check_and_increment_counter
      # consults `sample_every_n` on the policy and never looks at the per-check
      # maps at all. Only the editor writes those maps, so a policy declared in
      # code carries none of them — and reading a missing override as "every
      # span" told every such policy it graded everything while it sampled one
      # span in twenty.
      #
      module CheckSampling
        # Every check on the policy with the sampling and trigger it was
        # configured with.
        #
        # @return [Array<Hash>] :evaluator, :check, :sampling, :trigger
        def check_sampling(policy)
          Array(policy.evaluators).flat_map do |evaluator|
            next [] unless evaluator.is_a?(Hash)

            checks_of(evaluator).map { |check| check_entry(policy, evaluator, check) }
          end.uniq { |entry| entry[:check] }
        end

        # One phrase for the whole policy: the sampling if every check agrees,
        # and an honest "varies" if they do not.
        def policy_sampling_label(policy)
          phrases = check_sampling(policy).map { |entry| entry[:sampling] }.uniq
          return policy_fallback_label(policy) if phrases.empty?
          return phrases.first if phrases.one?

          "varies"
        end

        # The same, short enough for a table cell.
        def policy_sampling_cell(policy)
          entries = check_sampling(policy)
          phrases = entries.map { |entry| entry[:sampling] }.uniq
          return policy_fallback_cell(policy) if phrases.empty?
          return phrases.first if phrases.one?

          "#{phrases.size} rates"
        end

        # A check whose trigger is manual does not fire on its own however it
        # is sampled, which is the more important half of "how often does this
        # run" and appeared nowhere outside the edit form.
        def manual_checks?(policy)
          check_sampling(policy).any? { |entry| entry[:trigger] == "manual" }
        end

        private

        def checks_of(evaluator)
          Array(evaluator["checks"] || evaluator[:checks]).map(&:to_s)
        end

        def check_entry(policy, evaluator, check)
          { evaluator: (evaluator["name"] || evaluator[:name]).to_s,
            check: check,
            sampling: sampling_phrase(policy, evaluator, check),
            trigger: setting(evaluator, "check_trigger_modes", check) || "automatic" }
        end

        def sampling_phrase(policy, evaluator, check)
          case setting(evaluator, "check_sampling_modes", check)
          when "percentage" then "#{setting(evaluator, 'check_sample_rates', check).to_i}%"
          when "every_n" then every_n_phrase(policy, evaluator, check)
          else policy_fallback_cell(policy)
          end
        end

        # `check_sample_every_n` only carries a value where one was entered, so
        # a check left on the default falls back to the policy's own stride
        # rather than being reported as "1/0".
        def every_n_phrase(policy, evaluator, check)
          every = setting(evaluator, "check_sample_every_n", check).to_i

          every.positive? ? "1/#{every}" : policy_fallback_cell(policy)
        end

        def setting(evaluator, group, check)
          values = evaluator[group] || evaluator[group.to_sym] || {}
          return nil unless values.is_a?(Hash)

          values[check].nil? ? values[check.to_sym] : values[check]
        end

        # A policy that declares no checks has nothing per-check to report, so
        # its own columns are all there is.
        def policy_fallback_label(policy)
          case policy.sampling_mode
          when "every_n" then "every #{policy.sample_every_n}th span"
          when "percentage" then "#{policy.sample_rate}% of spans"
          else "every span"
          end
        end

        def policy_fallback_cell(policy)
          case policy.sampling_mode
          when "every_n" then "1/#{policy.sample_every_n}"
          when "percentage" then "#{policy.sample_rate}%"
          else "all"
          end
        end
      end
    end
  end
end
