# frozen_string_literal: true

require "spec_helper"

require_relative "../../../../../app/components/RAAF/rails/ui/base"
require_relative "../../../../../app/components/RAAF/rails/ui/molecules/stat_card"
require_relative "../../../../../app/components/RAAF/rails/ui/organisms/stat_grid"

# The console had two KPI tiles doing the same job in different halves of
# itself, and a reader met a different KPI row every second screen with no
# change of subject to justify it. `StatCard` now carries both presentations;
# this is the step where every screen moves onto it.
#
# Both checks read source rather than rendered HTML on purpose. `StatCard`
# aliases the health dialect onto the surviving vocabulary, so a tile that
# still says `:bad` renders byte-identically to one that says `:danger` — the
# thing being migrated is the word, and the word is only visible in the source.
module RAAF
  module Rails
    module Ui
      RSpec.describe "the console's KPI tiles" do
        COMPONENT_ROOT = File.expand_path("../../../../../app/components/RAAF/rails", __dir__)

        # The superseded tile and the grid that exists only to lay it out. Both
        # go in the contract step; until then they are the only two files
        # allowed to name the component.
        SUPERSEDED_FILES = %w[
          ui/molecules/metric_card.rb
          ui/organisms/metric_grid.rb
        ].freeze

        SUPERSEDED = /(?:Molecules::MetricCard|Organisms::MetricGrid|render_metric_card)/

        # Every method that decides what a KPI tile says, per screen — the
        # hashes themselves and the helpers they take a tone from. Listing them
        # is what makes the check exact: `:bad` is a correct word for a
        # `MeterRow` bar or a `Mono` figure on these same screens, and only the
        # tile has converged on the semantic set.
        TILE_METHODS = {
          "continuous/analytics_dashboard.rb" => %w[headline],
          "continuous/health_dashboard.rb" => %w[
            agreement_card agreement_tone latency_card error_card error_tone cost_card
          ],
          "continuous/policy_list.rb" => %w[headline],
          "continuous/queue_list.rb" => %w[
            stats waiting_stat in_flight_stat throughput_stat oldest_stat
          ],
          "eval/experiment_comparison.rb" => %w[
            metrics success_metric tokens_metric moved_metric regressed_metric delta_tone
          ],
          "eval/experiment_show.rb" => %w[metrics],
          "eval/feedback_score_list.rb" => %w[headline average_tone],
          "tracing/costs_index.rb" => %w[kpi_stats spend_tone cost_per_run_tone direction_tone],
          "tracing/dashboard_index.rb" => %w[kpis],
          "tracing/performance_dashboard.rb" => %w[kpis],
          "tracing/replay/show_component.rb" => %w[
            metrics duration_metric token_metric model_metric
          ],
          "ui/style_guide.rb" => %w[kpi_stats charts]
        }.freeze

        def self.source_of(relative_path)
          File.read(File.join(COMPONENT_ROOT, relative_path))
        end

        # A method body, from its `def` to the `end` at the same indentation.
        # Every component in this library is formatted that way, which is what
        # makes reading one out of the file honest rather than clever.
        def self.method_body(source, name)
          lines = source.lines
          start = lines.index { |line| line.match?(/^(\s*)def #{Regexp.escape(name)}\b/) }
          raise "no `def #{name}` in the source" unless start

          indent = lines[start][/^\s*/]
          finish = ((start + 1)...lines.size).find { |i| lines[i] == "#{indent}end\n" }
          raise "no `end` closing `def #{name}`" unless finish

          lines[start..finish].join
        end

        describe "the superseded tile" do
          let(:components) do
            Dir[File.join(COMPONENT_ROOT, "**", "*.rb")]
              .map { |path| path.delete_prefix("#{COMPONENT_ROOT}/") }
              .reject { |path| SUPERSEDED_FILES.include?(path) }
          end

          it "is rendered by nothing" do
            offenders = components.select { |path| self.class.source_of(path).match?(SUPERSEDED) }

            expect(offenders).to be_empty,
                                 "still rendering the superseded KPI tile: #{offenders.join(', ')}"
          end
        end

        # The screens that kept the icon-box tiles say so once for the row
        # rather than once for each of their four tiles.
        describe "the presentation a row declares" do
          def row(**args)
            Organisms::StatGrid.new(**args).call
          end

          let(:tiles) { [{ label: "Queued", value: "12" }, { label: "In flight", value: "3" }] }

          it "gives it to every tile in the row" do
            html = row(layout: :leading, stats: tiles)

            expect(html.scan("raaf-stat-card--leading").size).to eq(2)
          end

          it "leaves the tile's own shape alone when the row asks for nothing" do
            expect(row(stats: tiles)).not_to include("raaf-stat-card--leading")
          end

          # A tile that says where its icon goes means it, so the row does not
          # overrule it.
          it "yields to a tile that names its own" do
            html = row(layout: :leading, stats: [tiles.first.merge(layout: :corner)])

            expect(html).not_to include("raaf-stat-card--leading")
          end
        end

        # `TONE_ALIASES` exists so a screen that had not migrated yet still
        # rendered correctly. Once every screen has, nothing in the console
        # should need it, and the contract step can take it out.
        describe "the tone vocabulary" do
          retired = Molecules::StatCard::TONE_ALIASES.keys

          TILE_METHODS.each do |path, methods|
            it "is the surviving one throughout #{path}" do
              source = self.class.source_of(path)

              methods.each do |name|
                body = self.class.method_body(source, name)

                retired.each do |tone|
                  expect(body).not_to match(/:#{tone}(?![\w?!])/),
                                      "#{path}##{name} still says :#{tone}"
                end
              end
            end
          end
        end
      end
    end
  end
end
