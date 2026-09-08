# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for managing experiments
      class ExperimentsController < BaseController
        Experiment = RAAF::Eval::Models::Experiment
        Dataset = RAAF::Eval::Models::Dataset

        before_action :set_experiment, only: %i[show edit update destroy run cancel]

        # GET /raaf/eval/experiments
        def index
          # The list draws each experiment's dataset name, which is one query
          # per row without this.
          @experiments = Experiment.recent.includes(:dataset)
          @experiments = @experiments.for_agent(params[:agent]) if params[:agent].present?
          @experiments = @experiments.for_model(params[:model]) if params[:model].present?
          @experiments = @experiments.by_status(params[:status]) if params[:status].present?

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentList.new(
                experiments: @experiments,
                agents: Experiment.distinct.pluck(:agent_name).compact_blank.sort,
                filters: { status: params[:status], agent: params[:agent] }
              )
              render_in_layout component, title: "Experiments", crumb: "Evaluate", current: :experiments
            end
            format.json { render json: @experiments }
          end
        end

        # GET /raaf/eval/experiments/:id
        def show
          @results = @experiment.experiment_results.includes(:dataset_item).recent.limit(100)

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentShow.new(
                experiment: @experiment, results: @results,
                # The table shows a hundred rows; the screen says so only when
                # the run recorded more than that.
                total_results: @experiment.experiment_results.count
              )
              render_in_layout component, title: @experiment.name, crumb: "Evaluate", current: :experiments
            end
            format.json { render json: @experiment.as_json(include: :aggregate_metrics) }
          end
        end

        # GET /raaf/eval/experiments/new
        def new
          @experiment = Experiment.new
          @datasets = Dataset.active.latest_versions.recent

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentForm.new(experiment: @experiment, datasets: @datasets)
              render_in_layout component, title: "New Experiment"
            end
          end
        end

        # GET /raaf/eval/experiments/:id/edit
        def edit
          render_edit
        end

        # POST /raaf/eval/experiments
        def create
          @experiment = Experiment.new(experiment_params)
          if @experiment.save
            redirect_to eval_experiment_path(@experiment), notice: "Experiment created."
          else
            @datasets = Dataset.active.latest_versions.recent
            component = RAAF::Rails::Eval::ExperimentForm.new(experiment: @experiment, datasets: @datasets)
            render_in_layout component, title: "New Experiment", status: :unprocessable_content
          end
        end

        # PATCH /raaf/eval/experiments/:id
        def update
          if @experiment.update(experiment_update_params)
            redirect_to eval_experiment_path(@experiment), notice: "Experiment updated."
          else
            render_edit(status: :unprocessable_entity)
          end
        end

        # POST /raaf/eval/experiments/:id/run
        #
        # Queued rather than run here. The run executes the agent once per
        # dataset item and scores each answer, so a large dataset is a long
        # sequence of model calls — which the request that started it has no
        # business waiting for. The experiment's status carries the progress.
        def run
          RAAF::Rails::Eval::ExperimentRunJob.perform_later(@experiment.id)
          redirect_to eval_experiment_path(@experiment), notice: "Experiment queued."
        rescue StandardError => e
          redirect_to eval_experiment_path(@experiment), alert: "Could not queue experiment: #{e.message}"
        end

        # GET /raaf/eval/experiments/:id/compare?against=<id>
        #
        # A score on its own says nothing. This holds the run against another
        # run of the same dataset, which is the only comparison that means
        # anything: two runs over different cases have no item to line up and
        # their averages answer different questions.
        def compare
          candidates = comparable_experiments
          against = candidates.find { |run| run.id == params[:against].to_i }
          against ||= candidates.first

          comparison = against && RAAF::Eval::ExperimentEngine.new
                                                              .compare_experiments(against, @experiment)

          component = RAAF::Rails::Eval::ExperimentComparison.new(
            experiment: @experiment, against: against, candidates: candidates, comparison: comparison
          )
          render_in_layout component, title: "#{@experiment.name} · compare", crumb: "Evaluate",
                                      current: :experiments
        end

        # POST /raaf/eval/experiments/:id/cancel
        def cancel
          @experiment.cancel!
          redirect_to eval_experiment_path(@experiment), notice: "Experiment cancelled."
        end

        # DELETE /raaf/eval/experiments/:id
        def destroy
          @experiment.destroy
          redirect_to eval_experiments_path, notice: "Experiment deleted."
        end

        private

        def set_experiment
          @experiment = Experiment.find(params[:id])
        end

        def experiment_params
          params.require(:experiment).permit(
            :name, :description, :dataset_id, :agent_name, :model, :provider,
            :created_by, configuration: {}, metadata: {}
          )
        end

        def render_edit(status: :ok)
          component = RAAF::Rails::Eval::ExperimentEdit.new(
            experiment: @experiment,
            datasets: selectable_datasets,
            agents: selectable_agents,
            scorers: available_scorers
          )
          render_in_layout component, title: @experiment.name, crumb: "Evaluate", current: :experiments, status: status
        end

        # The editor writes name, description, dataset, agent, model and
        # provider to their columns; everything else the screen edits has no
        # column, so it is folded into `configuration` and `metadata` here.
        # The screen and this method are the only two places that shape is
        # written — `Experiment#setting`, `#scorers`, `#schedule` and `#tags`
        # are the only places it is read.
        def experiment_update_params
          permitted = params.require(:experiment).permit(
            :name, :description, :dataset_id, :agent_name, :model, :provider
          )

          permitted[:configuration] = merged_configuration
          permitted[:metadata] = merged_metadata
          permitted
        end

        def merged_configuration
          submitted = params.require(:experiment).fetch(:configuration, nil)
          return @experiment.configuration.to_h unless submitted.respond_to?(:permit)

          settings = submitted.permit(*Experiment::SETTINGS.keys).to_h
          settings = settings.transform_values { |value| numeric(value) }

          # Keys the screen does not edit — anything a host application put on
          # the experiment itself — survive the round trip.
          @experiment.configuration.to_h
                     .merge(settings)
                     .merge("scorers" => submitted_scorers(submitted),
                            "schedule" => submitted_schedule(submitted))
        end

        # The form posts every registered scorer, enabled or not, so the list
        # is rewritten wholesale rather than merged. A scorer that is off with
        # no weight is dropped instead of being stored as an empty row.
        def submitted_scorers(submitted)
          rows = submitted.fetch(:scorers, nil)
          return [] unless rows.respond_to?(:values)

          rows.values.filter_map do |row|
            next unless row.respond_to?(:permit)

            row = row.permit(:key, :evaluator, :check, :enabled, :weight, :threshold).to_h
            next if row["key"].blank?

            enabled = row["enabled"].to_s == "1"
            next if !enabled && row["weight"].to_f.zero? && row["threshold"].blank?

            { "key" => row["key"], "evaluator" => row["evaluator"], "check" => row["check"],
              "enabled" => enabled, "weight" => row["weight"].to_f,
              "threshold" => row["threshold"].presence&.to_f }
          end
        end

        def submitted_schedule(submitted)
          schedule = submitted.fetch(:schedule, nil)
          return @experiment.schedule.transform_keys(&:to_s) unless schedule.respond_to?(:permit)

          schedule = schedule.permit(:trigger, :cron, :notify, :alert_below).to_h
          trigger = schedule["trigger"].to_s
          trigger = "manual" unless Experiment::SCHEDULE_TRIGGERS.include?(trigger)

          { "trigger" => trigger,
            # A cron expression left behind by a trigger that no longer reads it
            # would be a rule nobody can see running.
            "cron" => trigger == "cron" ? schedule["cron"].to_s.strip : "",
            "notify" => schedule["notify"].to_s.strip,
            "alert_below" => schedule["alert_below"].presence&.to_f }
        end

        def merged_metadata
          tags = params.require(:experiment)[:tags]
          metadata = @experiment.metadata.to_h
          return metadata if tags.nil?

          metadata.merge("tags" => tags.to_s.split(",").map(&:strip).reject(&:empty?).uniq)
        end

        # Blank stays blank; "0.7" becomes a Float and "5" an Integer, so a
        # setting read back is the type it was written as.
        def numeric(value)
          string = value.to_s.strip
          return nil if string.empty?
          return string.to_i unless string.include?(".")

          string.to_f
        end

        def selectable_datasets
          Dataset.active.latest_versions.recent
        end

        # The evaluator registry knows which agents can be scored, and it is
        # the same source the continuous policy form picks from. Agents already
        # named by an experiment are added so an existing record's own agent is
        # never dropped from its picker.
        # The other runs of this dataset, newest first. A run still going has
        # nothing settled to compare, and comparing a run with itself answers
        # a question nobody asked.
        def comparable_experiments
          Experiment.where(dataset_id: @experiment.dataset_id)
                    .where.not(id: @experiment.id)
                    .where(status: %w[completed failed])
                    .order(completed_at: :desc, id: :desc)
                    .limit(50)
                    .to_a
        end

        def selectable_agents
          from_evaluators = available_evaluators.filter_map { |detail| detail[:agent_name] }
          (from_evaluators + Experiment.distinct.pluck(:agent_name)).compact_blank.uniq.sort
        end

        # One row per check, which is the unit a policy weights too — so an
        # experiment and a policy cannot end up naming the same scorer
        # differently.
        def available_scorers
          available_evaluators.flat_map do |detail|
            Array(detail[:checks]).filter_map { |check| scorer_entry(detail, check) }
          end
        end

        def scorer_entry(detail, check)
          if check.is_a?(Hash)
            field = check[:field_name] || check["field_name"]
            type = check[:evaluator_type] || check["evaluator_type"]
            name = [field, type].compact.join(":")
            label = check[:display_name] || check["display_name"]
            note = check[:description] || check["description"]
          else
            name = check.to_s
            label = nil
            note = detail[:description]
          end

          return nil if name.blank?

          { key: "#{detail[:name]}/#{name}",
            evaluator: detail[:name].to_s,
            check: name,
            label: label.presence || "#{detail[:name]} · #{name}",
            note: note }
        end

        def available_evaluators
          @available_evaluators ||=
            if defined?(RAAF::Eval::Continuous::EvaluatorDiscovery)
              RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
            else
              []
            end
        end
      end
    end
  end
end
