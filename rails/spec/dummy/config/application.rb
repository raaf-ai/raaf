# frozen_string_literal: true

require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"

require "phlex-rails"
require "kaminari"
require "raaf-rails"

module Dummy
  # The host application the engine specs mount RAAF::Rails::Engine into.
  #
  # The gem ships no application of its own, so every constant under
  # app/models, app/controllers, app/components and app/jobs was unreachable
  # from a spec: those directories are only on the load path once an engine
  # has been booted by a real Rails::Application.
  class Application < ::Rails::Application
    config.load_defaults 8.0
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "raaf-rails-specs" * 4

    config.logger = Logger.new(IO::NULL)
    config.log_level = :fatal

    # The engine's screens are Phlex components rendered from controllers, so
    # nothing here needs the asset pipeline; its stylesheet and console bundle
    # are served by RAAF::Rails::AssetsController.
    config.assets.enabled = false if config.respond_to?(:assets)

    config.action_dispatch.show_exceptions = :none
    config.action_controller.allow_forgery_protection = false
    config.active_job.queue_adapter = :test
    config.active_record.maintain_test_schema = false
  end
end
