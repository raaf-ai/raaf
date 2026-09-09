# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for prompt versions
      class PromptVersionsController < BaseController
        before_action :set_prompt

        # GET /raaf/eval/prompts/:prompt_id/versions
        def index
          @versions = @prompt.prompt_versions.recent
          respond_to do |format|
            format.json { render json: @versions }
          end
        end

        # GET /raaf/eval/prompts/:prompt_id/versions/:id
        def show
          @version = @prompt.prompt_versions.find(params[:id])
          respond_to do |format|
            format.json { render json: @version }
          end
        end

        # GET /raaf/eval/prompts/:prompt_id/versions/new
        #
        # The prompt screen's "New Version" control used to link back to the
        # screen it was on, because there was no form behind it. The draft is
        # seeded from the published version, since a new version is almost
        # always an edit of the one in force rather than a blank page.
        def new
          seed = @prompt.active_version || @prompt.prompt_versions.recent.first

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::PromptVersionForm.new(prompt: @prompt, seed: seed)
              render_in_layout component, title: "New version of #{@prompt.name}", live: false
            end
          end
        end

        # POST /raaf/eval/prompts/:prompt_id/versions
        def create
          @version = @prompt.create_version!(
            content: params[:version][:content],
            model: params[:version][:model],
            model_parameters: params[:version][:model_parameters]&.to_unsafe_h || {},
            commit_message: params[:version][:commit_message],
            created_by: current_user_name
          )
          redirect_to eval_prompt_path(@prompt), notice: "Version #{@version.version_number} created."
        end

        # POST /raaf/eval/prompts/:prompt_id/versions/:id/publish
        def publish
          @version = @prompt.prompt_versions.find(params[:id])
          @version.publish!
          redirect_to eval_prompt_path(@prompt), notice: "Version #{@version.version_number} published."
        end

        # POST /raaf/eval/prompts/:prompt_id/versions/:id/archive
        def archive
          @version = @prompt.prompt_versions.find(params[:id])
          @version.archive!
          redirect_to eval_prompt_path(@prompt), notice: "Version #{@version.version_number} archived."
        end

        private

        def set_prompt
          @prompt = RAAF::Eval::Models::Prompt.find(params[:prompt_id])
        end

        def current_user_name
          respond_to?(:current_user) && current_user&.respond_to?(:name) ? current_user.name : "system"
        end
      end
    end
  end
end
