# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Controller for managing evaluation execution
      #
      # Provides endpoints for:
      # - Creating new evaluations from spans
      # - Executing evaluations asynchronously
      # - Polling evaluation status
      # - Viewing evaluation results
      #
      class EvaluationsController < ApplicationController
        before_action :set_session, only: [:show, :execute, :status, :results, :destroy]

        # GET /evaluations/new?span_id=123
        def new
          @span_id = params[:span_id]
          @session = Session.new(name: "Evaluation #{Time.current.strftime('%Y-%m-%d %H:%M')}")

          respond_to do |format|
            format.html
            format.json { render json: @session }
          end
        end

        # POST /evaluations
        def create
          @session = Session.new(session_params)
          @session.user_id = current_user&.id

          if @session.save
            # Create initial configuration from params
            if params[:configuration].present?
              @session.configurations.create!(
                name: "Configuration 1",
                configuration: configuration_params
              )
            end

            respond_to do |format|
              format.html { redirect_to evaluation_path(@session), notice: "Evaluation session created successfully" }
              format.json { render json: @session, status: :created }
            end
          else
            respond_to do |format|
              format.html { render :new, status: :unprocessable_entity }
              format.json { render json: { errors: @session.errors }, status: :unprocessable_entity }
            end
          end
        end

        # GET /evaluations/:id
        def show
          respond_to do |format|
            format.html
            format.json { render json: @session }
          end
        end

        # POST /evaluations/:id/execute
        def execute
          if @session.running?
            render json: { error: "Evaluation already running" }, status: :unprocessable_entity
            return
          end

          @session.mark_running!

          # Queue background job for execution
          EvaluationExecutionJob.perform_later(@session.id)

          respond_to do |format|
            format.html { redirect_to status_evaluation_path(@session) }
            format.json { render json: { status: "running", session_id: @session.id } }
          end
        end

        # GET /evaluations/:id/status
        def status
          respond_to do |format|
            format.html
            format.json { render json: { status: @session.status, progress: @session.progress_percentage } }
            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                "evaluation_progress",
                partial: "raaf/eval/ui/evaluations/progress",
                locals: { session: @session }
              )
            end
          end
        end

        # GET /evaluations/:id/results
        def results
          unless @session.completed?
            redirect_to status_evaluation_path(@session), alert: "Evaluation not yet completed"
            return
          end

          @results = @session.results.includes(:configuration)

          respond_to do |format|
            format.html
            format.json { render json: @results }
          end
        end

        # DELETE /evaluations/:id
        def destroy
          @session.destroy

          respond_to do |format|
            format.html { redirect_to sessions_path, notice: "Evaluation deleted successfully" }
            format.json { head :no_content }
          end
        end

        private

        def set_session
          @session = Session.find(params[:id])
        end

        def session_params
          params.require(:session).permit(:name, :description, :baseline_span_id, :session_type)
        end

        def configuration_params
          params.require(:configuration).permit(
            :model,
            :provider,
            :temperature,
            :max_tokens,
            :top_p,
            :frequency_penalty,
            :presence_penalty,
            :instructions
          ).to_h
        end
      end
    end
  end
end
