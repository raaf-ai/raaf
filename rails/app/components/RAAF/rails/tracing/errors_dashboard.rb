# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # Monitor › Errors: one row per distinct failure, as RAAF Console.dc.html
      # draws it.
      #
      # The design gives this screen a single table of signatures and nothing
      # else. What it dropped was a KPI row counting the errors the table
      # already counts, and a second list of individual failures underneath —
      # which is the same data ungrouped, so the one noisy signature at the top
      # of the table filled it and hid everything else.
      #
      # A signature is the pair the {SpanRecord.error_signatures} rollup groups
      # on: exception class and message. The trend beside each is that
      # signature's count against the same length of time immediately before
      # the window, which is what says whether the fix is working.
      #
      class ErrorsDashboard < BaseComponent
        # Columns and fr weights taken from RAAF Console.dc.html, plus the
        # three the Overview's Failing now panel already gave each signature
        # and this screen did not: how many runs it touched, how fast it is
        # arriving, and when it started. Clicking through to the dedicated
        # screen used to lose all three.
        COLUMNS = [
          { label: "Error signature", span: 2.2 },
          { label: "Agent", span: 1.0 },
          { label: "Traces", span: 0.6, align: :right },
          { label: "Count", span: 0.7, align: :right },
          { label: "Trend", span: 0.7, align: :right },
          { label: "First seen", span: 0.85, align: :right },
          { label: "Last seen", span: 0.85, align: :right }
        ].freeze

        # @param signatures [Array<Hash>] rows from SpanRecord.error_signatures
        def initialize(signatures: [], params: {})
          @signatures = signatures.to_a
          @params = params
        end

        def view_template
          div(class: "raaf-page") do
            filters
            render(Organisms::Card.new(flush: true)) do
              render(Organisms::DataGrid.new(columns: COLUMNS, empty: empty_state)) do |grid|
                visible_signatures.each { |signature| row(grid, signature) }
              end
            end
          end
        end

        private

        # A chip per failing agent, and a query over the exception and its
        # message. Every other list screen in the console opens with a rail;
        # this one sent the reader back to the range control for its only
        # narrowing.
        #
        # The chip counts are taken over all the signatures rather than the
        # filtered ones, so the rail stays a fixed point to filter against.
        def filters
          render(Molecules::FilterBar.new(chips: agent_chips, panel: true,
                                          query: @params[:q], action: dashboard_errors_path,
                                          placeholder: "Search exceptions…",
                                          carry: { range: @params[:range], agent: @params[:agent] }))
        end

        def agent_chips
          counts = @signatures.group_by { |signature| signature[:agent].to_s }
                              .transform_values { |group| group.sum { |row| row[:count].to_i } }

          all = [{ label: "All", active: @params[:agent].blank?,
                   count: @signatures.sum { |row| row[:count].to_i }.nonzero?,
                   href: dashboard_errors_path(filter_params(agent: nil)) }]

          all + counts.sort_by { |_, count| -count }.map { |agent, count| agent_chip(agent, count) }
        end

        def agent_chip(agent, count)
          { label: agent.presence || "unnamed", active: @params[:agent].to_s == agent,
            count: count, href: dashboard_errors_path(filter_params(agent: agent)) }
        end

        # Keeps the range and the query, so narrowing to one agent does not
        # silently reset the window the counts were read over.
        def filter_params(overrides)
          { range: @params[:range], agent: @params[:agent], q: @params[:q] }
            .merge(overrides).compact.reject { |_, value| value.to_s.empty? }
        end

        def visible_signatures
          @visible_signatures ||= @signatures.select { |signature| matches?(signature) }
        end

        def matches?(signature)
          return false if @params[:agent].present? && signature[:agent].to_s != @params[:agent]
          return true if @params[:q].blank?

          "#{signature[:exception]} #{signature[:message]}".downcase.include?(@params[:q].to_s.downcase)
        end

        # Two empty states, because they mean opposite things. Nothing failed
        # is good news; nothing matched is a filter the reader can clear, and
        # a screen that says "Nothing failed" over an active filter is lying
        # about the window.
        def empty_state
          if @params[:agent].present? || @params[:q].present?
            { icon: "funnel", title: "No signature matches",
              text: "Clear the filters to see every failure in this range." }
          else
            { icon: "check-circle", title: "Nothing failed",
              text: "Failures in the selected range are grouped here by exception." }
          end
        end

        # To the newest span carrying the signature rather than to its trace:
        # the span detail is where the backtrace and the arguments that
        # produced it are, and the trace is one click on from there.
        def row(grid, signature)
          grid.row(href: trace_span_path(signature[:span_id], signature[:trace_id]), cells: [
                     { value: signature_cell(signature), primary: true },
                     { value: Atoms::Mono.new(signature[:agent], tone: :muted) },
                     { value: Atoms::Mono.new(number(signature[:traces]), tone: :muted), align: :right },
                     { value: count_cell(signature), align: :right },
                     { value: trend_cell(signature[:trend]), align: :right },
                     { value: Atoms::Mono.new(time_ago(signature[:first_seen] || signature[:last_seen]),
                                              tone: :muted), align: :right },
                     { value: Atoms::Mono.new(time_ago(signature[:last_seen]), tone: :muted),
                       align: :right }
                   ])
        end

        # The count with its arrival rate under it. A signature that fired
        # forty times over a week and one that fired forty times in a minute
        # are the same number and different emergencies.
        def count_cell(signature)
          Molecules::TitleMeta.new(number(signature[:count]), rate_phrase(signature), mono: true)
        end

        # Occurrences a minute across the stretch the signature has been
        # firing. Under one a minute the rate rounds away to nothing worth
        # reading, so the cell says nothing rather than "0/min".
        def rate_phrase(signature)
          minutes = firing_minutes(signature)
          return nil if minutes.nil? || signature[:count].to_i < 2

          per_minute = signature[:count].to_f / minutes
          "#{per_minute.round}/min" if per_minute >= 1
        end

        def firing_minutes(signature)
          first = signature[:first_seen]
          last = signature[:last_seen]
          return nil unless first && last

          minutes = (last - first) / 60.0
          minutes.positive? ? minutes : nil
        end

        def signature_cell(signature)
          Molecules::TitleMeta.new(signature[:exception], signature[:message],
                                   mono: true, tone: :bad)
        end

        # Rising is the only direction worth alarming about, so a fall is read
        # as good and a signature that has not moved stays quiet.
        def trend_cell(trend)
          return Atoms::Mono.new("new", tone: :warn) if trend.nil?
          return Atoms::Mono.new("— 0%", tone: :muted) if trend.zero?

          arrow = trend.positive? ? "▲" : "▼"
          Atoms::Mono.new("#{arrow} #{trend.abs}%", tone: trend.positive? ? :bad : :ok)
        end

        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end
      end
    end
  end
end
