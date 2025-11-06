# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Simple session-based authentication for demo purposes
  before_action :authenticate_user!

  helper_method :current_user

  private

  def authenticate_user!
    unless current_user
      redirect_to login_path, alert: "Please log in to continue"
    end
  end

  def current_user
    return nil unless session[:user_id]

    @current_user ||= User.find_by(id: session[:user_id]) if defined?(User)
    @current_user ||= OpenStruct.new(id: session[:user_id], email: 'demo@example.com') # Fallback
  end
end
