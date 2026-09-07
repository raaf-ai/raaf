# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # The experiment editor, from the `isEdit` screen in RAAF Eval.dc.html:
      # Identity, Run configuration, Scorers and Schedule & alerts in a column,
      # beside a sticky rail holding the pending diff, what the next run will
      # do, and the actions.
      #
      # **Where the values go.** `raaf_experiments` has columns for name,
      # description, dataset, agent, model and provider, and nothing else the
      # screen edits. The rest is written to `configuration` and `metadata` —
      # both jsonb that already ships — so an install already running gains
      # this screen without a migration. `Experiment::SETTINGS`,
      # `#scorers`, `#schedule` and `#tags` are the only readers of that
      # shape.
      #
      # **Where the scorers come from.** The picker lists checks from
      # `EvaluatorDiscovery`, which is the same registry the continuous policy
      # form reads. An experiment and a policy therefore weight the same named
      # scorers, and a new evaluator appears on both screens at once.
      #
      # **What the engine acts on today.** `ExperimentEngine` builds its agent
      # from what the caller passes it and takes scoring as a block, so the
      # run settings and scorer weights saved here are the experiment's
      # declared configuration rather than instructions the engine already
      # follows. The "Next run" panel says only what is true of the next run.
      #
      class ExperimentEdit < RAAF::Rails::Tracing::BaseComponent
        Experiment = RAAF::Eval::Models::Experiment

        TRIGGER_LABELS = {
          "manual" => "Manual only",
          "nightly" => "Nightly",
          "weekly" => "Weekly",
          "cron" => "Cron"
        }.freeze

        # Weights are a judgement, not a constraint — a set that does not total
        # 1.0 still saves. The header just says so.
        FULL_WEIGHT = 1.0

        # @param experiment [RAAF::Eval::Models::Experiment]
        # @param datasets [Array<Dataset>] selectable datasets
        # @param agents [Array<String>] agent names seen in the trace store
        # @param scorers [Array<Hash>] :key, :evaluator, :check, :label, :note
        def initialize(experiment:, datasets: [], agents: [], scorers: [])
          @experiment = experiment
          @datasets = datasets
          @agents = agents
          @available = scorers
        end

        def view_template
          div(class: "raaf-page") do
            errors if @experiment.errors.any?

            # `scope:` is not optional here. The model is
            # `RAAF::Eval::Models::Experiment`, so `form_with` would name every
            # field `raaf_eval_models_experiment[…]` while the controller reads
            # `params[:experiment]` — and the label `for` attributes below
            # would point at ids that do not exist.
            form_with(model: @experiment, scope: :experiment,
                      url: eval_experiment_path(@experiment),
                      method: :patch, data: form_data) do |f|
              div(class: "raaf-editor") do
                div(class: "raaf-editor-main") do
                  identity(f)
                  run_configuration(f)
                  scorers(f)
                  schedule(f)
                end

                aside(class: "raaf-editor-side") do
                  pending_changes
                  next_run
                  actions
                end
              end
            end
          end
        end

        private

        def form_data
          { controller: "experiment-edit",
            experiment_edit_full_weight_value: FULL_WEIGHT }
        end

        def errors
          render(Molecules::Alert.new(:error, title: error_title)) do
            ul(class: "raaf-alert-list") do
              @experiment.errors.full_messages.each { |message| li { message } }
            end
          end
        end

        def error_title
          "#{pluralize(@experiment.errors.count, 'problem')} stopped this experiment being saved"
        end

        # ── Identity ──────────────────────────────────────────────────────

        def identity(form)
          render(Organisms::Card.new(title: "Identity")) do
            div(class: "raaf-field-grid") do
              field("Experiment name", "experiment_name") do
                form.text_field(:name, class: input_class(mono: true), required: true,
                                       **tracked("Name", @experiment.name))
              end

              field("Agent under test", "experiment_agent_name") do
                form.select(:agent_name, agent_options, { include_blank: "No agent set" },
                            { class: select_class(mono: true),
                              **tracked("Agent", @experiment.agent_name) })
              end

              field("Dataset", "experiment_dataset_id") do
                form.select(:dataset_id, dataset_options, {},
                            { class: select_class(mono: true), required: true,
                              **tracked("Dataset", dataset_label(@experiment.dataset)) })
              end

              field("Tags", "experiment_tags",
                    hint: "Comma separated. Used to group experiments in listings.") do
                input(type: "text", name: "experiment[tags]", id: "experiment_tags",
                      value: @experiment.tags.join(", "), class: input_class,
                      **tracked("Tags", @experiment.tags.join(", ")))
              end

              field("Description", "experiment_description", wide: true) do
                form.text_area(:description, rows: 2, class: textarea_class,
                                             **tracked("Description", @experiment.description))
              end
            end
          end
        end

        def agent_options
          # The saved agent stays selectable even when nothing has traced under
          # that name lately, so opening the form cannot silently clear it.
          (@agents.map(&:to_s) + [@experiment.agent_name.to_s]).reject(&:empty?).uniq.sort
        end

        def dataset_options
          @datasets.map { |dataset| [dataset_label(dataset), dataset.id] }
        end

        def dataset_label(dataset)
          return nil if dataset.nil?

          "#{dataset.name} · v#{dataset.version} · #{pluralize(dataset.items_count.to_i, 'item')}"
        end

        # ── Run configuration ─────────────────────────────────────────────

        def run_configuration(form)
          render(Organisms::Card.new(title: "Run configuration")) do
            div(class: "raaf-field-grid") do
              field("Model", "experiment_model") do
                form.text_field(:model, class: input_class(mono: true), placeholder: "gpt-4o",
                                        **tracked("Model", @experiment.model))
              end

              field("Provider", "experiment_provider",
                    hint: "Blank lets RAAF detect it from the model name.") do
                form.text_field(:provider, class: input_class(mono: true), placeholder: "openai",
                                           **tracked("Provider", @experiment.provider))
              end

              temperature
              setting_number("Max turns", "max_turns", min: 1, max: 20, step: 1)
              setting_number("Concurrency", "concurrency", min: 1, max: 32, step: 1)
              setting_number("Timeout · seconds", "timeout_seconds", min: 5, max: 300, step: 1)
            end
          end
        end

        def temperature
          value = @experiment.setting("temperature").to_f

          div(class: "raaf-field raaf-field--wide") do
            div(class: "raaf-slider-head") do
              render Atoms::Label.new("Temperature", for_id: "experiment_temperature")
              render Atoms::Mono.new("%.2f" % value, tone: :accent,
                                                     data: { experiment_edit_target: "temperatureValue" })
            end

            # The diff compares against what the control reports, and a range
            # normalises "0.30" to "0.3" — so the tracked value is the raw one,
            # not the two-decimal label beside it.
            input(type: "range", id: "experiment_temperature", class: "raaf-slider",
                  name: "experiment[configuration][temperature]",
                  min: 0, max: 1, step: 0.05, value: value,
                  data: { action: "input->experiment-edit#temperatureChanged",
                          **tracked_data("Temperature", value.to_s) })

            p(class: "raaf-input-hint") { temperature_note(value) }
          end
        end

        # The slider is a number without a meaning until you say what the ends
        # do, and this note is the only place the screen says it.
        def temperature_note(value)
          case value
          when 0...0.2 then "Near-deterministic — the run is repeatable, and a regression is the agent's, not the sampler's."
          when 0.2...0.8 then "Some variation between runs. Compare across several items rather than one."
          else "Highly variable. Scores from a single run say little at this setting."
          end
        end

        def setting_number(label, key, min:, max:, step:)
          value = @experiment.setting(key)

          field(label, "experiment_#{key}") do
            input(type: "number", id: "experiment_#{key}", class: input_class(mono: true),
                  name: "experiment[configuration][#{key}]",
                  min: min, max: max, step: step, value: value,
                  **tracked(label, value))
          end
        end

        # ── Scorers ───────────────────────────────────────────────────────

        def scorers(_form)
          render(Organisms::Card.new(title: "Scorers", flush: true)) do |card|
            card.actions { weight_total }

            if @available.empty?
              render Molecules::EmptyState.new(
                icon: "sliders",
                title: "No scorers registered",
                text: "Scorers come from the evaluator registry. Register an evaluator and it " \
                      "appears here and on the continuous policies at the same time."
              )
            else
              @available.each_with_index { |scorer, index| scorer_row(scorer, index) }
            end
          end
        end

        def weight_total
          total = @experiment.weight_total
          off = (total - FULL_WEIGHT).abs > 0.001

          render Atoms::Mono.new("weights total #{'%.2f' % total}",
                                 class: off ? "raaf-weight-total--off" : nil,
                                 data: { experiment_edit_target: "weightTotal" })
        end

        def scorer_row(scorer, index)
          saved = saved_scorer(scorer[:key])
          prefix = "experiment[configuration][scorers][#{index}]"

          div(class: "raaf-scorer-edit#{' is-off' unless saved[:enabled]}",
              data: { experiment_edit_target: "scorerRow" }) do
            hidden("#{prefix}[key]", scorer[:key])
            hidden("#{prefix}[evaluator]", scorer[:evaluator])
            hidden("#{prefix}[check]", scorer[:check])
            # An unchecked toggle posts nothing, so the off state needs its own
            # field or a scorer switched off would keep its last saved value.
            hidden("#{prefix}[enabled]", "0")

            span(class: "raaf-scorer-edit-body") do
              render Atoms::Mono.new(scorer[:label], class: "raaf-scorer-edit-name")
              span(class: "raaf-scorer-edit-note") { scorer[:note] } if scorer[:note].present?
            end

            scorer_number("Weight", "#{prefix}[weight]", saved[:weight], step: 0.1,
                                                                         label_for: "scorer_#{index}_weight",
                                                                         tracked_as: "#{scorer[:label]} weight")

            scorer_number("Threshold", "#{prefix}[threshold]", saved[:threshold], step: 0.01,
                                                                                  label_for: "scorer_#{index}_threshold",
                                                                                  tracked_as: "#{scorer[:label]} threshold")

            render Atoms::Toggle.new(
              name: "#{prefix}[enabled]", value: "1", checked: saved[:enabled],
              data: { action: "change->experiment-edit#scorerToggled",
                      **tracked_data("#{scorer[:label]} scoring", saved[:enabled] ? "on" : "off") }
            )
          end
        end

        def scorer_number(text, name, value, step:, label_for:, tracked_as:)
          div(class: "raaf-scorer-edit-num") do
            render Atoms::Label.new(text, for_id: label_for)
            input(type: "number", id: label_for, name: name, value: value,
                  min: 0, max: 1, step: step,
                  class: "raaf-input raaf-input--glass raaf-input--sm raaf-input--mono",
                  **tracked(tracked_as, value))
          end
        end

        # A scorer the experiment has never saved starts off, with no weight —
        # picking it up is a decision, and a default weight would quietly make
        # every registered scorer count. The zero is an Integer so the field
        # reads "0" rather than "0.0", which a number input renders in the
        # reader's locale and turns into "0,0" on a Dutch host.
        def saved_scorer(key)
          @saved_scorers ||= @experiment.scorers.index_by { |scorer| scorer[:key] }
          @saved_scorers.fetch(key, { enabled: false, weight: 0, threshold: nil })
        end

        # ── Schedule & alerts ─────────────────────────────────────────────

        def schedule(_form)
          saved = @experiment.schedule

          render(Organisms::Card.new(title: "Schedule & alerts")) do
            div(class: "raaf-stack") do
              trigger(saved)

              div(class: "raaf-field-grid") do
                field("Cron expression", "experiment_cron",
                      hint: "Read only when the trigger is Cron.") do
                  # Two targets on one element. Stimulus reads the attribute as
                  # a space-separated list, and merging the hashes would drop
                  # one of them — the target key is the same key twice.
                  input(type: "text", id: "experiment_cron", class: input_class(mono: true),
                        name: "experiment[configuration][schedule][cron]",
                        value: saved[:cron], placeholder: "0 2 * * *",
                        disabled: saved[:trigger] != "cron",
                        data: tracked_data("Cron", saved[:cron])
                              .merge(experiment_edit_target: "cron field"))
                end

                field("Notify channel", "experiment_notify", optional: true,
                                                             hint: "Where a breach is announced.") do
                  input(type: "text", id: "experiment_notify", class: input_class(mono: true),
                        name: "experiment[configuration][schedule][notify]",
                        value: saved[:notify], placeholder: "#raaf-evals",
                        **tracked("Notify", saved[:notify]))
                end

                field("Alert below composite", "experiment_alert_below", optional: true,
                                                                         hint: "Blank raises no alert.") do
                  input(type: "number", id: "experiment_alert_below", class: input_class(mono: true),
                        name: "experiment[configuration][schedule][alert_below]",
                        value: saved[:alert_below], min: 0, max: 1, step: 0.01,
                        **tracked("Alert below", saved[:alert_below]))
                end
              end
            end
          end
        end

        def trigger(saved)
          div(class: "raaf-field") do
            render Atoms::Label.new("Trigger")

            div(class: "raaf-pillset", role: "radiogroup", "aria-label": "Trigger") do
              Experiment::SCHEDULE_TRIGGERS.each { |value| trigger_pill(value, saved[:trigger]) }
            end
          end
        end

        # Every radio in the group carries the *saved* trigger as its initial,
        # not its own label. A radio that carried its own would always match
        # itself when checked, and the group could never report a change.
        def trigger_pill(value, selected)
          id = "experiment_trigger_#{value}"

          input(type: "radio", id: id, class: "raaf-pill-radio",
                name: "experiment[configuration][schedule][trigger]",
                value: value, checked: value == selected,
                data: { action: "change->experiment-edit#triggerChanged",
                        **tracked_data("Trigger", TRIGGER_LABELS[selected]) })
          label(for: id, class: "raaf-pill") { TRIGGER_LABELS[value] }
        end

        # ── Pending changes ───────────────────────────────────────────────

        def pending_changes
          render(Organisms::Card.new(title: "Pending changes", flush: true)) do |card|
            card.actions do
              render Atoms::Badge.new("Saved", variant: :"soft-slate", size: :sm,
                                               data: { experiment_edit_target: "dirtyBadge" })
            end

            div(data: { experiment_edit_target: "changes" })

            p(class: "raaf-diff-empty", data: { experiment_edit_target: "changesEmpty" }) do
              "Nothing edited yet. Changes appear here as a diff before you save, and the next " \
                "run picks them up."
            end
          end
        end

        # ── Next run ──────────────────────────────────────────────────────

        # Only what is true of the next run. The design's fourth row is an
        # estimated cost; nothing prices a dataset before it runs, so the row
        # is the last run's cost where there is one, and absent where not.
        def next_run
          render(Organisms::Card.new(title: "Next run", flush: true)) do
            next_run_facts.each { |label, value| fact(label, value) }
          end
        end

        def next_run_facts
          items = @experiment.dataset&.items_count.to_i

          [["Items", items.positive? ? items.to_s : "—"],
           ["Scorers", enabled_scorer_count],
           ["Trigger", TRIGGER_LABELS[@experiment.schedule[:trigger]]],
           ["Last run", last_run]]
        end

        def enabled_scorer_count
          count = @experiment.scorers.count { |scorer| scorer[:enabled] }
          count.zero? ? "none enabled" : pluralize(count, "scorer")
        end

        def last_run
          return "never" if @experiment.completed_at.nil?

          time_ago(@experiment.completed_at)
        end

        def fact(label, value)
          div(class: "raaf-editor-fact") do
            span(class: "raaf-editor-fact-label") { label }
            render Atoms::Mono.new(value)
          end
        end

        # ── Actions ───────────────────────────────────────────────────────

        def actions
          div(class: "raaf-editor-actions") do
            button(type: "submit", class: "raaf-button") { "Save changes" }

            button(type: "button", class: "raaf-button raaf-button--secondary",
                   data: { action: "experiment-edit#revert" }) { "Revert to saved" }

            link_to("Back to experiment", eval_experiment_path(@experiment),
                    class: "raaf-editor-back")
          end
        end

        # ── Shared ────────────────────────────────────────────────────────

        def field(label, for_id, hint: nil, optional: false, wide: false, &block)
          render(Molecules::Field.new(label: label, for_id: for_id, hint: hint,
                                      optional: optional,
                                      class: wide ? "raaf-field--wide" : nil), &block)
        end

        # The bare input classes are the light-theme ones; on this console they
        # are always wrong, so every control here carries the glass modifier.
        def input_class(mono: false)
          ["raaf-input", "raaf-input--glass", ("raaf-input--mono" if mono)].compact.join(" ")
        end

        def select_class(mono: false)
          "#{input_class(mono: mono)} raaf-select"
        end

        def textarea_class
          "#{input_class} raaf-textarea"
        end

        def hidden(name, value)
          input(type: "hidden", name: name, value: value)
        end

        # Every editable control announces its label and the value it was
        # loaded with, which is all the diff panel needs — no second copy of
        # the record has to be kept in the page for it to compare against.
        def tracked(label, value)
          { data: tracked_data(label, value) }
        end

        def tracked_data(label, value)
          { experiment_edit_target: "field",
            diff_label: label,
            diff_initial: value.to_s }
        end
      end
    end
  end
end
