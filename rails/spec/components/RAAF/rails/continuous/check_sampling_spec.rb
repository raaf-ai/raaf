# frozen_string_literal: true

require "rails_helper"

# Sampling is configured per check in the editor, and on save the controller
# forces the policy's sampling_mode to every_n and sets the policy-level
# sample_every_n to the minimum across all checks. The list's Sample column and
# the detail's Configuration row then printed that synthesised value.
RSpec.describe RAAF::Rails::Continuous::CheckSampling do
  let(:reader) { Class.new { include RAAF::Rails::Continuous::CheckSampling }.new }

  def evaluator(checks:, modes: {}, every_n: {}, rates: {}, triggers: {})
    { "name" => "quality", "checks" => checks,
      "check_sampling_modes" => modes, "check_sample_every_n" => every_n,
      "check_sample_rates" => rates, "check_trigger_modes" => triggers }
  end

  def policy(evaluators, sampling_mode: "every_n", sample_every_n: 10, sample_rate: 0)
    instance_double("EvaluationPolicy", evaluators: evaluators,
                                        sampling_mode: sampling_mode,
                                        sample_every_n: sample_every_n,
                                        sample_rate: sample_rate)
  end

  # The case from the ticket: the policy row read "1/10" and was wrong about
  # the other check, which was invisible outside the edit form.
  describe "two checks sampled differently" do
    let(:mixed) do
      policy([evaluator(checks: %w[a:quality b:quality],
                        modes: { "a:quality" => "every_n", "b:quality" => "every_n" },
                        every_n: { "a:quality" => 10, "b:quality" => 100 })])
    end

    it "reports each check's own rate" do
      expect(reader.check_sampling(mixed).map { |entry| entry[:sampling] })
        .to eq(%w[1/10 1/100])
    end

    it "refuses to pick one of them for the whole policy" do
      expect(reader.policy_sampling_label(mixed)).to eq("varies")
      expect(reader.policy_sampling_cell(mixed)).to eq("2 rates")
    end
  end

  describe "checks that agree" do
    it "reports the rate they agree on" do
      agreed = policy([evaluator(checks: %w[a:quality b:quality],
                                 modes: { "a:quality" => "every_n", "b:quality" => "every_n" },
                                 every_n: { "a:quality" => 10, "b:quality" => 10 })])

      expect(reader.policy_sampling_label(agreed)).to eq("1/10")
      expect(reader.policy_sampling_cell(agreed)).to eq("1/10")
    end

    it "reads a percentage check as a percentage" do
      percentage = policy([evaluator(checks: %w[a:quality],
                                     modes: { "a:quality" => "percentage" },
                                     rates: { "a:quality" => 25 })])

      expect(reader.policy_sampling_label(percentage)).to eq("25%")
    end

    # check_sample_every_n only carries a value where one was entered.
    it "does not read a missing stride as 1/0" do
      defaulted = policy([evaluator(checks: %w[a:quality],
                                    modes: { "a:quality" => "every_n" })])

      expect(reader.policy_sampling_label(defaulted)).to eq("every span")
    end
  end

  describe "trigger mode" do
    it "is reported per check" do
      manual = policy([evaluator(checks: %w[a:quality b:quality],
                                 triggers: { "a:quality" => "manual" })])

      expect(reader.check_sampling(manual).map { |entry| entry[:trigger] })
        .to eq(%w[manual automatic])
      expect(reader.manual_checks?(manual)).to be(true)
    end
  end

  # A policy with no checks has nothing per-check to say, so its own columns
  # are all there is.
  it "falls back to the policy's own columns where it declares no checks" do
    empty = policy([])

    expect(reader.policy_sampling_label(empty)).to eq("every 10th span")
    expect(reader.policy_sampling_cell(empty)).to eq("1/10")
  end
end
