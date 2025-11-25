# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Base controller for continuous evaluation features
      class BaseController < ApplicationController
        rescue_from ActiveRecord::RecordNotFound, with: :not_found
        rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

        private

        def not_found
          respond_to do |format|
            format.html { render 'shared/not_found', status: :not_found }
            format.json { render json: { error: 'Not found' }, status: :not_found }
          end
        end

        def unprocessable_entity(exception)
          respond_to do |format|
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: { errors: exception.record.errors }, status: :unprocessable_entity }
          end
        end

        def parse_time_range(params)
          start_time = params[:start_time].present? ? Time.zone.parse(params[:start_time]) : 7.days.ago
          end_time = params[:end_time].present? ? Time.zone.parse(params[:end_time]) : Time.current
          start_time..end_time
        end
      end
    end
  end
end
