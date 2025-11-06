# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application", to: "raaf/eval/ui/application.js", preload: true
pin "@hotwired/stimulus", to: "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/dist/stimulus.min.js"
pin "@hotwired/turbo-rails", to: "https://cdn.jsdelivr.net/npm/@hotwired/turbo-rails@7.3.0/app/javascript/turbo.min.js"

# Stimulus controllers
pin "raaf/eval/ui/controllers/monaco_editor_controller", to: "raaf/eval/ui/controllers/monaco_editor_controller.js"
pin "raaf/eval/ui/controllers/evaluation_progress_controller", to: "raaf/eval/ui/controllers/evaluation_progress_controller.js"
pin "raaf/eval/ui/controllers/form_validation_controller", to: "raaf/eval/ui/controllers/form_validation_controller.js"
