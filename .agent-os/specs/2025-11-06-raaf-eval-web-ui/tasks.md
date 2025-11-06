# Spec Tasks

These are the tasks to be completed for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-web-ui/spec.md

> Created: 2025-11-06
> Status: Ready for Implementation

## Tasks

- [ ] 1. Initialize Rails engine gem structure
  - [ ] 1.1 Write tests for engine initialization
  - [ ] 1.2 Create raaf-eval-ui gem directory structure
  - [ ] 1.3 Create lib/raaf/eval/ui/engine.rb with isolated namespace
  - [ ] 1.4 Create lib/raaf/eval/ui/version.rb
  - [ ] 1.5 Create lib/raaf-eval-ui.rb entry point
  - [ ] 1.6 Create raaf-eval-ui.gemspec with dependencies
  - [ ] 1.7 Set up autoload paths for components
  - [ ] 1.8 Configure importmap for JavaScript controllers
  - [ ] 1.9 Verify all tests pass and engine loads correctly

- [ ] 2. Create engine configuration system
  - [ ] 2.1 Write tests for configuration module
  - [ ] 2.2 Create lib/raaf/eval/ui/configuration.rb
  - [ ] 2.3 Implement authentication_method configuration
  - [ ] 2.4 Implement current_user_method configuration
  - [ ] 2.5 Implement authorize_span_access callback configuration
  - [ ] 2.6 Implement layout configuration
  - [ ] 2.7 Implement inherit_assets configuration
  - [ ] 2.8 Add configure block DSL
  - [ ] 2.9 Verify all tests pass and configuration works

- [ ] 3. Create database schema and migrations
  - [ ] 3.1 Write tests for session models
  - [ ] 3.2 Create migration for raaf_eval_ui_sessions table
  - [ ] 3.3 Create migration for raaf_eval_ui_session_configurations table
  - [ ] 3.4 Create migration for raaf_eval_ui_session_results table
  - [ ] 3.5 Add indexes for performance optimization
  - [ ] 3.6 Add foreign key constraints
  - [ ] 3.7 Test migration rollback
  - [ ] 3.8 Verify all tests pass

- [ ] 4. Create session models
  - [ ] 4.1 Write tests for Session model
  - [ ] 4.2 Create app/models/raaf/eval/ui/session.rb
  - [ ] 4.3 Implement associations (user, baseline_span)
  - [ ] 4.4 Implement validations
  - [ ] 4.5 Implement scopes (recent, saved)
  - [ ] 4.6 Write tests for SessionConfiguration model
  - [ ] 4.7 Create app/models/raaf/eval/ui/session_configuration.rb
  - [ ] 4.8 Write tests for SessionResult model
  - [ ] 4.9 Create app/models/raaf/eval/ui/session_result.rb
  - [ ] 4.10 Verify all tests pass

- [ ] 5. Create ApplicationController base
  - [ ] 5.1 Write tests for ApplicationController
  - [ ] 5.2 Create app/controllers/raaf/eval/ui/application_controller.rb
  - [ ] 5.3 Implement authenticate_user_from_config! method
  - [ ] 5.4 Implement current_user method
  - [ ] 5.5 Implement authorize_span_access! method
  - [ ] 5.6 Configure layout from configuration
  - [ ] 5.7 Add helper methods
  - [ ] 5.8 Verify all tests pass

- [ ] 6. Create SpansController
  - [ ] 6.1 Write tests for SpansController
  - [ ] 6.2 Create app/controllers/raaf/eval/ui/spans_controller.rb
  - [ ] 6.3 Implement index action with filters
  - [ ] 6.4 Implement show action
  - [ ] 6.5 Implement search action (AJAX)
  - [ ] 6.6 Implement filter action (AJAX)
  - [ ] 6.7 Add pagination support
  - [ ] 6.8 Add authorization checks
  - [ ] 6.9 Verify all tests pass

- [ ] 7. Create EvaluationsController
  - [ ] 7.1 Write tests for EvaluationsController
  - [ ] 7.2 Create app/controllers/raaf/eval/ui/evaluations_controller.rb
  - [ ] 7.3 Implement new action
  - [ ] 7.4 Implement create action
  - [ ] 7.5 Implement execute action
  - [ ] 7.6 Implement status action with Turbo Stream support
  - [ ] 7.7 Implement results action
  - [ ] 7.8 Implement show action
  - [ ] 7.9 Implement destroy action
  - [ ] 7.10 Verify all tests pass

- [ ] 8. Create SessionsController
  - [ ] 8.1 Write tests for SessionsController
  - [ ] 8.2 Create app/controllers/raaf/eval/ui/sessions_controller.rb
  - [ ] 8.3 Implement index action
  - [ ] 8.4 Implement show action
  - [ ] 8.5 Implement create action
  - [ ] 8.6 Implement update action
  - [ ] 8.7 Implement destroy action
  - [ ] 8.8 Verify all tests pass

- [ ] 9. Create engine routes
  - [ ] 9.1 Write tests for routing
  - [ ] 9.2 Create config/routes.rb in engine
  - [ ] 9.3 Define spans resources with collection actions
  - [ ] 9.4 Define evaluations resources with member actions
  - [ ] 9.5 Define sessions resources
  - [ ] 9.6 Set root route
  - [ ] 9.7 Test route generation
  - [ ] 9.8 Verify all tests pass

- [ ] 10. Create SpanBrowser component
  - [ ] 10.1 Write tests for SpanBrowser component
  - [ ] 10.2 Create app/components/raaf/eval/ui/span_browser.rb
  - [ ] 10.3 Implement filterable table layout
  - [ ] 10.4 Implement filter dropdowns
  - [ ] 10.5 Implement search bar
  - [ ] 10.6 Implement pagination controls
  - [ ] 10.7 Implement row selection
  - [ ] 10.8 Implement expandable row details
  - [ ] 10.9 Implement loading states
  - [ ] 10.10 Verify all tests pass and component renders

- [ ] 11. Create SpanDetail component
  - [ ] 11.1 Write tests for SpanDetail component
  - [ ] 11.2 Create app/components/raaf/eval/ui/span_detail.rb
  - [ ] 11.3 Implement three-section layout
  - [ ] 11.4 Implement syntax-highlighted JSON display
  - [ ] 11.5 Implement expandable tool calls
  - [ ] 11.6 Implement expandable handoffs
  - [ ] 11.7 Implement timeline visualization
  - [ ] 11.8 Implement token and cost breakdown
  - [ ] 11.9 Implement copy-to-clipboard buttons
  - [ ] 11.10 Verify all tests pass and component renders

- [ ] 12. Create PromptEditor component
  - [ ] 12.1 Write tests for PromptEditor component
  - [ ] 12.2 Create app/components/raaf/eval/ui/prompt_editor.rb
  - [ ] 12.3 Implement split-pane layout
  - [ ] 12.4 Integrate Monaco Editor container
  - [ ] 12.5 Implement estimated token count display
  - [ ] 12.6 Implement character count
  - [ ] 12.7 Implement validation indicators
  - [ ] 12.8 Implement diff view toggle
  - [ ] 12.9 Verify all tests pass and component renders

- [ ] 13. Create SettingsForm component
  - [ ] 13.1 Write tests for SettingsForm component
  - [ ] 13.2 Create app/components/raaf/eval/ui/settings_form.rb
  - [ ] 13.3 Implement model/provider dropdown
  - [ ] 13.4 Implement temperature slider with numeric input
  - [ ] 13.5 Implement max tokens input
  - [ ] 13.6 Implement top_p slider
  - [ ] 13.7 Implement frequency penalty slider
  - [ ] 13.8 Implement presence penalty slider
  - [ ] 13.9 Implement advanced settings collapsible
  - [ ] 13.10 Implement reset to baseline button
  - [ ] 13.11 Implement real-time validation
  - [ ] 13.12 Verify all tests pass and component renders

- [ ] 14. Create ExecutionProgress component
  - [ ] 14.1 Write tests for ExecutionProgress component
  - [ ] 14.2 Create app/components/raaf/eval/ui/execution_progress.rb
  - [ ] 14.3 Implement progress bar with percentage
  - [ ] 14.4 Implement status messages
  - [ ] 14.5 Implement estimated time remaining
  - [ ] 14.6 Implement cancel button
  - [ ] 14.7 Implement error display
  - [ ] 14.8 Implement Turbo Stream update support
  - [ ] 14.9 Verify all tests pass and component renders

- [ ] 15. Create ResultsComparison component
  - [ ] 15.1 Write tests for ResultsComparison component
  - [ ] 15.2 Create app/components/raaf/eval/ui/results_comparison.rb
  - [ ] 15.3 Implement three-column layout
  - [ ] 15.4 Implement diff highlighting (additions, deletions, modifications)
  - [ ] 15.5 Implement line-by-line vs unified diff toggle
  - [ ] 15.6 Implement expandable sections
  - [ ] 15.7 Implement delta indicators
  - [ ] 15.8 Integrate diff-lcs and diffy gems
  - [ ] 15.9 Verify all tests pass and component renders

- [ ] 16. Create MetricsPanel component
  - [ ] 16.1 Write tests for MetricsPanel component
  - [ ] 16.2 Create app/components/raaf/eval/ui/metrics_panel.rb
  - [ ] 16.3 Implement token usage comparison
  - [ ] 16.4 Implement latency comparison
  - [ ] 16.5 Implement quality metrics display
  - [ ] 16.6 Implement regression indicators
  - [ ] 16.7 Implement statistical significance badges
  - [ ] 16.8 Implement expandable detailed metrics
  - [ ] 16.9 Implement export metrics button
  - [ ] 16.10 Verify all tests pass and component renders

- [ ] 17. Create ConfigurationComparison component
  - [ ] 17.1 Write tests for ConfigurationComparison component
  - [ ] 17.2 Create app/components/raaf/eval/ui/configuration_comparison.rb
  - [ ] 17.3 Implement tabbed interface
  - [ ] 17.4 Implement side-by-side comparison grid
  - [ ] 17.5 Implement difference highlighting
  - [ ] 17.6 Implement configuration selection
  - [ ] 17.7 Implement visual indicators for best/worst
  - [ ] 17.8 Verify all tests pass and component renders

- [ ] 18. Create Monaco Editor Stimulus controller
  - [ ] 18.1 Write JavaScript tests for Monaco controller
  - [ ] 18.2 Create app/assets/javascript/raaf/eval/ui/controllers/monaco_editor_controller.js
  - [ ] 18.3 Implement loadMonaco method
  - [ ] 18.4 Implement initializeEditor method
  - [ ] 18.5 Implement editor content syncing
  - [ ] 18.6 Implement validateContent method
  - [ ] 18.7 Implement showDiff method
  - [ ] 18.8 Implement keyboard shortcuts (Cmd+S, Cmd+Enter)
  - [ ] 18.9 Implement session storage persistence
  - [ ] 18.10 Verify all tests pass and editor works

- [ ] 19. Create Evaluation Progress Stimulus controller
  - [ ] 19.1 Write JavaScript tests for progress controller
  - [ ] 19.2 Create app/assets/javascript/raaf/eval/ui/controllers/evaluation_progress_controller.js
  - [ ] 19.3 Implement startPolling method
  - [ ] 19.4 Implement stopPolling method
  - [ ] 19.5 Implement Turbo Stream message rendering
  - [ ] 19.6 Implement automatic polling cleanup
  - [ ] 19.7 Implement error handling
  - [ ] 19.8 Verify all tests pass and polling works

- [ ] 20. Create Form Validation Stimulus controller
  - [ ] 20.1 Write JavaScript tests for validation controller
  - [ ] 20.2 Create app/assets/javascript/raaf/eval/ui/controllers/form_validation_controller.js
  - [ ] 20.3 Implement parameter range validation
  - [ ] 20.4 Implement error message display
  - [ ] 20.5 Implement submit button state management
  - [ ] 20.6 Implement error clearing on correction
  - [ ] 20.7 Verify all tests pass and validation works

- [ ] 21. Create background job for evaluation execution
  - [ ] 21.1 Write tests for EvaluationExecutionJob
  - [ ] 21.2 Create app/jobs/raaf/eval/ui/evaluation_execution_job.rb
  - [ ] 21.3 Implement perform method
  - [ ] 21.4 Integrate with Phase 1 evaluation engine
  - [ ] 21.5 Implement status updates
  - [ ] 21.6 Implement error handling
  - [ ] 21.7 Implement result storage
  - [ ] 21.8 Verify all tests pass and jobs execute

- [ ] 22. Set up Turbo Streams for real-time updates
  - [ ] 22.1 Write tests for Turbo Stream updates
  - [ ] 22.2 Create evaluation progress partial
  - [ ] 22.3 Implement Turbo Stream response in status action
  - [ ] 22.4 Test real-time progress updates
  - [ ] 22.5 Implement automatic polling start/stop
  - [ ] 22.6 Verify all tests pass and updates work

- [ ] 23. Create engine assets and styles
  - [ ] 23.1 Create app/assets/stylesheets/raaf/eval/ui/application.css
  - [ ] 23.2 Add Tailwind CSS integration
  - [ ] 23.3 Create custom styles for components
  - [ ] 23.4 Create app/assets/javascript/raaf/eval/ui/application.js
  - [ ] 23.5 Set up importmap configuration
  - [ ] 23.6 Add asset manifest
  - [ ] 23.7 Test asset precompilation
  - [ ] 23.8 Verify all assets load correctly

- [ ] 24. Create engine layout
  - [ ] 24.1 Write tests for layout rendering
  - [ ] 24.2 Create app/views/layouts/raaf/eval/ui/application.html.erb
  - [ ] 24.3 Include asset tags
  - [ ] 24.4 Include Turbo and Stimulus setup
  - [ ] 24.5 Add navigation elements
  - [ ] 24.6 Add flash message display
  - [ ] 24.7 Test layout with host app layout override
  - [ ] 24.8 Verify all tests pass and layout renders

- [ ] 25. Create integration tests for user workflows
  - [ ] 25.1 Write test for span browsing workflow
  - [ ] 25.2 Write test for evaluation setup workflow
  - [ ] 25.3 Write test for evaluation execution workflow
  - [ ] 25.4 Write test for results viewing workflow
  - [ ] 25.5 Write test for session management workflow
  - [ ] 25.6 Write test for real-time updates workflow
  - [ ] 25.7 Run all integration tests
  - [ ] 25.8 Verify all workflows work end-to-end

- [ ] 26. Create browser compatibility tests
  - [ ] 26.1 Set up Selenium WebDriver for browser testing
  - [ ] 26.2 Test Chrome 100+ compatibility
  - [ ] 26.3 Test Firefox 100+ compatibility
  - [ ] 26.4 Test Safari 15+ compatibility
  - [ ] 26.5 Test Edge 100+ compatibility
  - [ ] 26.6 Test Monaco Editor across browsers
  - [ ] 26.7 Test Turbo Streams across browsers
  - [ ] 26.8 Verify all browsers work correctly

- [ ] 27. Create accessibility tests
  - [ ] 27.1 Test keyboard navigation
  - [ ] 27.2 Test ARIA labels and attributes
  - [ ] 27.3 Test focus management
  - [ ] 27.4 Test screen reader compatibility
  - [ ] 27.5 Test color contrast (WCAG AA)
  - [ ] 27.6 Test keyboard shortcuts
  - [ ] 27.7 Verify all accessibility requirements met

- [ ] 28. Create performance tests
  - [ ] 28.1 Benchmark span browser table rendering
  - [ ] 28.2 Benchmark Monaco Editor initialization
  - [ ] 28.3 Benchmark diff rendering
  - [ ] 28.4 Benchmark Turbo Stream updates
  - [ ] 28.5 Test with large datasets (1000+ spans)
  - [ ] 28.6 Optimize slow operations
  - [ ] 28.7 Verify performance targets met

- [ ] 29. Create engine documentation
  - [ ] 29.1 Create README.md with installation instructions
  - [ ] 29.2 Document mounting in Rails apps
  - [ ] 29.3 Document configuration options
  - [ ] 29.4 Document authentication integration
  - [ ] 29.5 Document component usage
  - [ ] 29.6 Create CHANGELOG.md
  - [ ] 29.7 Create example configurations
  - [ ] 29.8 Verify documentation is complete

- [ ] 30. Create demo/example application
  - [ ] 30.1 Create demo Rails app
  - [ ] 30.2 Mount raaf-eval-ui engine
  - [ ] 30.3 Configure authentication
  - [ ] 30.4 Seed with example data
  - [ ] 30.5 Test all features in demo app
  - [ ] 30.6 Document demo app setup
  - [ ] 30.7 Verify demo app works completely

- [ ] 31. Package and release preparation
  - [ ] 31.1 Run full test suite
  - [ ] 31.2 Check code coverage (target: 95%+)
  - [ ] 31.3 Run RuboCop linter
  - [ ] 31.4 Fix any linting issues
  - [ ] 31.5 Update version number
  - [ ] 31.6 Build gem package
  - [ ] 31.7 Test gem installation
  - [ ] 31.8 Verify all features work in packaged gem
