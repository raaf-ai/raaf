# Development Best Practices

> Version: 1.1.0
> Last updated: 2025-07-28
> Scope: Global development standards

## Context

This file is part of the Agent OS standards system. These global best practices are referenced by all product codebases and provide default development guidelines. Individual projects may extend or override these practices in their `.agent-os/product/dev-best-practices.md` file.

## Core Principles

### Keep It Simple
- Implement code in the fewest lines possible
- Avoid over-engineering solutions
- Choose straightforward approaches over clever ones
- Use Ruby idioms appropriately without sacrificing clarity

### Optimize for Readability
- Prioritize code clarity over micro-optimizations
- Write self-documenting code with clear variable names
- Add comments for "why" not "what"
- Use YARD documentation for public APIs

### DRY (Don't Repeat Yourself)
- Extract repeated business logic to private methods
- Extract repeated UI markup to reusable components
- Create utility functions for common operations
- Use modules for shared behavior across classes

### Modular Architecture
- Design with clear separation of concerns
- Build features as independent modules when possible
- Use dependency injection for flexibility
- Enable selective feature adoption
- Avoid tight coupling between layers (controllers should not call services directly from components)

## Dependencies

### Choose Libraries Wisely
When adding third-party dependencies:
- Select the most popular and actively maintained option
- Check the library's GitHub repository for:
  - Recent commits (within last 6 months)
  - Active issue resolution
  - Number of stars/downloads
  - Clear documentation
- Consider the dependency's own dependencies
- Evaluate impact on bundle size and load time

### Dependency Management
- Use semantic versioning in gemspecs
- Pin major versions to prevent breaking changes
- Document why each dependency is needed
- Regularly audit and update dependencies

## Code Organization

### File Structure
- Keep files focused on a single responsibility
- Group related functionality together
- Use consistent naming conventions
- One class or module per file generally
- Organize modules in a clear hierarchy

### Module Design
- Create focused modules with specific purposes
- Define clear interfaces between modules
- Minimize module coupling
- Document module responsibilities

### AI Agent Naming Standards

**For AI-powered applications using RAAF or similar frameworks:**

**Core Principle:** Name agents based on WHAT THEY DO, not HOW they do it. The name describes business function, not technical implementation.

**Agent Categories:**

1. **Search/Discovery Agents** (Perplexity or similar search providers)
   - Pattern: `[Domain]::[Thing]Finder|Discovery|Monitor|Gatherer`
   - Purpose: Collect factual data without reasoning
   - Examples: `Prospect::CompanyFinder`, `Intelligence::NewsMonitor`
   - Suffixes: `Finder`, `Discovery`, `Monitor`, `Gatherer`

2. **Reasoning/Analysis Agents** (OpenAI or similar LLM providers)
   - Pattern: `[Domain]::[Process]Analyzer|Scorer|Classifier|Detector|Generator`
   - Purpose: Perform reasoning, analysis, or classification
   - Examples: `Prospect::FitAnalyzer`, `DMU::StakeholderClassifier`
   - Suffixes: `Analyzer`, `Scorer`, `Classifier`, `Detector`, `Generator`

**Naming Rules:**
- No implementation details (avoid "Perplexity", "OpenAI", etc. in names)
- Use domain prefixes for organization (`Prospect::`, `Market::`, `Intelligence::`)
- Keep names to 2-3 words after domain prefix
- Use consistent suffixes to indicate agent type
- Names should be clear without additional context

**Examples:**

```ruby
# ✅ GOOD: Clear purpose
module Prospect
  class InternationalCompanyFinder  # Search agent
  class QuickFitAnalyzer           # Reasoning agent
end

# ❌ WRONG: Implementation details
class PerplexityCompanyAgent
class OpenAIAnalysisAgent
```

**For complete AI agent naming standards, see project-specific documentation.**

## Error Handling

### Exception Design
- Create a base error class for your project
- Use specific exception types for different failures
- Include context in error messages
- Make errors actionable for developers

### Resilience Patterns
- Implement retry logic for transient failures
- Use circuit breakers for external services
- Provide fallback strategies
- Log errors with appropriate detail levels

## Testing

### Testing Strategy
- Write tests for new functionality
- Maintain existing test coverage
- Test edge cases and error conditions
- Use mocks to minimize external dependencies
- Focus on behavior over implementation

### Test Organization
- Keep test files parallel to source files
- Use descriptive test names
- Group related tests with contexts
- Use factories for test data generation
- Keep tests fast and isolated
- Organize tests by logical groupings (use proper context blocks)
- Ensure test setup matches the scenario being tested
- Place tests in appropriate context blocks to avoid setup conflicts

### Component Testing Best Practices
- Pass data via constructor parameters, not direct service calls
- Test components in isolation from external dependencies
- Mock service calls at the boundary, not inside components
- Use dependency injection for testable component architecture

### Service-Based Controller Testing
Test controllers by mocking service interactions, not implementation details:

```ruby
RSpec.describe CompanyProfilesController, type: :controller do
  let(:mock_service) { instance_double(CompanyProfileService) }
  let(:success_result) { OpenStruct.new(success: true, company: company) }

  before do
    allow(CompanyProfileService).to receive(:new).and_return(mock_service)
  end

  describe 'GET #new' do
    it 'delegates to service with correct parameters' do
      expect(CompanyProfileService).to receive(:new).with(
        params: hash_including(action: :new, current_user: user)
      )
      expect(mock_service).to receive(:call).and_return(success_result)
      
      get :new
      expect(response).to have_http_status(:ok)
    end
  end
end
```

### Service Testing Best Practices
- Test each action method individually
- Test both success and failure scenarios
- Mock external dependencies (APIs, other services)
- Verify result object structure and content
- Test edge cases and error conditions

### Cost-Conscious Testing
- Mock expensive API calls by default
- Use VCR for recording real responses
- Profile test performance regularly
- Run expensive tests selectively

### Test Failure Management
- **NEVER** leave failing tests in the test suite
- If a test cannot be made to pass immediately, mark it as pending:
  ```ruby
  # Good: Mark as pending with reason
  it "should handle complex edge case", :pending => "needs API refactoring" do
    # test code
  end
  
  # Alternative syntax
  pending "needs API refactoring" do
    it "should handle complex edge case" do
      # test code
    end
  end
  ```
- Document the reason why the test is pending
- Revisit pending tests regularly during development
- All tests must pass in CI/CD pipeline

### Debugging and Troubleshooting
- When components fail to render, check for missing required parameters
- Use component parameter defaults to prevent nil errors in optional fields
- Verify that service-generated data matches view expectations
- Check ApplicationController parameter extraction for missing context
- Run individual test files when debugging specific issues

## Performance

### Resource Management
- Use connection pooling for external services
- Implement caching where appropriate
- Lazy load expensive operations
- Monitor memory usage in long-running processes

### Optimization Strategies
- Profile before optimizing
- Focus on algorithmic improvements
- Use Ruby's built-in performance features
- Consider memory vs CPU trade-offs

## Security

### Input Validation
- Validate all external inputs
- Sanitize user-generated content
- Use parameterized queries
- Implement rate limiting

### Sensitive Data
- Never log sensitive information
- Use environment variables for secrets
- Implement PII detection and redaction
- Follow principle of least privilege

## Documentation

### Code Documentation
- Document all public methods with YARD
- Include usage examples in documentation
- Keep README files up to date
- Document architectural decisions

### API Documentation
- Provide clear API references
- Include authentication details
- Show request/response examples
- Document error responses

## Monitoring and Observability

### Logging
- Use structured logging
- Include request IDs for tracing
- Log at appropriate levels
- Avoid logging sensitive data

### Metrics and Tracing
- Instrument key operations
- Track business metrics
- Use distributed tracing for complex flows
- Set up alerting for anomalies

## Development Workflow

### Version Control
- Write clear commit messages
- Keep commits focused and atomic
- Use conventional commit format
- Tag releases appropriately

### Code Review
- Review for correctness and style
- Check for security implications
- Verify test coverage
- Ensure documentation is updated

## Rails/Web Application Best Practices

### Service-View-Controller Pattern
- Controllers delegate ALL business logic to services
- Controllers are thin - they only handle HTTP concerns and orchestration
- Views receive data via constructor parameters
- Components should not make direct service calls
- Pass computed data down through the view hierarchy

### Thin Controllers with Service Delegation
Controllers should contain zero business logic and delegate everything to services:

```ruby
# Good: Thin controller with service delegation
class CompanyProfilesController < ApplicationController
  def new
    render_with_service(params: params.merge(action: :new, current_user: current_user))
  end

  def create
    create_with_service(params: params.merge(action: :create, current_user: current_user))
  end

  def edit
    render_with_service(params: params.merge(action: :edit, current_user: current_user))
  end
end

# Avoid: Business logic in controllers
class CompanyProfilesController < ApplicationController
  def create
    @company = CustomerCompany.new(company_params)
    @company.user = current_user
    
    if @company.save
      redirect_to company_profile_path(@company)
    else
      render :new
    end
  end
end
```

### Service Classes Handle All Business Logic
Services encapsulate all domain logic, validations, and data manipulation:

```ruby
class CompanyProfileService < BaseService
  def call
    case params[:action]
    when :new then handle_new
    when :create then handle_create
    when :edit then handle_edit
    when :update then handle_update
    when :show then handle_show
    when :destroy then handle_destroy
    end
  end

  private

  def handle_create
    company = CustomerCompany.new(company_params)
    company.user = current_user
    
    if company.save
      success_result(
        company: company,
        redirect_to: edit_company_profile_path(company, step: 'products'),
        notice: "Company created successfully"
      )
    else
      error_result(company: company, errors: company.errors)
    end
  end
end
```

### View Architecture
```ruby
# Good: Data passed from controller via service
class Views::CompanyProfiles::Edit < BaseComponent
  def initialize(company:, profile_completion:, current_user:, **options)
    @company = company
    @profile_completion = profile_completion
    @current_user = current_user
  end
end

# Avoid: Direct service calls in components
class CompanyProfileWizard < BaseComponent
  def overall_progress
    service = CompanyProfileService.new(...)  # Don't do this
    service.profile_completion
  end
end
```

### ApplicationController Helper Methods
Use standardized helper methods for consistent service delegation:

```ruby
# For read operations (GET requests)
def render_with_service(**service_params)
  service_result = service_class.new(**service_params).call
  render_view_with_result(service_result)
end

# For write operations with redirect logic (POST/PATCH/PUT)
def create_with_service(redirect_path = nil, **service_params)
  service_result = service_class.new(**service_params).call
  
  if service_result.success && service_result.redirect_to
    redirect_to(service_result.redirect_to, notice: service_result.notice)
  else
    render_view_with_result(service_result, status: :unprocessable_entity)
  end
end

# For actions that may redirect or render
def update_with_service(redirect_path = nil, service_class = nil, view_class = nil, **service_params)
  # Handles both success redirects and error re-rendering
end
```

### Service Result Standardization
Services should return consistent result objects:

```ruby
# Success results include data and optional redirect information
def success_result(data = {})
  OpenStruct.new(
    success: true,
    **data,
    redirect_to: nil,  # Optional redirect path
    notice: nil        # Optional flash message
  )
end

# Error results include error information and data for re-rendering
def error_result(data = {})
  OpenStruct.new(
    success: false,
    errors: [],
    **data
  )
end
```

### Controller Best Practices
- Always pass `current_user` to views when available
- Use explicit view class specification for non-standard actions
- Handle both success and error scenarios appropriately
- Never put business logic in controller actions
- Use service delegation helper methods consistently
- Let services determine redirect paths and flash messages

### Service Class Architecture
Services should inherit from BaseService and handle multiple related actions:

```ruby
class CompanyProfileService < BaseService
  # Single service handles all CRUD operations for a resource
  # Reduces code duplication and provides consistent behavior
  
  def call
    case params[:action]
    when :new then handle_new
    when :create then handle_create
    when :edit then handle_edit
    when :update then handle_update
    when :show then handle_show
    when :destroy then handle_destroy
    when :completion_status then handle_completion_status
    # Wizard-specific actions
    when :next_step then handle_next_step
    when :previous_step then handle_previous_step
    when :save_draft then handle_save_draft
    when :finish then handle_finish
    else
      error_result(errors: ["Unknown action: #{params[:action]}"])
    end
  end
end
```

### Benefits of Service-Based Controllers
- **Testability**: Business logic is isolated and easily testable
- **Reusability**: Services can be called from multiple places (controllers, jobs, console)
- **Consistency**: Standardized result objects and error handling
- **Maintainability**: Business logic changes happen in one place
- **Single Responsibility**: Controllers handle HTTP, services handle business logic
- **API-First**: Same services can power both web and API endpoints

### Parameter Management
```ruby
# Good: Ensure required context is available
def extract_view_params(service_result)
  params = service_result.table.except(:success, :errors, :redirect_to, :notice)
  params[:current_user] = current_user if respond_to?(:current_user)
  params
end
```

### JavaScript and Stimulus Best Practices

**MANDATORY:** All interactive JavaScript MUST use Stimulus controllers. Vanilla JavaScript and inline scripts are FORBIDDEN.

#### Core Stimulus Principles

```javascript
// ✅ CORRECT: Reusable Stimulus controller
// app/javascript/controllers/toggle_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleable"]
  static classes = ["hidden", "visible"]

  toggle() {
    this.toggleableTargets.forEach(target => {
      if (target.classList.contains(this.hiddenClass)) {
        target.classList.remove(this.hiddenClass)
        target.classList.add(this.visibleClass)
      } else {
        target.classList.remove(this.visibleClass)
        target.classList.add(this.hiddenClass)
      }
    })
  }
}
```

```ruby
# ✅ USAGE: Reuse in multiple views
div(data: { controller: "toggle" }) do
  button(data: { action: "click->toggle#toggle" }) { "Toggle Content" }
  div(data: { toggle_target: "toggleable" }, class: "hidden") do
    p { "This content can be toggled" }
  end
end
```

#### Abstract Common Behaviors

```javascript
// ✅ CORRECT: Base controller for common form behaviors
// app/javascript/controllers/form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton", "field"]
  static classes = ["loading", "error", "valid"]

  connect() {
    this.validateForm()
  }

  validateForm() {
    const isValid = this.fieldTargets.every(field => field.checkValidity())
    this.submitButtonTarget.disabled = !isValid
  }

  fieldChanged() {
    this.validateForm()
  }

  showLoading() {
    this.submitButtonTarget.classList.add(this.loadingClass)
  }

  hideLoading() {
    this.submitButtonTarget.classList.remove(this.loadingClass)
  }
}
```

```javascript
// ✅ CORRECT: Extend base controller for specific forms
// app/javascript/controllers/wizard_form_controller.js
import FormController from "./form_controller"

export default class extends FormController {
  static targets = [...super.targets, "step", "progress"]

  nextStep() {
    this.showLoading()
    // Handle step navigation
  }

  updateProgress() {
    // Update progress indicator
  }
}
```

#### Controller Composition Patterns

```javascript
// ✅ CORRECT: Mixins for shared behaviors
// app/javascript/mixins/confirmable.js
export const Confirmable = {
  confirm(event) {
    if (!window.confirm(this.data.get("confirmMessage") || "Are you sure?")) {
      event.preventDefault()
    }
  }
}

// app/javascript/controllers/delete_controller.js
import { Controller } from "@hotwired/stimulus"
import { Confirmable } from "../mixins/confirmable"

export default class extends Controller {
  static values = { confirmMessage: String }

  delete(event) {
    Confirmable.confirm.call(this, event)
    if (!event.defaultPrevented) {
      // Proceed with deletion
    }
  }
}
```

#### Anti-Patterns to Avoid

```javascript
// ❌ FORBIDDEN: Vanilla JavaScript
document.addEventListener('DOMContentLoaded', function() {
  const button = document.getElementById('my-button')
  button.addEventListener('click', function() {
    // Don't do this
  })
})

// ❌ FORBIDDEN: Inline JavaScript in HTML
onclick="handleClick()"

// ❌ FORBIDDEN: jQuery or other vanilla JS libraries for DOM manipulation
$('#element').click(function() {
  // Don't use jQuery
})
```

```ruby
# ❌ FORBIDDEN: Inline JavaScript in views
script { "function doSomething() { /* inline JS */ }" }

# ❌ FORBIDDEN: Vanilla JS event handlers
button(onclick: "alert('clicked')") { "Don't do this" }
```

#### Reusability Examples

```javascript
// ✅ EXCELLENT: Highly reusable autosave controller
// app/javascript/controllers/autosave_controller.js
import { Controller } from "@hotwired/stimulus"
import { debounce } from "../utils/debounce"

export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 2000 },
    method: { type: String, default: "PATCH" }
  }
  static targets = ["form", "status"]

  connect() {
    this.save = debounce(this.save.bind(this), this.intervalValue)
  }

  fieldChanged() {
    this.save()
  }

  async save() {
    this.showSaving()
    try {
      const formData = new FormData(this.formTarget)
      await fetch(this.urlValue, {
        method: this.methodValue,
        body: formData,
        headers: { "X-Requested-With": "XMLHttpRequest" }
      })
      this.showSaved()
    } catch (error) {
      this.showError()
    }
  }

  showSaving() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Saving..."
    }
  }

  showSaved() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Saved"
    }
  }

  showError() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Error saving"
    }
  }
}
```

```ruby
# ✅ USAGE: Reuse autosave across different forms
form_with(
  model: @product,
  data: {
    controller: "autosave",
    autosave_url_value: product_path(@product),
    action: "input->autosave#fieldChanged"
  }
) do |f|
  f.text_field :name, data: { action: "input->autosave#fieldChanged" }
  div(data: { autosave_target: "status" })
end
```

#### Testing Stimulus Controllers

```javascript
// ✅ CORRECT: Test controllers in isolation
// spec/javascript/controllers/toggle_controller_test.js
import { Application } from "@hotwired/stimulus"
import ToggleController from "../../app/javascript/controllers/toggle_controller"

describe("ToggleController", () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="toggle" data-toggle-hidden-class="hidden">
        <button data-action="click->toggle#toggle">Toggle</button>
        <div data-toggle-target="toggleable" class="visible">Content</div>
      </div>
    `

    const application = Application.start()
    application.register("toggle", ToggleController)
  })

  it("toggles content visibility", () => {
    const button = document.querySelector("button")
    const content = document.querySelector("[data-toggle-target='toggleable']")

    button.click()
    expect(content.classList.contains("hidden")).toBe(true)
  })
})
```

## Ruby-Specific Best Practices

### Use Ruby Idioms
```ruby
# Good: Ruby idiomatic
items.select(&:active?).map(&:name)

# Avoid: Non-idiomatic
items.select { |i| i.active? }.map { |i| i.name }
```

### Leverage Ruby Features
- Use keyword arguments for clarity
- Implement `to_s` and `inspect` for debugging
- Use blocks for configuration
- Take advantage of Ruby's metaprogramming carefully

### Thread Safety
- Design stateless components when possible
- Use mutex for shared mutable state
- Leverage concurrent-ruby for complex cases
- Document thread-safety guarantees

## AI Agent Best Practices

### 🚨 CRITICAL: RAAF ContextVariables Immutable Pattern

**RAAF ContextVariables uses an immutable pattern**. Each `.set()` call returns a **NEW instance**. Failure to capture the returned value will result in empty context and AI agents receiving "Unknown Company" instead of real data.

#### ✅ REQUIRED: Proper Immutable Usage
```ruby
# Correct pattern - capture each return value
def build_agent_context
  context = RAAF::DSL::ContextVariables.new
  context = context.set(:product, product)
  context = context.set(:company, company)
  context = context.set(:analysis_depth, analysis_depth)
  context  # Return built context
end
```

#### ❌ FORBIDDEN: Mutation Pattern (Will Fail)
```ruby
# WRONG - context will be empty!
def build_agent_context
  context = RAAF::DSL::ContextVariables.new
  context.set(:product, product)        # New instance not captured!
  context.set(:company, company)        # New instance not captured!
  context  # Returns empty context
end
```

#### Debugging Empty Context
```ruby
# Debug context issues
puts "Context size: #{context.size}"           # Should be > 0
puts "Product: #{context.get(:product)}"       # Should not be nil
puts "All variables: #{context.to_h.inspect}"  # Should show data
```

**Why Immutable?**
- Thread safety for concurrent AI operations
- Clear change tracking and debugging history
- Prevents accidental context mutation
- Functional programming best practices

### Mandatory RAAF DSL Prompt Usage
**ALL AI agents MUST use RAAF DSL prompt classes for improved readability, maintainability, and consistency:**

```ruby
# REQUIRED: Use RAAF DSL prompt classes
class MyAgent < Ai::Agents::ApplicationAgent
  include RAAF::DSL::Agents::AgentDsl
  include RAAF::DSL::Hooks::AgentHooks
  
  # RAAF DSL methods use prompt classes
  def build_instructions
    create_prompt.render(:system)
  end
  
  def build_schema
    create_prompt.schema
  end
  
  def build_user_prompt
    create_prompt.render(:user)
  end
  
  def create_prompt
    Ai::Prompts::MyPrompt.new(
      product: product,
      company: company,
      analysis_depth: analysis_depth
    )
  end
end

# FORBIDDEN: Inline string prompts
def build_instructions
  <<~PROMPT
    You are an expert...
  PROMPT
end
```

**Prompt Class Requirements:**
- Must inherit from `RAAF::DSL::Prompts::Base`
- Must use variable contracts (`required`, `optional`)
- Must use strict validation (`contract_mode :strict`)
- Must define JSON schemas using DSL
- Must separate system/user prompts into methods

### Agent Naming Conventions
AI agent names must follow strict naming rules to ensure compatibility with OpenAI's Structured Outputs API and other LLM providers:

```ruby
# Good: Valid schema-safe names
agent_name "MarketAnalysisAgent"
agent_name "DataProcessingAgent" 
agent_name "SearchTermGeneratorAgent"

# Bad: Invalid characters cause API errors
agent_name "Market Analysis Agent"      # Spaces not allowed
agent_name "Data-Processing Agent"      # Mixed separators
agent_name "Search & Filter Agent"      # Special characters
```

**Naming Rules:**
- Use PascalCase (no spaces, hyphens, or special characters)
- Must match pattern: `^[a-zA-Z0-9_-]+$`
- Be descriptive but concise
- End with "Agent" for clarity
- Maximum 50 characters recommended

### Agent Architecture Patterns
```ruby
class DataAnalysisAgent < Ai::Agents::ApplicationAgent
  include RAAF::DSL::Agents::AgentDsl
  include RAAF::DSL::Hooks::AgentHooks
  
  # Use schema-safe naming
  agent_name "DataAnalysisAgent"
  model "gpt-4o"
  max_turns 1
  
  # Clear context requirements
  REQUIRED_CONTEXT_KEYS = %i[data source_type].freeze
  
  def initialize(context:)
    validate_context!(context) if context.is_a?(Hash)
    super(context: context)
  end
  
  # Always validate inputs before expensive AI calls
  def build_instructions
    validate_input_data
    build_system_prompt
  end
  
  private
  
  def validate_input_data
    # Prevent API calls with insufficient data
    errors = []
    errors << "Data is required" if context.get(:data).blank?
    raise ArgumentError, errors.join(', ') if errors.any?
  end
end
```

### Schema Design Best Practices
- Define strict JSON schemas for consistent responses
- Use meaningful property names
- Include validation constraints (min/max, required fields)
- Provide clear descriptions for complex properties
- Test schema validation with example responses

### Error Handling for AI Agents
```ruby
def call
  Rails.logger.info "🤖 [#{self.class.name}] Starting analysis"
  
  begin
    raaf_result = run
    process_result(raaf_result)
  rescue RAAF::Models::APIError => e
    handle_api_error(e)
  rescue StandardError => e
    handle_general_error(e)
  end
end

private

def handle_api_error(error)
  if error.message.include?("rate limit")
    error_result("rate_limit", "AI service temporarily unavailable")
  elsif error.message.include?("schema")
    error_result("schema_error", "Response format error - please try again")
  else
    Rails.logger.error "❌ [#{self.class.name}] API Error: #{error.message}"
    error_result("api_error", "AI processing failed")
  end
end
```

### Performance Optimization
- Cache expensive agent results when appropriate
- Use appropriate model sizes (gpt-4o-mini for simple tasks, gpt-4o for complex analysis)
- Implement timeout handling for long-running agents
- Monitor token usage and implement cost controls
- Use streaming responses for real-time user feedback

---

*Customize this file with your team's specific practices. These guidelines apply to all code written by humans and AI agents.*
