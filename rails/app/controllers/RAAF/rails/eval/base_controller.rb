# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Base controller for Opik-inspired evaluation features
      class BaseController < ApplicationController
        rescue_from ActiveRecord::RecordNotFound, with: :not_found
        rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

        private

        def not_found
          respond_to do |format|
            format.html { render plain: "Not found", status: :not_found }
            format.json { render json: { error: "Not found" }, status: :not_found }
          end
        end

        def unprocessable_entity(exception)
          respond_to do |format|
            format.html { redirect_back(fallback_location: root_path, alert: exception.record.errors.full_messages.join(", ")) }
            format.json { render json: { errors: exception.record.errors }, status: :unprocessable_entity }
          end
        end
      end
    end
  end
end
