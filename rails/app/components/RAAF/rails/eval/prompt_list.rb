# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # The prompt listing, from the Prompts screen in RAAF Eval.dc.html: one
      # table where a row is a prompt, the version it is on, what model that
      # version targets, which agent uses it and when it last moved.
      #
      # The canvas draws the table alone. The filter rail above it is this
      # screen's own: the controller already filters by agent, and creating a
      # prompt needs a button somewhere.
      #
      class PromptList < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Eval.dc.html.
        COLUMNS = [
          { label: "Prompt", span: 2.2 },
          { label: "Version", span: 0.7, align: :right },
          { label: "Model", span: 1.1 },
          { label: "Used by", span: 1.5 },
          { label: "Updated", span: 0.85, align: :right }
        ].freeze

        # @param prompts [Enumerable<Prompt>] the rows to draw
        # @param agents [Array<String>] every agent a prompt names
        # @param filters [Hash] :agent, as the controller read it
        def initialize(prompts:, agents: [], filters: {})
          @prompts = prompts
          @agents = agents || []
          @filters = filters || {}
        end

        def view_template
          div(class: "raaf-page") do
            filters
            table
          end
        end

        private

        def filters
          render(Molecules::FilterBar.new(panel: true, lead: agent_filter)) do
            render Atoms::Mono.new(pluralize(@prompts.size, "prompt"), tone: :muted)
            render Atoms::Button.new(label: "New prompt", icon: "plus-lg", size: :sm,
                                     href: "#{eval_prompts_path}/new")
          end
        end

        def agent_filter
          Molecules::ScopeFilter.new(
            name: "agent", value: @filters[:agent], options: @agents,
            action: eval_prompts_path, prefix: "agent"
          )
        end

        def table
          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "file-text", title: "No prompts",
                              text: "Nothing is under version control here yet." }
                   )) do |grid|
              @prompts.each { |prompt| row(grid, prompt) }
            end
          end
        end

        def row(grid, prompt)
          grid.row(href: eval_prompt_path(prompt), cells: [
                     { value: Molecules::TitleMeta.new(prompt.name, prompt.description.presence,
                                                       mono: true) },
                     { value: Atoms::Mono.new("v#{prompt.latest_version}"), align: :right },
                     { value: Atoms::Mono.new(model_for(prompt), tone: :muted) },
                     { value: Atoms::Mono.new(prompt.agent_name.presence || "no agent",
                                              tone: :muted) },
                     { value: Atoms::Mono.new(time_ago(prompt.updated_at), tone: :muted),
                       align: :right }
                   ])
        end

        # The model the newest version targets. Picked out of the preloaded
        # association rather than ordered in SQL, which would be a query per
        # row and undo the controller's `includes`.
        def model_for(prompt)
          latest = prompt.prompt_versions.max_by(&:version_number)

          latest&.model.presence || "—"
        end
      end
    end
  end
end
