# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for managing versioned prompts
      class PromptsController < BaseController
        Prompt = RAAF::Eval::Models::Prompt

        before_action :set_prompt, only: %i[show edit update destroy diff history]

        # GET /raaf/eval/prompts
        def index
          @prompts = Prompt.recent
          @prompts = @prompts.for_agent(params[:agent]) if params[:agent].present?

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::PromptList.new(prompts: @prompts)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Prompts") { render component }
              render layout
            end
            format.json { render json: @prompts }
          end
        end

        # GET /raaf/eval/prompts/:id
        def show
          @versions = @prompt.prompt_versions.recent
          @active_version = @prompt.active_version

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::PromptShow.new(
                prompt: @prompt, versions: @versions, active_version: @active_version
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: @prompt.name) { render component }
              render layout
            end
            format.json { render json: @prompt.as_json(methods: :history) }
          end
        end

        # GET /raaf/eval/prompts/new
        def new
          @prompt = Prompt.new
          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::PromptForm.new(prompt: @prompt)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "New Prompt") { render component }
              render layout
            end
          end
        end

        # POST /raaf/eval/prompts
        def create
          @prompt = Prompt.new(prompt_params)
          if @prompt.save
            # Create initial version if content provided
            if params.dig(:prompt, :initial_content).present?
              @prompt.create_version!(
                content: params[:prompt][:initial_content],
                model: params[:prompt][:initial_model],
                commit_message: "Initial version",
                created_by: current_user_name
              )
            end
            redirect_to eval_prompt_path(@prompt), notice: "Prompt created."
          else
            component = RAAF::Rails::Eval::PromptForm.new(prompt: @prompt)
            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "New Prompt") { render component }
            render layout, status: :unprocessable_entity
          end
        end

        # PATCH /raaf/eval/prompts/:id
        def update
          if @prompt.update(prompt_params)
            redirect_to eval_prompt_path(@prompt), notice: "Prompt updated."
          else
            component = RAAF::Rails::Eval::PromptForm.new(prompt: @prompt)
            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Edit #{@prompt.name}") { render component }
            render layout, status: :unprocessable_entity
          end
        end

        # DELETE /raaf/eval/prompts/:id
        def destroy
          @prompt.destroy
          redirect_to eval_prompts_path, notice: "Prompt deleted."
        end

        # GET /raaf/eval/prompts/:id/diff
        def diff
          diff_result = @prompt.diff(params[:from].to_i, params[:to].to_i)
          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::PromptDiff.new(prompt: @prompt, diff: diff_result)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Diff: #{@prompt.name}") { render component }
              render layout
            end
            format.json { render json: diff_result }
          end
        end

        # GET /raaf/eval/prompts/:id/history
        def history
          respond_to do |format|
            format.json { render json: @prompt.history }
          end
        end

        private

        def set_prompt
          @prompt = Prompt.find(params[:id])
        end

        def prompt_params
          params.require(:prompt).permit(:name, :description, :agent_name, metadata: {})
        end

        def current_user_name
          respond_to?(:current_user) && current_user&.respond_to?(:name) ? current_user.name : "system"
        end
      end
    end
  end
end
