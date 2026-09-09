# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # One case from a dataset, in full.
      #
      # The list truncates Input and Expected at 160 characters, so any case
      # longer than a sentence could not be read from the console at all —
      # though `dataset_items#show` was routed the whole time and answered
      # JSON. This is the HTML the row now opens.
      #
      class DatasetItemShow < RAAF::Rails::Tracing::BaseComponent
        def initialize(dataset:, item:)
          @dataset = dataset
          @item = item
        end

        def view_template
          div(class: "raaf-page") do
            header
            payload("Input", @item.input)
            payload("Expected output", @item.expected_output) if @item.has_expected_output?
            metadata_panel if metadata.any?
          end
        end

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: @dataset.name, href: eval_dataset_path(@dataset) },
            title: "Item ##{@item.id}",
            mono: true,
            description: description,
            meta: head_meta,
            badges: [source_badge]
          )
        end

        # A case imported from a real failure and one written by hand are
        # tested identically and trusted differently, so the screen says which
        # this is before it says anything else about it.
        def description
          if @item.from_production?
            "Imported from a production span, so this case is a run that really happened."
          else
            "Written by hand."
          end
        end

        def head_meta
          [@item.created_at&.strftime("added %Y-%m-%d"),
           (@item.has_expected_output? ? "has an expected output" : "no expected output")]
            .compact.join(" · ")
        end

        def source_badge
          if @item.from_production?
            Atoms::Badge.new("Span", variant: :"tint-cyan", size: :sm)
          else
            Atoms::Badge.new("Manual", variant: :"tint-slate", size: :sm)
          end
        end

        # Whole, and not truncated: reading the case is the only reason to be
        # on this screen.
        def payload(title, body)
          render(Organisms::Card.new(title: title, flush: true)) do
            render Atoms::CodeBlock.new(body, height: :tall)
          end
        end

        def metadata_panel
          render(Organisms::Card.new(title: "Metadata", flush: true)) do
            render Molecules::KeyValueList.new(pairs: metadata, layout: :rows, mono: true, flush: true)
          end
        end

        def metadata
          @metadata ||= begin
            recorded = @item.metadata
            recorded.is_a?(Hash) ? recorded.transform_values(&:to_s) : {}
          end
        end
      end
    end
  end
end
