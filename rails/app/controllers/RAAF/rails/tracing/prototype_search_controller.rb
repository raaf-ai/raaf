# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # PROTOTYPE — throwaway. Delete with the branch it lives on.
      #
      # Three variants of a "Search" plugin screen, switchable via `?variant=`,
      # on the throwaway route /raaf/prototype/search. Charted for
      # prospects-radar/prospects_radar#1091, under the map #1088.
      #
      # The question is what a non-AI content source looks like as a console
      # section, and the three variants disagree about the one thing that
      # decides the contract: what the list unit is.
      #
      #   A — Call log      one provider call is the row
      #   B — Spend board   one provider is the row, calls are a drill-down
      #   C — Run ledger    one buying run is the row, calls nest under it
      #
      # Data is real: SearchCostTracking, 14.5k rows, unscoped. Two things it
      # does not carry are left visibly missing rather than faked, because
      # their absence is itself an answer for the contract — duration, which
      # only the span has, and the returned URLs and snippets, which only
      # collect_result_attributes writes.
      #
      class PrototypeSearchController < ApplicationController
        VARIANTS = %w[A B C].freeze

        # Two calls by the same account and agent inside this gap are read as
        # one buying run. The real plugin would use the parent trace id; this
        # store has none, and inferring it is the cheapest way to see whether
        # the run is the unit worth designing for.
        RUN_GAP_SECONDS = 120

        def show
          return head(:not_found) if ::Rails.env.production?

          @variant = VARIANTS.include?(params[:variant].to_s.upcase) ? params[:variant].to_s.upcase : "A"
          @calls = load_calls

          render_in_layout component, title: "Search (prototype #{@variant})", crumb: "Prototype", live: false
        end

        private

        def component
          case @variant
          when "B" then Prototype::SearchSpendBoard.new(calls: @calls, params: prototype_params)
          when "C" then Prototype::SearchRunLedger.new(calls: @calls, runs: runs, params: prototype_params)
          else Prototype::SearchCallLog.new(calls: @calls, params: prototype_params)
          end
        end

        def prototype_params
          params.permit(:variant, :provider, :call, :run, :q).to_h.symbolize_keys
        end

        Call = Struct.new(:id, :at, :provider, :query, :results, :cost_usd, :account_id,
                          :agent, :model, :metadata, keyword_init: true)

        def load_calls
          model = "SearchCostTracking".safe_constantize
          return [] unless model

          unscoped_rows(model).map do |row|
            Call.new(
              id: row.id, at: row.created_at, provider: row.provider.to_s,
              query: row.search_query.to_s, results: row.result_count.to_i,
              cost_usd: row.cost_usd.to_f, account_id: row.account_id,
              agent: row.agent_class.to_s, model: row.model.to_s,
              metadata: row.metadata.is_a?(Hash) ? row.metadata : {}
            )
          end
        end

        def unscoped_rows(model)
          fetch = -> { model.order(created_at: :desc).limit(600).to_a }
          defined?(ActsAsTenant) ? ActsAsTenant.without_tenant(&fetch) : fetch.call
        end

        # Calls grouped into inferred buying runs, newest first.
        def runs
          @calls.group_by { |call| [ call.account_id, call.agent ] }
                .flat_map { |(account_id, agent), calls| split_by_gap(calls).map { |group| run_for(account_id, agent, group) } }
                .sort_by { |run| run[:started_at] }.reverse
        end

        def split_by_gap(calls)
          calls.sort_by(&:at).slice_when { |a, b| (b.at - a.at) > RUN_GAP_SECONDS }.to_a
        end

        def run_for(account_id, agent, group)
          { id: "#{account_id}-#{agent}-#{group.first.id}", account_id: account_id, agent: agent,
            calls: group.sort_by(&:at).reverse, started_at: group.first.at, ended_at: group.last.at,
            cost_usd: group.sum(&:cost_usd), results: group.sum(&:results),
            providers: group.map(&:provider).uniq.sort, empty: group.count { |c| c.results.zero? } }
        end
      end
    end
  end
end
