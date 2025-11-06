# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Controller for browsing and selecting production spans
      #
      # Provides endpoints for:
      # - Listing spans with filters and pagination
      # - Viewing span details
      # - Searching spans
      # - Filtering spans by criteria
      #
      class SpansController < ApplicationController
        before_action :set_span, only: [:show]
        before_action :authorize_span, only: [:show]

        # GET /spans
        def index
          @spans = fetch_spans
          @page = params[:page]&.to_i || 1
          @per_page = params[:per_page]&.to_i || 25

          respond_to do |format|
            format.html
            format.json { render json: @spans }
          end
        end

        # GET /spans/:id
        def show
          respond_to do |format|
            format.html
            format.json { render json: @span }
          end
        end

        # GET /spans/search
        def search
          query = params[:q]
          @spans = search_spans(query)

          respond_to do |format|
            format.json { render json: @spans }
            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                "spans_table",
                partial: "raaf/eval/ui/spans/table",
                locals: { spans: @spans }
              )
            end
          end
        end

        # GET /spans/filter
        def filter
          @spans = fetch_spans
          @filters = extract_filters

          respond_to do |format|
            format.json { render json: @spans }
            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                "spans_table",
                partial: "raaf/eval/ui/spans/table",
                locals: { spans: @spans }
              )
            end
          end
        end

        private

        def set_span
          # This would fetch from Phase 1's span model
          # For now, create a stub
          @span = OpenStruct.new(
            id: params[:id],
            agent_name: "TestAgent",
            model: "gpt-4",
            status: "completed",
            created_at: Time.current
          )
        end

        def authorize_span
          authorize_span_access!(@span) if @span
        end

        def fetch_spans
          # This would query Phase 1's evaluation spans
          # For now, return empty array
          []
        end

        def search_spans(query)
          # This would search Phase 1's spans
          # For now, return empty array
          []
        end

        def extract_filters
          {
            agent_name: params[:agent_name],
            model: params[:model],
            status: params[:status],
            start_date: params[:start_date],
            end_date: params[:end_date]
          }.compact
        end
      end
    end
  end
end
