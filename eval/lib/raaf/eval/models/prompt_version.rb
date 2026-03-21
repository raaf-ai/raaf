# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # PromptVersion represents a specific version of a prompt.
      # Supports draft/published/archived lifecycle for safe prompt management.
      #
      # @example Publishing a version
      #   version = prompt.create_version!(content: "New prompt...", commit_message: "Improve tone")
      #   version.publish!  # Makes this the active version
      #
      # @example Rolling back
      #   old_version = prompt.version(3)
      #   prompt.create_version!(
      #     content: old_version.content,
      #     commit_message: "Rollback to v3"
      #   ).publish!
      class PromptVersion < ActiveRecord::Base
        self.table_name = "raaf_prompt_versions"

        # Associations
        belongs_to :prompt,
                   class_name: "RAAF::Eval::Models::Prompt"

        # Validations
        validates :version_number, presence: true, numericality: { greater_than: 0 }
        validates :version_number, uniqueness: { scope: :prompt_id }
        validates :content, presence: true
        validates :status, presence: true, inclusion: { in: %w[draft published archived] }

        # Scopes
        scope :published, -> { where(status: "published") }
        scope :draft, -> { where(status: "draft") }
        scope :archived, -> { where(status: "archived") }
        scope :recent, -> { order(version_number: :desc) }
        scope :for_model, ->(model) { where(model: model) }

        ##
        # Publish this version, archiving any previously published version
        def publish!
          transaction do
            prompt.prompt_versions.published.update_all(status: "archived")
            update!(status: "published")
          end
        end

        ##
        # Archive this version
        def archive!
          update!(status: "archived")
        end

        ##
        # Check status predicates
        def published?
          status == "published"
        end

        def draft?
          status == "draft"
        end

        def archived?
          status == "archived"
        end

        ##
        # Get content length
        # @return [Integer]
        def content_length
          content&.length || 0
        end

        ##
        # Get a summary for display
        # @return [String]
        def summary
          "v#{version_number} (#{status}) - #{commit_message || 'No message'}"
        end
      end
    end
  end
end
