# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Base controller for continuous evaluation features
      class BaseController < ApplicationController
        include RAAF::Rails::TimeRange

        rescue_from ActiveRecord::RecordNotFound, with: :not_found
        rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

        private

        def not_found
          respond_to do |format|
            format.html { render "shared/not_found", status: :not_found }
            format.json { render json: { error: "Not found" }, status: :not_found }
          end
        end

        def unprocessable_entity(exception)
          respond_to do |format|
            format.html { render :edit, status: :unprocessable_content }
            format.json { render json: { errors: exception.record.errors }, status: :unprocessable_content }
          end
        end

        # A policy sampling a few spans an hour says nothing over a day.
        def default_range
          "7d"
        end
      end
    end
  end
end
