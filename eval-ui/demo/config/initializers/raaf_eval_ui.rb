# frozen_string_literal: true

# Configure RAAF Eval UI engine
RAAF::Eval::UI.configure do |config|
  # Authentication configuration
  # These methods will be called on the controller to authenticate users
  config.authentication_method = :authenticate_user!
  config.current_user_method = :current_user

  # Authorization callback for span access
  # This example allows all authenticated users to access all spans
  # In production, you might want to restrict based on team, project, etc.
  config.authorize_span_access = ->(user, span) {
    # Allow access if user is authenticated
    user.present?

    # Example: Restrict to team members
    # user.team_ids.include?(span.team_id)

    # Example: Restrict to span owner
    # span.user_id == user.id

    # Example: Admin bypass
    # user.admin? || span.user_id == user.id
  }

  # Layout configuration
  # Use the host application's layout
  config.layout = "application"

  # Asset inheritance
  # Inherit CSS and JavaScript from host application
  config.inherit_assets = true

  # Additional configuration options (if needed)
  # config.spans_per_page = 25
  # config.max_concurrent_evaluations = 5
  # config.enable_performance_tracking = true
end
