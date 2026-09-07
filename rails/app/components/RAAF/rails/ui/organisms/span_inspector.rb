# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # SpanInspector — one span, beside the waterfall.
        #
        # Tabs over the same span: one for each part of the payload it recorded,
        # then the error if it failed, its token and cost accounting, and the
        # raw record. Which tab is showing is a URL parameter rather than client
        # state, so a link to a span can point at the tab that explains it.
        #
        # A message carrying an +:id+ claims the tab of that name, together
        # with every other message carrying it -- which is how a conversation
        # is shown as one block per turn rather than one wall of JSON.
        # Messages without an id are all shown together, which is what a
        # caller that still passes a single "payload" tab expects.
        #
        # @example
        #   render Organisms::SpanInspector.new(
        #     kind: "tool", name: "crm_upsert", tab: :error,
        #     meta: ["4.0s", "tool · faraday", "0 tokens"],
        #     tabs: [{ id: :payload, label: "Payload", href: "?tab=payload" }],
        #     error: { klass: "Faraday::TimeoutError", message: "execution expired" }
        #   )
        #
        class SpanInspector < Base
          # @param kind [String]
          # @param name [String]
          # @param tab [Symbol, String] the tab currently showing
          # @param tabs [Array<Hash>] :id, :label, :href
          # @param meta [Array<Hash, String>] the header's figures; a Hash may
          #   carry :value and :tone
          # @param messages [Array<Hash>] payload tabs; an entry carrying
          #   :results is rendered as a Molecules::ResultList and one carrying
          #   :pairs as a Molecules::KeyValueList, and anything else is passed
          #   to Molecules::PayloadBlock. Its optional :id names the tab it
          #   belongs to
          # @param error [Hash, nil] error tab; see Molecules::ErrorCallout
          # @param tokens [Array<Hash>] tokens tab; :label, :value, :tone
          # @param raw [String, nil] raw tab
          # @param actions [Array<Hash>] controls on the title row, each a set
          #   of arguments for Atoms::Button. What can be done *to* the span
          #   belongs here rather than under a tab, which is where what the
          #   span *recorded* is read.
          def initialize(kind:, name:, tab: :payload, tabs: [], meta: [], messages: [],
                         error: nil, tokens: [], raw: nil, actions: [], class: nil, **attrs)
            @kind = kind
            @name = name
            @tab = tab.to_s
            @tabs = tabs
            @meta = meta
            @messages = messages
            @error = error
            @token_rows = tokens
            @raw = raw
            @actions = Array(actions)
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            section(class: tokens("raaf-inspector", @class), "aria-label": "Span inspector", **@attrs) do
              head
              tab_strip if @tabs.any?
              div(class: "raaf-inspector-panel") { panel }
            end
          end

          private

          def head
            div(class: "raaf-inspector-head") do
              div(class: "raaf-inspector-title") do
                render Atoms::KindBadge.new(@kind)
                span(class: "raaf-inspector-name") { @name }
                actions if @actions.any?
              end
              div(class: "raaf-inspector-meta") do
                @meta.each { |item| meta_item(item) }
              end
            end
          end

          def actions
            div(class: "raaf-inspector-actions") do
              @actions.each { |action| render Atoms::Button.new(size: :sm, **action) }
            end
          end

          def meta_item(item)
            if item.is_a?(Hash)
              render Atoms::Mono.new(item[:value], tone: item[:tone])
            else
              render Atoms::Mono.new(item, tone: :muted)
            end
          end

          def tab_strip
            render Molecules::Tabs.new(
              class: "raaf-inspector-tabs",
              items: @tabs.map do |item|
                { label: item[:label], href: item[:href], active: item[:id].to_s == @tab }
              end
            )
          end

          def panel
            case @tab
            when "error" then error_panel
            when "tokens" then tokens_panel
            when "raw" then raw_panel
            else payload_panel
            end
          end

          def payload_panel
            shown = messages_for_tab

            if shown.empty?
              render Molecules::EmptyState.new(icon: "braces", title: "No payload captured",
                                               text: "This span recorded no messages.")
              return
            end

            # The index only matters when the tab was built from more than one
            # message -- see {block_args}.
            shown.each_with_index do |message, index|
              payload_entry(message, shown.length > 1 ? index : nil)
            end
          end

          # A message is one of three shapes, and it says which by the key it
          # carries: +:results+ for a ranked list of search hits, +:pairs+ for
          # a span whose vocabulary has no section of its own and is showing
          # its attributes, and a body for everything else.
          def payload_entry(message, index = nil)
            if message[:results]
              render Molecules::ResultList.new(items: message[:results])
            elsif message[:pairs]
              render(Molecules::KeyValueList.new(layout: :rows)) do
                message[:pairs].each { |key, value| pair_row(key, value) }
              end
            else
              render Molecules::PayloadBlock.new(**block_args(message, index))
            end
          end

          # One fact per row, and a value that arrived as pretty-printed JSON —
          # a response format, a handoff's context — in a block of its own.
          # The row layout puts a value in a wrapping div, which folds the
          # indentation away and prints a schema back as the single line it
          # was recorded as.
          def pair_row(key, value)
            if value.to_s.include?("\n")
              render(Molecules::KeyValue.new(key, value, class: "raaf-kv--block")) do
                render Atoms::CodeBlock.new(value, height: :flush)
              end
            else
              render Molecules::KeyValue.new(key, value, mono: true)
            end
          end

          # The messages this tab is for: the one that claims it by id, or all
          # of them for a caller that names no tabs of its own.
          def messages_for_tab
            claimed = @messages.select { |message| message[:id].to_s == @tab }
            return claimed if claimed.any?

            @messages.any? { |message| message[:id].present? } ? [] : @messages
          end

          # PayloadBlock takes an id, for its reveal checkbox, but not a label
          # — which would otherwise reach the markup as an HTML attribute. The
          # same is true of the keys that pick a shape above.
          #
          # The id is the tab's, and a tab built from several messages — a
          # conversation, which is one block per turn — would hand every one
          # of them the same checkbox id. Every veil in the tab would then
          # point at the first block's checkbox, so revealing one turn either
          # revealed the wrong one or nothing at all. Numbered when there is
          # more than one, left alone when there is not, so the ids a single
          # section has always had do not move.
          def block_args(message, index)
            args = message.except(:label, :results, :pairs)
            return args if index.nil? || args[:id].blank?

            args.merge(id: "#{args[:id]}-#{index}")
          end

          def error_panel
            if @error.nil?
              render Molecules::EmptyState.new(icon: "check-circle", title: "No error",
                                               text: "This span completed without raising.")
              return
            end

            render Molecules::ErrorCallout.new(**@error)
          end

          # A span that is billed per token and consumed none has nothing to
          # account for, and a column of zeros would claim it had been
          # measured. Which spans get this tab at all is the caller's call.
          def tokens_panel
            if @token_rows.empty?
              render Molecules::EmptyState.new(icon: "coin", title: "Nothing billed",
                                               text: "This span recorded no tokens and no cost.")
              return
            end

            div(class: "raaf-inspector-rows") do
              @token_rows.each do |row|
                div(class: "raaf-inspector-row") do
                  span(class: "raaf-inspector-row-label") { row[:label] }
                  render Atoms::Mono.new(row[:value], tone: row[:tone])
                end
              end
            end
          end

          def raw_panel
            render Atoms::CodeBlock.new(@raw, height: :tall, class: "raaf-inspector-raw")
          end
        end
      end
    end
  end
end
