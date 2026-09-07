# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # StatusBadge — a trace or span status pill.
        #
        # Owns the only mapping from a run status to a colour. The tracer uses
        # several words for the same four states, so they are normalised here
        # rather than at every call site.
        #
        class StatusBadge < Base
          STATES = {
            "ok" => :completed, "completed" => :completed, "success" => :completed,
            "running" => :running, "pending" => :running, "queued" => :running,
            "error" => :failed, "failed" => :failed, "timeout" => :failed,
            "skipped" => :skipped, "cancelled" => :skipped,
            # A policy is not a run, but it reads on the same pill: one is
            # working, the other is not.
            "active" => :completed, "paused" => :skipped,
            # An evaluation's own verdicts. "average" is an outcome, not a
            # state — it had been borrowing the running pill and reading as
            # "Running", which says something else entirely.
            "good" => :completed, "average" => :warned,
            "bad" => :failed,
            # A scorer's own condition, from the Health screen. "stale" is not
            # a fault, so it takes the idle pill rather than the red one: the
            # scorer is fine and nothing has asked it anything.
            "healthy" => :completed, "drifting" => :warned, "stale" => :skipped
          }.freeze

          DOTS = { completed: :ok, running: :info, warned: :warn, failed: :bad,
                   skipped: :idle }.freeze

          # @param status [String, Symbol]
          # @param dot [Boolean] show a leading state dot
          def initialize(status, dot: true, class: nil, **attrs)
            @status = status
            @dot = dot
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            state = resolved

            span(class: tokens("raaf-status", "raaf-status--#{state}", @class), **@attrs) do
              render Dot.new(tone: DOTS.fetch(state, :idle), pulse: state == :running) if @dot
              plain label
            end
          end

          private

          def resolved
            STATES.fetch(@status.to_s.downcase, :skipped)
          end

          def label
            @status.to_s.empty? ? "unknown" : @status.to_s.tr("_-", "  ").capitalize
          end
        end
      end
    end
  end
end
