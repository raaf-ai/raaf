# frozen_string_literal: true

require "raaf/eval/ui/version"
require "raaf/eval/ui/configuration"
require "raaf/eval/ui/engine"

##
# RAAF Eval UI - Web interface for interactive agent evaluation
#
# This gem provides a mountable Rails engine with a complete web interface
# for browsing production spans, editing prompts, running evaluations, and
# comparing results.
#
# @example Mount in your Rails application
#   # config/routes.rb
#   Rails.application.routes.draw do
#     mount RAAF::Eval::UI::Engine, at: "/eval"
#   end
#
# @example Configure authentication
#   # config/initializers/raaf_eval_ui.rb
#   RAAF::Eval::UI.configure do |config|
#     config.authentication_method = :authenticate_user!
#     config.current_user_method = :current_user
#     config.authorize_span_access = ->(user, span) {
#       user.admin? || span.user_id == user.id
#     }
#   end
#
module RAAF
  module Eval
    module UI
      class Error < StandardError; end
    end
  end
end
