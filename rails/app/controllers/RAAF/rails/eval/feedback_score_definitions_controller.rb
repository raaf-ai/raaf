# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for feedback score definitions
      class FeedbackScoreDefinitionsController < BaseController
        FeedbackScoreDefinition = RAAF::Eval::Models::FeedbackScoreDefinition

        # GET /raaf/eval/feedback_score_definitions
        def index
          @definitions = FeedbackScoreDefinition.all
          respond_to do |format|
            format.json { render json: @definitions }
          end
        end

        # GET /raaf/eval/feedback_score_definitions/:id
        def show
          @definition = FeedbackScoreDefinition.find(params[:id])
          respond_to do |format|
            format.json { render json: @definition }
          end
        end

        # POST /raaf/eval/feedback_score_definitions
        def create
          @definition = FeedbackScoreDefinition.new(definition_params)
          if @definition.save
            render json: @definition, status: :created
          else
            render json: { errors: @definition.errors }, status: :unprocessable_entity
          end
        end

        # PATCH /raaf/eval/feedback_score_definitions/:id
        def update
          @definition = FeedbackScoreDefinition.find(params[:id])
          if @definition.update(definition_params)
            render json: @definition
          else
            render json: { errors: @definition.errors }, status: :unprocessable_entity
          end
        end

        # DELETE /raaf/eval/feedback_score_definitions/:id
        def destroy
          FeedbackScoreDefinition.find(params[:id]).destroy
          head :no_content
        end

        private

        def definition_params
          params.require(:feedback_score_definition).permit(:name, :description, :score_type, :min_value, :max_value, categories: [], metadata: {})
        end
      end
    end
  end
end
