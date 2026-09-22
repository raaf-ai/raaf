# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # A prompt and its versions.
      #
      # Three of the four controls on this screen used to do nothing. "New
      # Version" linked to the page you were already on; "Publish" and
      # "Archive" were anchors pointing at routes the routes file declares
      # +post+ only, so following one raised a routing error. They are a link
      # to a real form and two +button_to+ posts now.
      #
      # Nothing linked the diff either, though the route and the screen both
      # existed. Every version below the newest offers a comparison against
      # the one after it, which is the comparison a version history is read
      # for.
      #
      class PromptShow < RAAF::Rails::Tracing::BaseComponent
        VERSION_COLUMNS = [
          { label: "Version", span: 0.6 },
          { label: "Status", span: 0.7 },
          { label: "Message", span: 1.8 },
          { label: "Model", span: 0.9 },
          { label: "Created by", span: 0.8 },
          { label: "Created", span: 0.9, align: :right },
          { label: "", span: 1.4, align: :right }
        ].freeze

        def initialize(prompt:, versions:, active_version:)
          @prompt = prompt
          @versions = versions.to_a
          @active_version = active_version
        end

        def view_template
          div(class: "raaf-page") do
            actions
            header_panel
            active_panel
            versions_panel
          end
        end

        private

        def actions
          render Molecules::RowActions.new(class: "raaf-page-actions", actions: [
                                             { label: "New version",
                                               href: new_version_path }
                                           ])
        end

        def header_panel
          render Organisms::RecordHead.new(
            title: @prompt.name,
            mono: true,
            description: @prompt.description,
            status: @active_version ? "published" : "draft",
            meta: head_meta,
            stats: [{ label: "Versions", value: @versions.size.to_s },
                    { label: "Active", value: active_label }]
          )
        end

        def head_meta
          [@prompt.agent_name.presence && "agent #{@prompt.agent_name}",
           @prompt.created_at&.strftime("created %Y-%m-%d")].compact.join(" · ")
        end

        def active_label
          @active_version ? "v#{@active_version.version_number}" : "—"
        end

        # ── The published version ─────────────────────────────────────────

        def active_panel
          render(Organisms::Card.new(title: "Published version", subtitle: active_subtitle)) do
            if @active_version
              render Atoms::CodeBlock.new(@active_version.content, height: :tall)
            else
              render Molecules::EmptyState.new(
                icon: "file-earmark-text", title: "Nothing published",
                text: "Create a version and publish it to make it the one agents run."
              )
            end
          end
        end

        def active_subtitle
          return nil unless @active_version

          ["v#{@active_version.version_number}",
           @active_version.model.presence].compact.join(" · ")
        end

        # ── History ───────────────────────────────────────────────────────

        def versions_panel
          render(Organisms::Card.new(title: "Version history", flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: VERSION_COLUMNS,
                     empty: { icon: "clock-history", title: "No versions",
                              text: "A prompt with no versions has nothing to run." }
                   )) do |grid|
              @versions.each_with_index { |version, index| version_row(grid, version, index) }
            end
          end
        end

        # No row href: a row carrying `button_to` controls cannot itself be a
        # link, since the form would be nested inside the anchor.
        def version_row(grid, version, index)
          grid.row(cells: [
                     { value: Atoms::Mono.new("v#{version.version_number}"), primary: true },
                     { value: Atoms::StatusBadge.new(version.status) },
                     { value: version.commit_message.presence || "—" },
                     { value: Atoms::Mono.new(version.model.presence || "—", tone: :muted) },
                     { value: Atoms::Mono.new(version.created_by.presence || "—", tone: :muted) },
                     { value: Atoms::Mono.new(created_at(version), tone: :muted), align: :right },
                     { value: row_actions(version, index), align: :right }
                   ])
        end

        def created_at(version)
          version.created_at&.strftime("%Y-%m-%d %H:%M") || "—"
        end

        # The comparison a version history is read for is "what changed in
        # this one", so a version is diffed against the one before it. The
        # oldest has nothing before it and offers no diff.
        def row_actions(version, index)
          previous = @versions[index + 1]

          Molecules::RowActions.new(actions: [
            (diff_action(previous, version) if previous),
            (publish_action(version) if version.draft?),
            (archive_action(version) unless version.archived?)
          ].compact)
        end

        def diff_action(previous, version)
          { label: "Diff", href: diff_eval_prompt_path(@prompt, from: previous.version_number,
                                                                to: version.version_number) }
        end

        def publish_action(version)
          { label: "Publish", href: version_member_path(version, "publish"), method: :post,
            confirm: "Publish v#{version.version_number}? " \
                     "It becomes the version agents run." }
        end

        def archive_action(version)
          { label: "Archive", href: version_member_path(version, "archive"), method: :post,
            tone: :danger, confirm: "Archive v#{version.version_number}?" }
        end

        def version_member_path(version, action)
          "#{eval_prompt_path(@prompt)}/versions/#{version.id}/#{action}"
        end

        def new_version_path
          "#{eval_prompt_path(@prompt)}/versions/new"
        end
      end
    end
  end
end
