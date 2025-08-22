# frozen_string_literal: true

module RAAF
  module Rails
    # Base application controller for RAAF Rails Engine
    class ApplicationController < ::ActionController::Base
      protect_from_forgery with: :exception
      # Skip authentication for RAAF engine controllers
      skip_before_action :authenticate_user!, raise: false
    end
  end
end