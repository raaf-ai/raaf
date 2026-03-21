# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # Prompt represents a named, versioned prompt registry entry.
      # Inspired by Opik's prompt management for tracking prompt evolution.
      #
      # Each Prompt has multiple PromptVersions, enabling rollback and comparison.
      #
      # @example Creating a prompt with initial version
      #   prompt = Prompt.create!(
      #     name: "customer_support_v1",
      #     agent_name: "CustomerSupportAgent",
      #     description: "Main prompt for customer support interactions"
      #   )
      #   prompt.create_version!(
      #     content: "You are a helpful customer support agent...",
      #     model: "gpt-4o",
      #     commit_message: "Initial prompt"
      #   )
      #
      # @example Getting the active version
      #   active = prompt.active_version
      #   puts active.content
      class Prompt < ActiveRecord::Base
        self.table_name = "raaf_prompts"

        # Associations
        has_many :prompt_versions,
                 class_name: "RAAF::Eval::Models::PromptVersion",
                 foreign_key: :prompt_id,
                 dependent: :destroy

        # Validations
        validates :name, presence: true, uniqueness: true

        # Scopes
        scope :for_agent, ->(agent_name) { where(agent_name: agent_name) }
        scope :recent, -> { order(updated_at: :desc) }

        ##
        # Create a new version of this prompt
        # @param content [String] The prompt content
        # @param model [String] Target model
        # @param model_parameters [Hash] Model parameters
        # @param commit_message [String] Description of changes
        # @param created_by [String] Who created this version
        # @return [PromptVersion]
        def create_version!(content:, model: nil, model_parameters: {}, commit_message: nil, created_by: nil)
          next_version = latest_version + 1

          version = prompt_versions.create!(
            version_number: next_version,
            content: content,
            model: model,
            model_parameters: model_parameters,
            commit_message: commit_message,
            created_by: created_by,
            status: "draft"
          )

          update!(latest_version: next_version)
          version
        end

        ##
        # Get the currently active (published) version
        # @return [PromptVersion, nil]
        def active_version
          prompt_versions.published.order(version_number: :desc).first
        end

        ##
        # Get a specific version
        # @param version_number [Integer] Version number
        # @return [PromptVersion, nil]
        def version(version_number)
          prompt_versions.find_by(version_number: version_number)
        end

        ##
        # Get the latest version (any status)
        # @return [PromptVersion, nil]
        def latest
          prompt_versions.order(version_number: :desc).first
        end

        ##
        # Get diff between two versions
        # @param from_version [Integer] Start version number
        # @param to_version [Integer] End version number
        # @return [Hash] Diff information
        def diff(from_version, to_version)
          v1 = version(from_version)
          v2 = version(to_version)
          return nil unless v1 && v2

          {
            from: { version: from_version, content: v1.content, model: v1.model },
            to: { version: to_version, content: v2.content, model: v2.model },
            content_changed: v1.content != v2.content,
            model_changed: v1.model != v2.model,
            parameters_changed: v1.model_parameters != v2.model_parameters
          }
        end

        ##
        # Get version history
        # @return [Array<Hash>] Version summaries
        def history
          prompt_versions.order(version_number: :desc).map do |v|
            {
              version: v.version_number,
              status: v.status,
              commit_message: v.commit_message,
              created_by: v.created_by,
              model: v.model,
              created_at: v.created_at
            }
          end
        end
      end
    end
  end
end
