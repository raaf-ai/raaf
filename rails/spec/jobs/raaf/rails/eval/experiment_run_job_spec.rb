# frozen_string_literal: true

require "rails_helper"

# Running an experiment in the controller was safe only while it did nothing.
# Now that a run executes the agent once per dataset item and scores each
# answer, it is a long sequence of model calls and belongs off the request.
RSpec.describe RAAF::Rails::Eval::ExperimentRunJob, type: :job do
  let(:dataset) { RAAF::Eval::Models::Dataset.create!(name: "Briefings #{SecureRandom.hex(3)}") }

  let(:experiment) do
    RAAF::Eval::Models::Experiment.create!(name: "Briefing run", dataset: dataset,
                                           agent_name: "Briefer", model: "gpt-4o")
  end

  it "runs the experiment through the engine" do
    engine = instance_double(RAAF::Eval::ExperimentEngine)
    allow(RAAF::Eval::ExperimentEngine).to receive(:new).and_return(engine)
    expect(engine).to receive(:run_experiment).with(experiment)

    described_class.perform_now(experiment.id)
  end

  # A deleted experiment is not a failure worth retrying against.
  it "does nothing for an experiment that is gone" do
    expect(RAAF::Eval::ExperimentEngine).not_to receive(:new)

    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  # The engine records the experiment as failed itself, so the job has nothing
  # left to salvage and re-running the whole dataset would only cost money.
  it "swallows a failed run rather than retrying the dataset" do
    engine = instance_double(RAAF::Eval::ExperimentEngine)
    allow(RAAF::Eval::ExperimentEngine).to receive(:new).and_return(engine)
    allow(engine).to receive(:run_experiment).and_raise(StandardError, "provider down")

    expect { described_class.perform_now(experiment.id) }.not_to raise_error
  end
end
