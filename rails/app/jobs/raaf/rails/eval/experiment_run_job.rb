# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # Runs an experiment over its dataset, off the web request.
      #
      # The console used to run one in the controller and return immediately,
      # which was safe only because the run did nothing: no agent was resolved,
      # so every case fell through to a dry run and came back in microseconds.
      # Now that an experiment executes its agent and scores what comes out, a
      # four-hundred-case dataset is four hundred model calls, and that is not
      # something to hold a request open for.
      #
      # The experiment's own status is the progress: `running` while this works,
      # `completed` or `failed` after, which the screen already reads and polls.
      #
      class ExperimentRunJob < RAAF::Rails::ApplicationJob
        queue_as :raaf_evaluations

        # An experiment that fails is recorded as failed by the engine itself,
        # so a retry would run the whole dataset again over an error the run
        # already owns.
        retry_on StandardError, attempts: 1

        # @param experiment_id [Integer]
        def perform(experiment_id)
          experiment = RAAF::Eval::Models::Experiment.find_by(id: experiment_id)
          return if experiment.nil?

          RAAF::Eval::ExperimentEngine.new.run_experiment(experiment)
        rescue StandardError => e
          ::Rails.logger.error "[ExperimentRunJob] Experiment #{experiment_id} failed: #{e.message}"
        end
      end
    end
  end
end
