# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # Dataset represents a collection of test cases for systematic agent evaluation.
      # Inspired by Opik's dataset management with versioning support.
      #
      # Datasets contain items (input/expected_output pairs) that can be used to run
      # experiments comparing agent behavior across different configurations.
      #
      # @example Creating a dataset
      #   dataset = Dataset.create!(
      #     name: "Customer Support QA",
      #     description: "Common customer queries with expected responses",
      #     schema_definition: {
      #       input: { query: :string, context: :string },
      #       expected_output: { response: :string, category: :string }
      #     }
      #   )
      #
      # @example Adding items from production spans
      #   dataset.add_item_from_span(span_record)
      #
      # @example Creating a new version
      #   new_version = dataset.create_new_version!
      class Dataset < ActiveRecord::Base
        self.table_name = "raaf_datasets"

        # Associations
        has_many :dataset_items,
                 class_name: "RAAF::Eval::Models::DatasetItem",
                 foreign_key: :dataset_id,
                 dependent: :destroy
        has_many :experiments,
                 class_name: "RAAF::Eval::Models::Experiment",
                 foreign_key: :dataset_id,
                 dependent: :nullify

        # Validations
        validates :name, presence: true
        validates :version, presence: true, numericality: { greater_than: 0 }
        validates :status, presence: true, inclusion: { in: %w[active archived] }
        validates :name, uniqueness: { scope: :version, message: "already exists for this version" }

        # Scopes
        scope :active, -> { where(status: "active") }
        scope :archived, -> { where(status: "archived") }
        scope :by_name, ->(name) { where(name: name) }
        scope :latest_versions, -> {
          where("version = (SELECT MAX(d2.version) FROM raaf_datasets d2 WHERE d2.name = raaf_datasets.name)")
        }
        scope :recent, -> { order(created_at: :desc) }

        ##
        # Add a test case item to this dataset
        # @param input [Hash] The input data
        # @param expected_output [Hash] The expected output
        # @param metadata [Hash] Optional metadata
        # @return [DatasetItem]
        def add_item(input:, expected_output: {}, metadata: {})
          item = dataset_items.create!(
            input: input,
            expected_output: expected_output,
            metadata: metadata
          )
          increment!(:items_count)
          item
        end

        ##
        # Add a test case from a production span
        # @param span_data [Hash] Span data with input/output messages
        # @return [DatasetItem]
        def add_item_from_span(span_data)
          input = extract_input_from_span(span_data)
          expected_output = extract_output_from_span(span_data)

          add_item(
            input: input,
            expected_output: expected_output,
            metadata: {
              source_span_id: span_data[:span_id] || span_data["span_id"],
              source_trace_id: span_data[:trace_id] || span_data["trace_id"],
              imported_at: Time.current.iso8601
            }
          )
        end

        ##
        # Create a new version of this dataset, duplicating all items
        # @param created_by [String] Who created the new version
        # @return [Dataset] The new versioned dataset
        def create_new_version!(created_by: nil)
          new_version = self.class.create!(
            name: name,
            description: description,
            version: version + 1,
            status: "active",
            created_by: created_by,
            schema_definition: schema_definition,
            metadata: metadata.merge("forked_from_version" => version)
          )

          dataset_items.find_each do |item|
            new_version.dataset_items.create!(
              input: item.input,
              expected_output: item.expected_output,
              metadata: item.metadata.merge("copied_from_item_id" => item.id)
            )
          end

          new_version.update!(items_count: dataset_items.count)
          new_version
        end

        ##
        # Archive this dataset version
        def archive!
          update!(status: "archived")
        end

        ##
        # Check if this is the latest version
        # @return [Boolean]
        def latest_version?
          self.class.where(name: name).maximum(:version) == version
        end

        private

        def extract_input_from_span(span_data)
          messages = span_data[:input_messages] || span_data["input_messages"] ||
                     span_data.dig(:span_data, :input_messages) ||
                     span_data.dig("span_data", "input_messages") || []
          { messages: messages }
        end

        def extract_output_from_span(span_data)
          messages = span_data[:output_messages] || span_data["output_messages"] ||
                     span_data.dig(:span_data, :output_messages) ||
                     span_data.dig("span_data", "output_messages") || []
          { messages: messages }
        end
      end
    end
  end
end
