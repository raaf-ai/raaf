# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Controller for managing evaluation sessions
      #
      # Provides endpoints for:
      # - Listing saved sessions
      # - Loading session details
      # - Creating/updating sessions
      # - Deleting sessions
      #
      class SessionsController < ApplicationController
        before_action :set_session, only: [:show, :update, :destroy]

        # GET /sessions
        def index
          @sessions = Session.includes(:configurations, :results)
                             .where(user_id: current_user&.id)
                             .recent
          @filter = params[:filter] || "all"

          @sessions = case @filter
                      when "saved"
                        @sessions.saved
                      when "drafts"
                        @sessions.drafts
                      when "archived"
                        @sessions.archived
                      else
                        @sessions
                      end

          respond_to do |format|
            format.html
            format.json { render json: @sessions }
          end
        end

        # GET /sessions/:id
        def show
          respond_to do |format|
            format.html
            format.json do
              render json: @session.as_json(
                include: {
                  configurations: {},
                  results: { include: :configuration }
                }
              )
            end
          end
        end

        # POST /sessions
        def create
          @session = Session.new(session_params)
          @session.user_id = current_user&.id

          if @session.save
            respond_to do |format|
              format.html { redirect_to session_path(@session), notice: "Session saved successfully" }
              format.json { render json: @session, status: :created }
            end
          else
            respond_to do |format|
              format.html { render :new, status: :unprocessable_entity }
              format.json { render json: { errors: @session.errors }, status: :unprocessable_entity }
            end
          end
        end

        # PATCH/PUT /sessions/:id
        def update
          if @session.update(session_params)
            respond_to do |format|
              format.html { redirect_to session_path(@session), notice: "Session updated successfully" }
              format.json { render json: @session }
            end
          else
            respond_to do |format|
              format.html { render :edit, status: :unprocessable_entity }
              format.json { render json: { errors: @session.errors }, status: :unprocessable_entity }
            end
          end
        end

        # DELETE /sessions/:id
        def destroy
          @session.destroy

          respond_to do |format|
            format.html { redirect_to sessions_path, notice: "Session deleted successfully" }
            format.json { head :no_content }
          end
        end

        private

        def set_session
          @session = Session.find(params[:id])
        end

        def session_params
          params.require(:session).permit(
            :name,
            :description,
            :baseline_span_id,
            :session_type,
            metadata: {}
          )
        end
      end
    end
  end
end
