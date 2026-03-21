# frozen_string_literal: true

class CreateRaafPromptVersions < ActiveRecord::Migration[7.0]
  def change
    # Prompt registries (groups of versioned prompts)
    create_table :raaf_prompts do |t|
      t.string :name, null: false
      t.text :description
      t.string :agent_name
      t.integer :latest_version, null: false, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_prompts, :name, unique: true
    add_index :raaf_prompts, :agent_name

    # Individual prompt versions with full content tracking
    create_table :raaf_prompt_versions do |t|
      t.references :prompt, null: false, foreign_key: { to_table: :raaf_prompts }
      t.integer :version_number, null: false
      t.text :content, null: false
      t.string :model
      t.jsonb :model_parameters, default: {}
      t.string :commit_message
      t.string :created_by
      t.string :status, null: false, default: "draft"
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_prompt_versions, [:prompt_id, :version_number], unique: true,
              name: "idx_prompt_versions_on_prompt_and_version"
    add_index :raaf_prompt_versions, :status
    add_index :raaf_prompt_versions, :model
    add_index :raaf_prompt_versions, :created_at
  end
end
