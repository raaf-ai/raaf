**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Tools Guide
================

This guide covers the comprehensive tool ecosystem in Ruby AI Agents Factory (RAAF). Tools enable agents to interact with external systems, perform computations, and extend their capabilities beyond text generation.

After reading this guide, you will know:

* How to use built-in tools effectively
* How to create custom tools for your specific needs
* Advanced tool patterns and best practices
* Tool security and error handling
* Performance optimization for tool execution

--------------------------------------------------------------------------------

Introduction
------------

### The Tool Abstraction Layer

Tools represent the interface between AI reasoning and external systems. They provide a standardized way for agents to interact with the world beyond conversation, transforming AI from passive information processors into active system participants.

### Tool Categories and Capabilities

**Information Access Tools**: Enable agents to retrieve real-time data from web services, databases, file systems, and APIs. These tools provide the foundation for agents to access current information rather than relying solely on training data.

**Action Execution Tools**: Allow agents to perform operations like updating records, sending communications, processing transactions, and modifying system state. These tools enable agents to complete workflows rather than just provide recommendations.

**Computation Tools**: Provide agents with capabilities for complex calculations, data analysis, code execution, and specialized processing that exceeds natural language model capabilities.

**Integration Tools**: Facilitate interaction with external systems, services, and platforms, enabling agents to operate within existing technical ecosystems.

### Architectural Significance of Tools

Tools represent a fundamental architectural shift from passive AI systems to active AI agents. They transform the interaction model from question-and-answer to problem-solving and task completion.

**Capability Extension**: Tools extend AI capabilities beyond natural language processing to include system interaction, data manipulation, and workflow execution. This extension enables agents to operate as autonomous system components rather than isolated conversational interfaces.

**Real-World Integration**: Tools provide the mechanism for agents to interact with existing systems, databases, and workflows. This integration enables agents to work within established technical ecosystems rather than requiring separate, parallel systems.

**Verification and Feedback**: Tools enable agents to verify their actions and provide immediate feedback on results. This capability creates closed-loop systems where agents can assess the success of their actions and adjust accordingly.

**Workflow Completion**: Tools enable end-to-end workflow completion, transforming agents from advisory systems into operational systems capable of autonomous task execution.

### The Agency Transformation

The presence of tools fundamentally changes the nature of AI interaction. Systems evolve from consultation models (user asks, AI advises) to delegation models (user assigns, AI executes). This transformation requires different design patterns, error handling approaches, and security considerations.

### AI-Comprehensible Interface Design

Tools require different design patterns than traditional programming interfaces. They must be comprehensible to AI systems that understand natural language but lack programmer context.

**Explicit Parameter Naming**: Tool parameters must be self-documenting with clear, descriptive names that convey purpose and expected values.

```ruby
# AI-comprehensible interface
def process_customer_order(
  order_id:,           # The unique order identifier
  action:,             # What to do: 'status', 'cancel', 'modify'
  reason: nil          # Optional reason for action
)
```

**Comprehensive Documentation**: Tools require detailed documentation that explains parameters, expected inputs, possible outputs, and error conditions in natural language.

**Structured Error Handling**: Tools must provide structured error responses that AI systems can understand and act upon, rather than technical error messages designed for programmers.

**Type Safety**: Tools benefit from explicit type definitions and validation that help AI systems understand expected input formats and constraints.

### Design Philosophy

Tool design prioritizes AI comprehensibility over programmer convenience. This approach ensures that AI systems can effectively select, configure, and execute tools without human intervention.

### Capability Transformation Model

Tools fundamentally transform AI systems from advisory roles to operational roles:

**Advisory Model (Without Tools)**:
- Analysis and recommendation generation
- Information synthesis and explanation
- Strategic planning and ideation
- Limited to knowledge-based responses

**Operational Model (With Tools)**:
- Real-time data access and verification
- Action execution and workflow completion
- Result validation and feedback loops
- Integration with existing systems and processes

### The Autonomy Spectrum

Tools enable different levels of system autonomy:

**Level 1 - Information Access**: Tools provide current data to enhance AI responses
**Level 2 - Action Execution**: Tools enable AI systems to perform specific actions
**Level 3 - Workflow Automation**: Tools enable complete workflow execution
**Level 4 - System Integration**: Tools enable AI systems to operate as system components

### Integration Architecture

Tools serve as the integration layer between AI reasoning capabilities and external systems. This architecture enables AI systems to participate in existing workflows while maintaining system boundaries and security constraints.

Built-in Tools
--------------

### Production-Ready Tool Ecosystem

RAAF provides a comprehensive suite of built-in tools that address common integration patterns and operational requirements. These tools represent battle-tested implementations of frequently needed capabilities.

### Strategic Value of Built-in Tools

**Development Acceleration**: Built-in tools provide immediate capabilities without requiring custom integration development. This acceleration enables rapid prototyping and faster time-to-market for AI applications.

**Reliability Assurance**: Built-in tools incorporate comprehensive error handling, retry logic, and edge case management developed through extensive production use. This reliability reduces system failures and improves user experience.

**Security Implementation**: Built-in tools include security best practices, input validation, and safe execution patterns that prevent common vulnerabilities. This security foundation protects applications from tool-based attack vectors.

**Performance Optimization**: Built-in tools are optimized for performance and resource efficiency, incorporating caching, connection pooling, and other optimization patterns that improve system scalability.

### Architectural Patterns

Built-in tools demonstrate architectural patterns that inform custom tool development:

**Standardized Error Handling**: Consistent error response formats and recovery strategies
**Resource Management**: Efficient handling of connections, memory, and computational resources
**Security Boundaries**: Safe execution environments and input validation approaches
**Performance Optimization**: Caching strategies and efficient data processing patterns

### Tool Categories

Built-in tools span several functional categories, each addressing specific integration requirements and use cases.

### Web Search Tool

Search the web using OpenAI's hosted web search:

```ruby
require 'raaf-tools'

agent = RAAF::Agent.new(
  name: "ResearchAgent",
  instructions: "Help users research topics using web search",
  model: "gpt-4o"
)

# Add web search capability
web_search = RAAF::Tools::WebSearchTool.new
agent.add_tool(web_search.method(:call))

runner = RAAF::Runner.new(agent: agent)
result = runner.run("What are the latest developments in Ruby 3.3?")
```

This code creates a research agent that can access current web information to answer questions. When you ask about Ruby 3.3 developments, the agent will automatically perform web searches, analyze the results, and synthesize current information into a comprehensive response. The agent understands when to search, what terms to use, and how to combine multiple sources into coherent answers.

The web search tool handles all the complexity of API integration, result parsing, and content filtering behind the scenes. The agent receives clean, structured data from search results, which improves response quality while reducing token consumption.

**How web search transforms agents:** Without web search, an AI agent is limited to its training data, which has a knowledge cutoff. With web search, the agent becomes a research assistant that can access current information, verify claims, and explore topics beyond its training.

The web search tool handles the complexity of API integration, result parsing, and content filtering. It automatically extracts relevant information from search results and formats it for the AI model. This means the agent receives clean, structured data rather than raw HTML, improving response quality and reducing token consumption.

**Security considerations:** Web search tools can access potentially malicious content. RAAF's implementation includes content filtering, malware detection, and sandboxing to protect your application from harmful external content. It also respects robots.txt files and implements rate limiting to be a good citizen of the web.

Configuration options:

```ruby
web_search = RAAF::Tools::WebSearchTool.new(
  max_results: 10,           # Number of search results
  include_images: true,      # Include image results
  safe_search: :moderate,    # :off, :moderate, :strict
  region: 'us',             # Search region
  language: 'en'            # Search language
)
```

These configuration options control search behavior and result quality. The `max_results` parameter balances comprehensiveness with token consumption—more results provide broader context but consume more tokens and processing time. The `safe_search` setting filters inappropriate content but might exclude legitimate results in some domains.

Region and language settings significantly impact search quality. A customer service agent for a European company should use European search results and local languages. The agent will automatically adapt its responses to regional context and cultural nuances found in the search results.

**Configuration strategy:** These parameters aren't just options—they're performance and quality controls. `max_results` balances comprehensiveness with token consumption. More results provide broader context but consume more tokens and processing time. `safe_search` filters inappropriate content but might exclude legitimate results in some domains.

The `region` and `language` settings significantly impact search quality. A customer service agent for a European company should use European search results and local languages. The agent will automatically adapt its responses to regional context and cultural nuances found in the search results.

**Token optimization:** Web search can consume significant tokens if not managed properly. The tool automatically summarizes search results, extracts key information, and filters irrelevant content. You can further optimize by adjusting `max_results` based on your specific use case—research tasks might need 20 results, while quick fact-checking might only need 3.

### File Search Tool

Search through local files and documents:

```ruby
file_search = RAAF::Tools::FileSearchTool.new(
  search_paths: ['./docs', './src', './config'],
  file_extensions: ['.md', '.rb', '.yml', '.json'],
  max_file_size: 1_000_000,  # 1MB limit
  exclude_patterns: ['node_modules', '.git', 'tmp']
)

agent.add_tool(file_search.method(:call))

# Agent can now search your codebase
result = runner.run("Find all configuration files related to database settings")
```

This configuration creates a file search tool that can intelligently explore your codebase and documentation. When you ask about database settings, the agent will search through your specified directories, examine files matching your extensions, and identify relevant configuration files based on content analysis, not just filename matching.

The `search_paths` and `exclude_patterns` parameters serve as both performance optimizations and security controls. By restricting search to specific directories and excluding sensitive paths, you ensure the agent can't access configuration files, secrets, or system files that shouldn't be exposed to AI systems.

**Why file search is transformative:** File search transforms an AI agent from a generic assistant into a knowledgeable team member who understands your specific codebase, documentation, and configuration. Instead of giving general advice, the agent can reference your actual implementation, follow your coding conventions, and suggest changes based on your existing patterns.

The tool doesn't just search file names—it performs semantic search across file contents. It can find relevant code even when the exact terms aren't mentioned, understand context from surrounding code, and identify relationships between different parts of your codebase.

**Performance optimizations:** File search uses intelligent indexing and caching to avoid re-scanning unchanged files. It builds semantic indexes of your codebase, enabling fast similarity searches without re-processing every file. The `max_file_size` limit prevents memory issues with large generated files while still allowing access to substantial documentation.

**Security boundaries:** The `search_paths` and `exclude_patterns` parameters aren't just performance optimizations—they're security controls. By restricting search to specific directories and excluding sensitive paths, you ensure the agent can't access configuration files, secrets, or system files that shouldn't be exposed to AI systems.

### Code Interpreter Tool

#### The Day Our AI Agent Became a Data Scientist

A customer uploaded 50MB of sales data and asked: "Which products should we discontinue?"

Without code execution, our agent could only say: "I'd need to analyze your data to answer that."

With code execution, magic happened:

```python
# The agent wrote this code autonomously
import pandas as pd
import matplotlib.pyplot as plt

# Load and analyze sales data
df = pd.read_csv('sales_data.csv')

# Calculate key metrics
product_metrics = df.groupby('product_id').agg({
    'revenue': 'sum',
    'units_sold': 'sum',
    'return_rate': 'mean'
})

# Identify underperformers
underperformers = product_metrics[
    (product_metrics['revenue'] < product_metrics['revenue'].quantile(0.2)) &
    (product_metrics['return_rate'] > 0.15)
]

# Visualize findings
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
...
```

The agent identified 7 products losing money, created visualizations, and saved the company $200K/year.

#### Why Code Execution Changes Everything

**From Description to Demonstration**:

- Without: "The trend appears to be increasing"
- With: "Here's a graph showing 23% month-over-month growth"

**From Estimation to Calculation**:

- Without: "That seems like a lot of data"
- With: "Processing 1.2M records... found 47 anomalies"

**From Theory to Practice**:

- Without: "You could use machine learning"
- With: "I've trained a model with 94% accuracy. Here's the code."

#### Setting Up Safe Code Execution

```ruby
code_interpreter = RAAF::Tools::CodeInterpreterTool.new(
  allowed_languages: ['python', 'ruby', 'javascript'],
  timeout: 30,              # Execution timeout in seconds
  memory_limit: '512MB',    # Memory limit
  network_access: false     # Disable network for security
)

agent.add_tool(code_interpreter.method(:call))

# Agent can now run code
result = runner.run("Calculate the fibonacci sequence up to 100 and plot it")
```

#### Security: Learning from the "Crypto Mining Incident"

True story: An early version allowed network access. A clever user convinced the agent to mine cryptocurrency. The AWS bill was... memorable.

Now we sandbox everything:

- **Process Isolation**: Each execution runs in a separate container
- **Resource Limits**: CPU, memory, and time restrictions
- **Network Isolation**: No external access by default
- **File System Restrictions**: Can only access approved directories

These aren't paranoid measures—they're lessons learned the expensive way.

Supported languages and features:

```ruby
# Python with data science libraries
code_interpreter = RAAF::Tools::CodeInterpreterTool.new(
  language: 'python',
  libraries: [
    'numpy', 'pandas', 'matplotlib', 'seaborn',
    'scikit-learn', 'scipy', 'requests'
  ]
)

# Ruby with common gems
code_interpreter = RAAF::Tools::CodeInterpreterTool.new(
  language: 'ruby',
  gems: ['json', 'csv', 'nokogiri', 'httparty']
)

# JavaScript with Node.js
code_interpreter = RAAF::Tools::CodeInterpreterTool.new(
  language: 'javascript',
  runtime: 'node',
  packages: ['lodash', 'moment', 'axios']
)
```

**Language-specific optimizations:** Each language configuration is optimized for different use cases. Python with data science libraries excels at numerical analysis, visualization, and machine learning tasks. Ruby configurations leverage the language's strengths in text processing and web scraping. JavaScript setups are ideal for JSON manipulation and API interactions.

The pre-installed libraries aren't arbitrary—they're carefully chosen to provide maximum utility while maintaining security. Popular, well-maintained libraries reduce the risk of vulnerabilities while providing powerful capabilities that agents can leverage for complex tasks.

**Performance considerations:** Different languages have different performance characteristics. Python excels at data processing with NumPy but can be slower for general computation. JavaScript is fast for I/O operations but limited for CPU-intensive tasks. Ruby provides a good balance but isn't optimized for numerical computing. Choose based on your specific use case.

### Document Tool

Generate various document formats:

```ruby
document_tool = RAAF::Tools::DocumentTool.new(
  output_directory: './generated_docs',
  supported_formats: ['pdf', 'docx', 'html', 'markdown']
)

agent.add_tool(document_tool.method(:call))

# Agent can create professional documents
result = runner.run("Create a PDF report summarizing our Q4 sales data")
```

This code creates a document generation system that transforms conversational AI into a document production tool. When you ask for a Q4 sales report, the agent doesn't just provide analysis—it creates an actual PDF document with formatted content, charts, and professional presentation.

The document tool handles the complexity of format conversion, layout management, and file generation. The agent can focus on content creation while the tool manages the technical details of producing publication-ready documents in multiple formats.

**Document generation as business automation:** The document tool transforms agents from conversational assistants into document production systems. Instead of just discussing a report, the agent can actually create it—formatted, professional, and ready for distribution.

This capability addresses a common business need: converting data and analysis into presentable documents. The agent can take raw data, analyze it, draw conclusions, and produce a polished report in the appropriate format. This eliminates the manual work of copying insights from conversations into documents.

**Template-driven consistency:** Professional documents require consistent formatting, branding, and structure. The template system ensures that generated documents follow your organization's standards while allowing the AI to focus on content creation rather than formatting details.

Document generation with templates:

```ruby
document_tool = RAAF::Tools::DocumentTool.new(
  templates_directory: './templates',
  default_template: 'corporate_report.erb'
)

def generate_report(data:, template: 'default', format: 'pdf')
  document_tool.call(
    content: data,
    template: template,
    format: format,
    variables: {
      company_name: 'Acme Corp',
      report_date: Date.today,
      logo_path: './assets/logo.png'
    }
  )
end

agent.add_tool(method(:generate_report))
```

This template-driven approach ensures consistent document formatting across all generated reports. The template system separates content from presentation, allowing the AI to focus on analysis and insights while maintaining professional document standards.

The `variables` hash provides dynamic content that gets injected into templates, including company branding, current dates, and other contextual information. This creates personalized documents that follow organizational standards while containing AI-generated content.

### Computer Tool: When AI Meets the Desktop

The Computer Tool represents a paradigm shift in AI capabilities—from text-based interactions to visual understanding and physical desktop automation. This tool enables agents to literally "see" your screen and interact with any application, just like a human would.

#### The $200,000 Manual Process We Eliminated

A financial services client had a painful manual process: analysts spent 4 hours daily copying data from 15 different desktop applications into a master spreadsheet. Each application had a different interface, different data formats, and different quirks. The cost? $200,000 annually in analyst time.

We built an AI agent with the Computer Tool that:

1. **Takes screenshots** of each application
2. **Identifies data fields** using visual pattern recognition
3. **Extracts information** by clicking and copying
4. **Navigates between applications** using keyboard shortcuts
5. **Formats and consolidates** data into the master spreadsheet

The agent now completes this task in 20 minutes with 99.8% accuracy. The analysts focus on analysis instead of data entry.

#### How Computer Vision Meets AI Reasoning

The Computer Tool represents a fundamental shift in how we approach desktop automation. Traditional automation tools are essentially sophisticated scripts that follow predefined sequences of actions. They're powerful but inflexible—change the position of a button by a few pixels, and the automation breaks.

The Computer Tool combines computer vision with AI reasoning to create truly intelligent automation. Instead of relying on fixed coordinates or brittle selectors, it actually "sees" the screen the way a human would. It can identify buttons by their visual appearance, understand the context of different interface elements, and adapt to changes in the user interface.

This visual understanding is powered by the same AI models that can interpret natural language. When you ask the agent to "click the submit button," it doesn't just look for a button labeled "submit" at a specific location. Instead, it takes a screenshot, analyzes the visual elements, understands the context of the interface, and intelligently locates the most likely submit button based on visual cues like button styling, position, and surrounding elements.

The reasoning capability is what makes this truly powerful. The Computer Tool can understand intent, not just execute commands. If the usual submit button is disabled, it might recognize that a different action is needed first. If a dialog box appears unexpectedly, it can analyze the situation and determine the appropriate response. This combination of vision and reasoning creates automation that feels more like having a skilled human operator than running a script.

**Traditional RPA (Robotic Process Automation):**
- Brittle: Breaks when UI changes
- Scripted: Follows predefined paths
- Limited: Can't handle unexpected scenarios

**AI-Powered Computer Tool:**
- Adaptive: Understands visual context
- Intelligent: Reasons about what it sees
- Flexible: Handles variations and edge cases

The practical implications are enormous. Instead of spending weeks creating and maintaining brittle automation scripts, you can describe what you want to accomplish in natural language and let the AI figure out how to do it. The Computer Tool handles the complexity of visual recognition, interface navigation, and error recovery while you focus on the business logic and outcomes.

```ruby
# Basic computer tool setup
computer_tool = RAAF::Tools::ComputerTool.new(
  screen_resolution: [1920, 1080],
  click_delay: 0.5,         # Delay between clicks
  type_delay: 0.1,          # Delay between keystrokes
  screenshot_quality: :high, # :low, :medium, :high
  ocr_enabled: true,        # Enable text recognition
  confidence_threshold: 0.8  # Minimum confidence for element detection
)

agent.add_tool(computer_tool.method(:call))

# Agent can interact with desktop applications
result = runner.run("Take a screenshot and click on the 'Submit' button")
```

The configuration parameters are crucial for reliable automation. The `click_delay` and `type_delay` settings ensure that actions don't happen too quickly for applications to respond, preventing failures due to timing issues. The `screenshot_quality` affects both processing speed and accuracy of visual recognition.

The `ocr_enabled` setting activates text recognition, allowing the agent to read text from images and identify elements by their labels. The `confidence_threshold` determines how certain the tool must be before acting on visual elements, balancing accuracy with reliability.

#### Visual Element Detection Strategies

One of the most challenging aspects of desktop automation is reliably finding and interacting with user interface elements. Unlike web automation where you have direct access to the DOM structure, desktop automation must work with the visual representation of applications. The Computer Tool addresses this challenge through multiple complementary detection strategies, each optimized for different scenarios.

Understanding these strategies is crucial because no single approach works perfectly in all situations. Real-world applications have varying interface designs, update frequently, and may not follow consistent patterns. The Computer Tool's flexibility comes from its ability to intelligently choose and combine these approaches based on the specific situation.

**Method 1: Coordinate-Based Detection**

The most direct approach is to specify exact screen coordinates. This method is lightning-fast and works regardless of the application's internal structure. However, it's also the most fragile—if the window is resized, moved, or if the interface layout changes, the coordinates become invalid.

Coordinate-based detection is best used for:
- Initial setup and calibration
- Applications with fixed, unchanging layouts
- Quick prototyping and testing
- Situations where pixel-perfect precision is required

**Method 2: Text-Based Detection**

This approach uses Optical Character Recognition (OCR) to identify elements by their visible text. The Computer Tool can read text from the screen and locate buttons, labels, and other elements based on their textual content. This method is remarkably flexible because it works regardless of the underlying application technology.

Text-based detection excels when:
- Elements have clear, readable text labels
- Interface layout changes but text remains consistent
- Working with legacy applications without accessibility support
- Dealing with dynamically generated interfaces

The fuzzy matching capability is particularly powerful—it can handle slight variations in text due to different fonts, sizes, or even minor spelling differences. This makes automation more resilient to interface updates and localization changes.

**Method 3: Image-Based Detection**

Image-based detection works by comparing visual templates against the current screen. You provide a reference image of the element you want to find, and the Computer Tool uses computer vision algorithms to locate similar visual patterns. This approach is particularly effective for graphical elements like icons, buttons with unique styling, or complex visual components.

This method is ideal for:
- Icons and graphical elements without text
- Custom UI components with unique visual designs
- Applications with consistent visual styling
- Elements that are difficult to identify through other means

The similarity threshold is adjustable, allowing you to balance precision with flexibility. A higher threshold requires an exact match, while a lower threshold can accommodate slight variations in appearance.

**Method 4: Accessibility-Based Detection**

Modern applications often include accessibility metadata that describes interface elements for screen readers and other assistive technologies. The Computer Tool can leverage this information to identify elements by their semantic meaning rather than their visual appearance. This approach is the most robust because it works independently of visual changes.

Accessibility-based detection works best when:
- Applications follow accessibility guidelines
- You need maximum reliability across interface updates
- Working with standard system controls
- Compliance requirements mandate accessibility support

The combination of these detection methods creates a layered approach to element identification. The Computer Tool can start with the most reliable method available for a given element and fall back to alternatives if the primary approach fails. This redundancy is what makes AI-powered automation significantly more robust than traditional approaches.

```ruby
# Method 1: Coordinate-based clicking (most precise)
computer_tool.click(x: 100, y: 200)

# Method 2: Text-based clicking (most flexible)
computer_tool.click(text: "Submit Button")
computer_tool.click(text: "Save", fuzzy_match: true)  # Handles slight variations

# Method 3: Image-based clicking (most reliable)
computer_tool.click(image: "./button_template.png")
computer_tool.click(image: "./button_template.png", similarity: 0.9)

# Method 4: Accessibility-based clicking (most robust)
computer_tool.click(accessibility_id: "submit-btn")
computer_tool.click(role: "button", name: "Submit")
```

Each method has different trade-offs:

- **Coordinate-based**: Fast but brittle (breaks if UI changes)
- **Text-based**: Flexible but depends on OCR accuracy
- **Image-based**: Reliable but requires template maintenance
- **Accessibility-based**: Robust but requires accessible applications

The art of effective desktop automation lies in understanding when to use each approach and how to combine them for maximum reliability. The Computer Tool's intelligence comes from its ability to make these decisions automatically, choosing the most appropriate strategy based on the current context and falling back gracefully when primary methods fail.

#### Complex Automation Workflows

The Computer Tool excels at multi-step workflows that span multiple applications:

```ruby
# Enterprise workflow automation
def process_invoice_approval(invoice_id:)
  # Step 1: Open finance application
  computer_tool.key_combination(keys: ["cmd", "space"])
  computer_tool.type(text: "Finance App")
  computer_tool.key_press(key: "enter")
  computer_tool.wait_for_element(text: "Finance Dashboard", timeout: 10)
  
  # Step 2: Search for invoice
  computer_tool.click(text: "Search")
  computer_tool.type(text: invoice_id)
  computer_tool.key_press(key: "enter")
  
  # Step 3: Extract invoice details
  screenshot = computer_tool.screenshot
  invoice_data = extract_invoice_details(screenshot)
  
  # Step 4: Validate in approval system
  computer_tool.key_combination(keys: ["cmd", "tab"])  # Switch to approval system
  computer_tool.click(text: "New Approval")
  computer_tool.type(text: invoice_data[:vendor])
  computer_tool.tab_to_next_field
  computer_tool.type(text: invoice_data[:amount])
  
  # Step 5: Submit for approval
  computer_tool.click(text: "Submit for Approval")
  
  # Step 6: Confirm success
  success_message = computer_tool.wait_for_element(text: "Approval submitted", timeout: 5)
  
  {
    success: success_message.present?,
    invoice_id: invoice_id,
    amount: invoice_data[:amount],
    vendor: invoice_data[:vendor],
    approval_timestamp: Time.current
  }
end

agent.add_tool(method(:process_invoice_approval))
```

This workflow demonstrates the Computer Tool's ability to:

1. **Navigate between applications** using keyboard shortcuts
2. **Wait for elements** to appear before proceeding
3. **Extract visual information** from screenshots
4. **Perform complex form interactions** with tab navigation
5. **Validate results** by checking for confirmation messages

#### Advanced Computer Tool Features

```ruby
# Advanced screenshot capabilities
computer_tool.screenshot(
  region: [0, 0, 800, 600],    # Specific screen region
  format: :png,                # Output format
  include_cursor: false,       # Hide cursor in screenshot
  mark_elements: true          # Highlight detected elements
)

# Intelligent text input
computer_tool.type(
  text: "Hello, world!",
  clear_first: true,          # Clear field before typing
  verify_input: true,         # Verify text was entered correctly
  paste_mode: true            # Use paste instead of typing
)

# Advanced element waiting
computer_tool.wait_for_element(
  text: "Processing complete",
  timeout: 30,                # Maximum wait time
  poll_interval: 1,           # Check every second
  disappear: false            # Wait for element to appear (not disappear)
)

# Complex mouse operations
computer_tool.drag(
  from: [100, 100],
  to: [200, 200],
  duration: 1.0,              # Drag duration in seconds
  button: :left               # Mouse button
)

# Keyboard shortcut sequences
computer_tool.key_sequence([
  ["cmd", "c"],               # Copy
  ["cmd", "tab"],             # Switch app
  ["cmd", "v"]                # Paste
])
```

These advanced features enable sophisticated automation scenarios:

- **Region screenshots** focus on specific areas for better performance
- **Intelligent text input** handles different input methods and validation
- **Element waiting** ensures reliable automation timing
- **Complex mouse operations** enable drag-and-drop functionality
- **Keyboard sequences** automate complex shortcuts

#### Error Handling and Recovery

Computer automation faces unique challenges that require robust error handling:

```ruby
class RobustComputerTool
  def initialize(base_tool)
    @computer_tool = base_tool
    @retry_count = 0
    @max_retries = 3
  end
  
  def safe_click(element_description)
    begin
      # Try multiple detection methods
      if element_description.is_a?(Hash)
        if element_description[:text]
          @computer_tool.click(text: element_description[:text])
        elsif element_description[:image]
          @computer_tool.click(image: element_description[:image])
        elsif element_description[:coordinates]
          @computer_tool.click(x: element_description[:coordinates][0], 
                               y: element_description[:coordinates][1])
        end
      else
        @computer_tool.click(text: element_description)
      end
      
      # Verify click worked
      sleep(0.5)
      verify_click_success(element_description)
      
    rescue ElementNotFoundError => e
      @retry_count += 1
      if @retry_count <= @max_retries
        # Take screenshot for debugging
        screenshot = @computer_tool.screenshot
        save_debug_screenshot(screenshot, "click_attempt_#{@retry_count}")
        
        # Try alternative detection method
        retry_with_alternative_method(element_description)
        retry
      else
        raise "Failed to click element after #{@max_retries} attempts: #{e.message}"
      end
    end
  end
  
  private
  
  def verify_click_success(element_description)
    # Check if UI changed as expected
    # This depends on the specific application
  end
  
  def retry_with_alternative_method(element_description)
    # Implement fallback strategies
    # For example, try fuzzy text matching or image similarity reduction
  end
end
```

#### Performance Optimization

Computer tool operations can be slow due to screenshot processing and visual recognition. Here's how to optimize:

```ruby
# Optimize screenshot operations
computer_tool.configure(
  screenshot_cache_ttl: 2,    # Cache screenshots for 2 seconds
  region_detection: true,     # Only screenshot relevant regions
  compression_level: 6,       # Balance quality vs speed
  parallel_processing: true   # Process multiple elements simultaneously
)

# Batch operations where possible
def efficient_form_filling(form_data)
  # Take one screenshot and analyze all fields
  screenshot = computer_tool.screenshot
  fields = computer_tool.detect_form_fields(screenshot)
  
  # Plan optimal filling sequence
  fill_sequence = optimize_field_sequence(fields, form_data)
  
  # Execute efficiently
  fill_sequence.each do |field, value|
    computer_tool.click(field[:coordinates])
    computer_tool.type(text: value, verify_input: false)  # Skip verification for speed
  end
  
  # Verify all fields at once
  verify_form_completion(form_data)
end
```

#### Security and Safety Considerations

Computer tool automation requires careful security consideration:

```ruby
# Security-conscious computer tool
class SecureComputerTool
  def initialize(base_tool, security_config)
    @computer_tool = base_tool
    @allowed_applications = security_config[:allowed_applications]
    @restricted_actions = security_config[:restricted_actions]
    @audit_logger = security_config[:audit_logger]
  end
  
  def safe_action(action_type, params)
    # Verify application is allowed
    current_app = get_current_application
    unless @allowed_applications.include?(current_app)
      raise SecurityError, "Action not allowed in application: #{current_app}"
    end
    
    # Check for restricted actions
    if @restricted_actions.include?(action_type)
      raise SecurityError, "Restricted action: #{action_type}"
    end
    
    # Log action for audit
    @audit_logger.log(
      action: action_type,
      application: current_app,
      parameters: sanitize_params(params),
      timestamp: Time.current,
      user_agent: get_user_context
    )
    
    # Execute action
    @computer_tool.public_send(action_type, params)
  end
  
  private
  
  def get_current_application
    # Detect currently active application
    # Platform-specific implementation
  end
  
  def sanitize_params(params)
    # Remove sensitive information from logs
    params.except(:password, :ssn, :credit_card)
  end
end
```

#### Real-World Applications

The Computer Tool enables powerful automation scenarios across industries:

**Financial Services:**
- Automated regulatory reporting across multiple systems
- Cross-system data validation and reconciliation
- Automated compliance checking in trading systems

**Healthcare:**
- Patient data aggregation from multiple EMR systems
- Automated insurance claim processing
- Medical image analysis workflow automation

**Manufacturing:**
- Quality control data collection from inspection systems
- Production planning across multiple planning tools
- Automated inventory management

**Retail:**
- Multi-channel inventory synchronization
- Automated pricing updates across platforms
- Customer service case routing and escalation

The Computer Tool transforms AI agents from conversational assistants into active participants in your desktop workflows. By combining visual understanding with intelligent reasoning, it enables automation that was previously impossible with traditional RPA tools.

The key to success with the Computer Tool is understanding its capabilities and limitations, implementing robust error handling, and designing workflows that leverage its strengths while mitigating potential fragility. When properly implemented, it can eliminate hours of manual work while improving accuracy and consistency.

### Vector Search Tool: The Memory That Understands Meaning

Vector search enables semantic understanding of content rather than just keyword matching.

We had 10 years of technical documentation—50,000 documents, 200 million words. A customer asked: "How do we handle multi-tenant database isolation?" Our keyword search found nothing. The answer existed in a document titled "Architectural Patterns for SaaS Applications" but it never used the word "multi-tenant."

Vector search found it in 0.3 seconds.

#### What Makes Vector Search Revolutionary

**Traditional Search**: Looks for exact words
**Vector Search**: Understands meaning

Think of it like this:

- Traditional search is like looking for a specific book by its exact title
- Vector search is like asking a librarian "I need something about keeping customer data separate in cloud apps"

#### The Three-Step Vector Search Process

**Step 1: Turn Text into Numbers (Embeddings)**

```ruby
# Text becomes a 1536-dimensional vector
"How to scale databases" → [0.023, -0.045, 0.891, ...]
"Database scaling guide" → [0.025, -0.043, 0.889, ...]
# Notice: Different words, similar vectors!
```

**Step 2: Store Vectors in High-Dimensional Space**

```ruby
# Similar concepts cluster together
# Even if they use completely different words
Database concepts: [scaling, sharding, replication, partitioning]
Performance concepts: [optimization, caching, indexing, tuning]
Security concepts: [encryption, authentication, authorization, audit]
```

**Step 3: Find Nearest Neighbors**

```ruby
# Query: "How to make my app faster?"
# Finds: Performance optimization guides, caching tutorials, 
#        database indexing docs, CDN setup guides
# Even though none contain the word "faster"
```

#### Basic Vector Search Implementation

```ruby
# Initialize with thoughtful configuration
vector_search = RAAF::Tools::VectorSearchTool.new(
  # Choose your embedding model wisely
  embedding_model: 'text-embedding-3-small',  # Good balance
  # embedding_model: 'text-embedding-3-large',  # More accurate, more expensive
  
  # Where to store the index
  index_path: './vector_index',
  
  # How similar is "similar enough"?
  similarity_threshold: 0.7,  # 0.0 = anything, 1.0 = exact match
  
  # Advanced options
  dimension: 1536,            # Must match embedding model
  metric: 'cosine',          # 'cosine', 'euclidean', or 'dot_product'
  index_type: 'hnsw'         # Hierarchical Navigable Small World
)

# Index your documents
vector_search.index_documents([
  { 
    id: 'doc_001',
    content: 'Ruby is a dynamic programming language focused on simplicity',
    metadata: { 
      type: 'definition',
      source: 'official_docs',
      last_updated: '2024-01-15',
      importance: 'high'
    }
  },
  {
    id: 'doc_002', 
    content: 'Python emphasizes code readability with significant whitespace',
    metadata: {
      type: 'comparison',
      source: 'tech_blog',
      author: 'jane_doe',
      tags: ['python', 'syntax', 'beginner']
    }
  }
])

# Add to agent
agent.add_tool(vector_search.method(:search))

# Now your agent understands meaning
result = runner.run("Find information about readable programming languages")
# Finds both Ruby (simplicity) and Python (readability) documents
```

#### Advanced Vector Search Patterns

**Pattern 1: Multi-Index Strategy**

```ruby
class MultiIndexVectorSearch
  def initialize
    # Different indexes for different content types
    @indexes = {
      technical: create_index('technical_docs', 'text-embedding-3-large'),
      support: create_index('support_tickets', 'text-embedding-3-small'),
      chat: create_index('chat_history', 'text-embedding-3-small')
    }
  end
  
  def search(query:, search_type: :all, limit: 10)
    case search_type
    when :all
      # Search all indexes, merge results
      results = @indexes.map do |name, index|
        index.search(query, limit: limit / @indexes.size)
      end
      merge_and_rerank(results)
      
    when :technical_only
      @indexes[:technical].search(query, limit: limit)
      
    when :contextual
      # Use chat history to enhance technical search
      context = @indexes[:chat].search(query, limit: 3)
      enhanced_query = build_contextual_query(query, context)
      @indexes[:technical].search(enhanced_query, limit: limit)
    end
  end
  
  private
  
  def merge_and_rerank(results)
    # Combine results from multiple indexes
    all_results = results.flatten
    
    # Re-rank based on:
    # 1. Similarity score
    # 2. Source credibility 
    # 3. Recency
    # 4. User preferences
    rerank_results(all_results)
  end
end
```

**Pattern 2: Hybrid Search (Keyword + Vector)**

```ruby
class HybridSearchTool
  def initialize
    @vector_search = RAAF::Tools::VectorSearchTool.new(
      embedding_model: 'text-embedding-3-small'
    )
    @keyword_search = RAAF::Tools::KeywordSearchTool.new(
      analyzer: 'english',
      boost_exact_matches: true
    )
  end
  
  def search(query:, mode: :hybrid)
    case mode
    when :vector_only
      @vector_search.search(query)
      
    when :keyword_only  
      @keyword_search.search(query)
      
    when :hybrid
      # Get results from both
      vector_results = @vector_search.search(query, limit: 20)
      keyword_results = @keyword_search.search(query, limit: 20)
      
      # Combine with weighted scores
      combine_results(
        vector_results,
        keyword_results,
        vector_weight: 0.7,
        keyword_weight: 0.3
      )
    end
  end
  
  def combine_results(vector_results, keyword_results, vector_weight:, keyword_weight:)
    # Create unified scoring
    scored_results = {}
    
    # Add vector results
    vector_results.each do |result|
      scored_results[result[:id]] = {
        content: result[:content],
        vector_score: result[:score] * vector_weight,
        keyword_score: 0,
        metadata: result[:metadata]
      }
    end
    
    # Add keyword results
    keyword_results.each do |result|
      if scored_results[result[:id]]
        scored_results[result[:id]][:keyword_score] = result[:score] * keyword_weight
      else
        scored_results[result[:id]] = {
          content: result[:content],
          vector_score: 0,
          keyword_score: result[:score] * keyword_weight,
          metadata: result[:metadata]
        }
      end
    end
    
    # Calculate final scores and sort
    scored_results.map do |id, data|
      data[:final_score] = data[:vector_score] + data[:keyword_score]
      data[:id] = id
      data
    end.sort_by { |r| -r[:final_score] }
  end
end
```

**Pattern 3: Contextual Enhancement**

```ruby
class ContextualVectorSearch
  def initialize
    @vector_tool = RAAF::Tools::VectorSearchTool.new(
      embedding_model: 'text-embedding-3-large'
    )
    @conversation_history = []
  end
  
  def search_with_context(query:, user_profile: nil)
    # Build enhanced query with context
    enhanced_query = build_enhanced_query(
      base_query: query,
      recent_context: extract_recent_topics,
      user_preferences: user_profile
    )
    
    # Search with enhanced query
    results = @vector_tool.search(enhanced_query)
    
    # Post-process based on context
    filtered_results = apply_contextual_filters(results, user_profile)
    
    # Learn from this interaction
    update_context(query, filtered_results)
    
    filtered_results
  end
  
  private
  
  def build_enhanced_query(base_query:, recent_context:, user_preferences:)
    # Add context to improve search relevance
    enhanced = base_query
    
    # Add recent topic context
    if recent_context.any?
      enhanced += " Related to: #{recent_context.join(', ')}"
    end
    
    # Add user preference context
    if user_preferences
      enhanced += " For #{user_preferences[:expertise_level]} level"
      enhanced += " Focus on #{user_preferences[:interests].join(', ')}" if user_preferences[:interests]
    end
    
    enhanced
  end
  
  def extract_recent_topics
    # Extract key topics from recent conversation
    @conversation_history.last(5).flat_map do |message|
      extract_key_phrases(message)
    end.uniq
  end
end
```

#### Real-World Vector Search Applications

**1. Intelligent Documentation Assistant**

```ruby
class DocumentationAssistant
  def initialize
    @vector_search = RAAF::Tools::VectorSearchTool.new(
      embedding_model: 'text-embedding-3-large',
      index_path: './docs_index'
    )
    
    # Index all documentation with rich metadata
    index_documentation
  end
  
  def answer_question(question)
    # Search for relevant documentation
    relevant_docs = @vector_search.search(
      question,
      limit: 5,
      metadata_filters: {
        type: ['api_reference', 'guide', 'tutorial'],
        version: ENV['DOCS_VERSION'] || 'latest'
      }
    )
    
    # Build context from relevant docs
    context = build_context_from_docs(relevant_docs)
    
    # Generate answer using context
    generate_answer(question, context)
  end
  
  private
  
  def index_documentation
    Dir.glob('./docs/**/*.md').each do |file|
      content = File.read(file)
      metadata = extract_metadata(file, content)
      
      # Index with rich metadata
      @vector_search.index_document({
        id: file,
        content: content,
        metadata: metadata
      })
    end
  end
  
  def extract_metadata(file, content)
    {
      path: file,
      type: categorize_doc_type(file),
      version: extract_version(content),
      last_modified: File.mtime(file),
      complexity: assess_complexity(content),
      topics: extract_topics(content),
      code_examples: count_code_blocks(content)
    }
  end
end
```

**2. Customer Support Knowledge Base**

```ruby
class SupportKnowledgeBase
  def initialize
    @vector_search = RAAF::Tools::VectorSearchTool.new(
      embedding_model: 'text-embedding-3-small'
    )
    
    # Index support tickets, solutions, and FAQs
    index_support_data
  end
  
  def find_similar_issues(customer_description)
    # Search for similar past issues
    similar_tickets = @vector_search.search(
      customer_description,
      limit: 10,
      metadata_filters: {
        status: 'resolved',
        satisfaction: ['high', 'medium']
      }
    )
    
    # Group by solution type
    solutions = group_by_solution(similar_tickets)
    
    # Return ranked solutions
    {
      immediate_solutions: solutions[:quick_fix],
      guided_solutions: solutions[:step_by_step],
      escalation_needed: solutions[:complex]
    }
  end
  
  def auto_tag_ticket(ticket_content)
    # Find similar tickets to infer tags
    similar = @vector_search.search(ticket_content, limit: 20)
    
    # Extract common tags from similar tickets
    tag_frequency = Hash.new(0)
    similar.each do |ticket|
      ticket[:metadata][:tags].each { |tag| tag_frequency[tag] += 1 }
    end
    
    # Return most relevant tags
    tag_frequency.sort_by { |_, count| -count }
                 .first(5)
                 .map { |tag, _| tag }
  end
end
```

**3. Code Example Finder**

```ruby
class CodeExampleFinder
  def initialize
    @vector_search = RAAF::Tools::VectorSearchTool.new(
      embedding_model: 'code-embedding-model'  # Specialized for code
    )
    
    index_code_examples
  end
  
  def find_examples(description)
    # Search for code examples matching the description
    examples = @vector_search.search(
      description,
      limit: 5,
      boost_fields: {
        'metadata.language': 2.0,
        'metadata.framework': 1.5
      }
    )
    
    # Format examples for display
    examples.map do |example|
      {
        code: example[:content],
        language: example[:metadata][:language],
        description: example[:metadata][:description],
        complexity: example[:metadata][:complexity],
        dependencies: example[:metadata][:dependencies],
        related_concepts: find_related_concepts(example)
      }
    end
  end
end
```

#### Performance Optimization for Vector Search

**1. Batch Processing**

```ruby
class OptimizedVectorSearch
  def batch_index(documents, batch_size: 100)
    documents.each_slice(batch_size) do |batch|
      # Generate embeddings for entire batch
      embeddings = generate_batch_embeddings(batch.map { |d| d[:content] })
      
      # Index with pre-computed embeddings
      batch.each_with_index do |doc, idx|
        index_with_embedding(doc, embeddings[idx])
      end
    end
  end
  
  def parallel_search(queries, max_threads: 5)
    results = Concurrent::Hash.new
    thread_pool = Concurrent::FixedThreadPool.new(max_threads)
    
    queries.each do |query_id, query_text|
      thread_pool.post do
        results[query_id] = search(query_text)
      end
    end
    
    thread_pool.shutdown
    thread_pool.wait_for_termination
    
    results
  end
end
```

**2. Caching Strategies**

```ruby
class CachedVectorSearch
  def initialize
    @vector_search = RAAF::Tools::VectorSearchTool.new
    @embedding_cache = LRUCache.new(max_size: 10000)
    @result_cache = TTLCache.new(ttl: 3600)  # 1 hour
  end
  
  def search_with_cache(query)
    # Check result cache first
    cache_key = Digest::SHA256.hexdigest(query)
    cached_result = @result_cache.get(cache_key)
    return cached_result if cached_result
    
    # Get or compute embedding
    embedding = get_or_compute_embedding(query)
    
    # Perform search
    results = @vector_search.search_by_embedding(embedding)
    
    # Cache results
    @result_cache.set(cache_key, results)
    
    results
  end
  
  private
  
  def get_or_compute_embedding(text)
    cache_key = Digest::SHA256.hexdigest(text)
    
    @embedding_cache.get(cache_key) || begin
      embedding = generate_embedding(text)
      @embedding_cache.set(cache_key, embedding)
      embedding
    end
  end
end
```

#### Common Pitfalls and Solutions

**Pitfall 1: Embedding Model Mismatch**

```ruby
# Wrong: Mixing embedding models
vector_search.index_with_model(doc1, 'text-embedding-3-small')
vector_search.index_with_model(doc2, 'text-embedding-3-large')
# Results in meaningless similarity scores!

# Right: Consistent embedding model
vector_search = RAAF::Tools::VectorSearchTool.new(
  embedding_model: 'text-embedding-3-small'  # Use everywhere
)
```

**Pitfall 2: Over-Indexing**

```ruby
# Wrong: Indexing everything
vector_search.index_document({
  content: entire_book_text  # 500,000 words
})

# Right: Chunk intelligently
chunker = TextChunker.new(max_tokens: 500, overlap: 50)
chunks = chunker.chunk(entire_book_text)

chunks.each_with_index do |chunk, idx|
  vector_search.index_document({
    id: "book_chunk_#{idx}",
    content: chunk,
    metadata: {
      source: 'book_title',
      chapter: extract_chapter(chunk),
      position: idx
    }
  })
end
```

**Pitfall 3: Ignoring Metadata**

```ruby
# Wrong: Content only
vector_search.index_document({ content: "Ruby tutorial" })

# Right: Rich metadata for filtering
vector_search.index_document({
  content: "Ruby tutorial",
  metadata: {
    type: 'tutorial',
    difficulty: 'beginner',
    topics: ['ruby', 'programming', 'basics'],
    author: 'expert_name',
    rating: 4.8,
    views: 15000,
    last_updated: Date.today,
    prerequisites: ['basic_programming'],
    estimated_time: '2 hours'
  }
})
```

#### The Future of Vector Search

Vector search is evolving rapidly:

1. **Multi-Modal Embeddings**: Search across text, images, and code with unified embeddings
2. **Sparse-Dense Hybrid**: Combining keyword precision with semantic understanding
3. **Learned Embeddings**: Models that adapt to your specific domain
4. **Graph-Enhanced Search**: Incorporating relationship data into vector similarity

The key is starting simple and evolving based on real user needs. Every improvement should be driven by actual search failures, not theoretical possibilities.

### MCP (Model Context Protocol) Tool

#### MCP Integration Benefits

AI agents become significantly more useful when they can interact with existing systems and tools. Without integrations, agents are limited to providing advice based on their training data rather than accessing current, specific information.

The Model Context Protocol (MCP) is the universal translator that connects your AI agent to the world. Developed by [Anthropic](https://anthropic.com), MCP creates a standardized way for AI systems to securely access external tools and data sources.

#### Why MCP Matters: The Enterprise Reality

**Before MCP**: Every tool integration was custom-built

- 6 months to integrate with internal wiki
- 3 months to connect to ticketing system  
- 2 months to access code repositories
- Each integration brittle and hard to maintain

**After MCP**: Standardized, secure, scalable

- 1 week to integrate with any MCP-compatible service
- Consistent security model across all tools
- Easy to maintain and extend
- Growing ecosystem of ready-to-use tools

#### Basic MCP Integration

```ruby
# Simple MCP tool setup
mcp_tool = RAAF::Tools::MCPTool.new(
  server_url: 'http://localhost:8000',
  tools: ['filesystem', 'git', 'database']
)

agent.add_tool(mcp_tool.method(:call))

# Agent can now use external MCP tools
result = runner.run("Use the git tool to check the repository status")
```

#### Advanced MCP Configuration

```ruby
# Production-ready MCP setup
mcp_tool = RAAF::Tools::MCPTool.new(
  server_url: ENV['MCP_SERVER_URL'],
  authentication: {
    type: 'bearer',
    token: ENV['MCP_ACCESS_TOKEN']
  },
  timeout: 30,
  retry_config: {
    max_retries: 3,
    backoff_factor: 2
  },
  tools: {
    'filesystem' => {
      allowed_paths: ['/workspace', '/tmp'],
      max_file_size: 10 * 1024 * 1024  # 10MB
    },
    'git' => {
      allowed_repos: ['main', 'staging'],
      read_only: false
    },
    'database' => {
      connection_string: ENV['DATABASE_URL'],
      allowed_operations: ['SELECT', 'INSERT', 'UPDATE']
    }
  }
)

agent.add_tool(mcp_tool.method(:call))
```

#### Multi-Server MCP Architecture

```ruby
class MCPOrchestrator
  def initialize
    @servers = {
      development: RAAF::Tools::MCPTool.new(
        server_url: 'http://dev-tools.internal:8000',
        tools: ['filesystem', 'git', 'docker']
      ),
      data: RAAF::Tools::MCPTool.new(
        server_url: 'http://data-tools.internal:8001',
        tools: ['database', 'analytics', 'reporting']
      ),
      external: RAAF::Tools::MCPTool.new(
        server_url: 'http://external-apis.internal:8002',
        tools: ['slack', 'jira', 'confluence']
      )
    }
  end
  
  def call(tool_name:, **params)
    # Route to appropriate server
    server = find_server_for_tool(tool_name)
    raise "Unknown tool: #{tool_name}" unless server
    
    # Execute with proper context
    server.call(tool_name: tool_name, **params)
  end
  
  private
  
  def find_server_for_tool(tool_name)
    @servers.each do |name, server|
      return server if server.available_tools.include?(tool_name)
    end
    nil
  end
end

# Use orchestrator
orchestrator = MCPOrchestrator.new
agent.add_tool(orchestrator.method(:call))
```

#### Real-World MCP Applications

**1. Development Workflow Integration**

```ruby
# MCP server provides development tools
mcp_dev = RAAF::Tools::MCPTool.new(
  server_url: 'http://dev-server:8000',
  tools: ['git', 'docker', 'kubernetes', 'ci_cd']
)

agent.add_tool(mcp_dev.method(:call))

# Agent can now:
# - Check git status and create branches
# - Build and deploy Docker containers
# - Monitor Kubernetes deployments
# - Trigger CI/CD pipelines

result = runner.run(
  "Check the status of the user-auth service, " +
  "and if it's failing, roll back to the previous version"
)
```

**2. Data Analysis Integration**

```ruby
# MCP server provides data tools
mcp_data = RAAF::Tools::MCPTool.new(
  server_url: 'http://data-server:8001',
  tools: ['sql_query', 'analytics', 'visualization']
)

agent.add_tool(mcp_data.method(:call))

# Agent can now:
# - Execute SQL queries safely
# - Generate analytics reports
# - Create visualizations
# - Export data in various formats

result = runner.run(
  "Show me the top 10 products by revenue this month, " +
  "and create a chart comparing them to last month"
)
```

**3. Customer Support Integration**

```ruby
# MCP server provides support tools
mcp_support = RAAF::Tools::MCPTool.new(
  server_url: 'http://support-server:8002',
  tools: ['ticket_system', 'knowledge_base', 'user_lookup']
)

agent.add_tool(mcp_support.method(:call))

# Agent can now:
# - Search knowledge base
# - Look up customer information
# - Create and update tickets
# - Escalate issues

result = runner.run(
  "Customer john.doe@example.com is having login issues. " +
  "Check their account status and previous tickets"
)
```

#### MCP Security Best Practices

```ruby
class SecureMCPTool < RAAF::Tools::MCPTool
  def initialize(config)
    super(config)
    @rate_limiter = RateLimiter.new(requests_per_minute: 60)
    @audit_logger = AuditLogger.new
  end
  
  def call(tool_name:, **params)
    # Rate limiting
    @rate_limiter.check_rate_limit!
    
    # Input validation
    validate_tool_access(tool_name)
    sanitize_parameters(params)
    
    # Audit logging
    @audit_logger.log_request(tool_name, params)
    
    begin
      result = super(tool_name: tool_name, **params)
      @audit_logger.log_success(tool_name, result)
      result
    rescue => e
      @audit_logger.log_error(tool_name, e)
      raise
    end
  end
  
  private
  
  def validate_tool_access(tool_name)
    allowed_tools = ENV['MCP_ALLOWED_TOOLS']&.split(',') || []
    raise "Unauthorized tool: #{tool_name}" unless allowed_tools.include?(tool_name)
  end
  
  def sanitize_parameters(params)
    params.each do |key, value|
      if value.is_a?(String)
        # Prevent injection attacks
        raise "Invalid parameter" if value.include?('..') || value.include?('&&')
      end
    end
  end
end
```

#### Performance Optimization for MCP

```ruby
class OptimizedMCPTool < RAAF::Tools::MCPTool
  def initialize(config)
    super(config)
    @connection_pool = ConnectionPool.new(size: 10, timeout: 5) do
      create_connection
    end
    @cache = LRUCache.new(max_size: 1000)
  end
  
  def call(tool_name:, **params)
    # Check cache for idempotent operations
    if cacheable_operation?(tool_name, params)
      cache_key = generate_cache_key(tool_name, params)
      cached_result = @cache.get(cache_key)
      return cached_result if cached_result
    end
    
    # Use connection pool
    result = @connection_pool.with do |connection|
      execute_tool(connection, tool_name, params)
    end
    
    # Cache result if appropriate
    if cacheable_operation?(tool_name, params)
      @cache.set(cache_key, result)
    end
    
    result
  end
  
  private
  
  def cacheable_operation?(tool_name, params)
    # Cache read operations for 5 minutes
    read_operations = ['git_status', 'database_query', 'file_read']
    read_operations.include?(tool_name)
  end
end
```

#### Building Your Own MCP Server

```ruby
# Simple MCP server for custom tools
class CustomMCPServer
  def initialize(port: 8000)
    @port = port
    @tools = {}
    register_default_tools
  end
  
  def register_tool(name, &block)
    @tools[name] = block
  end
  
  def start
    require 'sinatra'
    
    set :port, @port
    
    post '/execute' do
      request_data = JSON.parse(request.body.read)
      tool_name = request_data['tool']
      params = request_data['params']
      
      if @tools[tool_name]
        result = @tools[tool_name].call(params)
        { success: true, result: result }.to_json
      else
        status 404
        { success: false, error: "Tool not found: #{tool_name}" }.to_json
      end
    end
    
    get '/tools' do
      { tools: @tools.keys }.to_json
    end
  end
  
  private
  
  def register_default_tools
    register_tool('system_info') do |params|
      {
        hostname: `hostname`.strip,
        uptime: `uptime`.strip,
        disk_usage: `df -h`.strip
      }
    end
    
    register_tool('process_list') do |params|
      processes = `ps aux`.strip.split("\n")
      {
        count: processes.length - 1,
        processes: processes[1..10]  # Top 10 processes
      }
    end
  end
end

# Start custom MCP server
server = CustomMCPServer.new(port: 8000)
server.start
```

#### The Future of MCP

The Model Context Protocol is evolving rapidly:

1. **Standardized Tool Ecosystem**: Growing library of MCP-compatible tools
2. **Enhanced Security**: Fine-grained permissions and audit trails
3. **Performance Improvements**: Connection pooling and caching built-in
4. **Multi-Modal Support**: Tools that work with text, images, and code
5. **Federated Architecture**: Tools that span multiple organizations

The key is starting with simple integrations and building complexity based on real needs. Every MCP integration should solve a specific business problem, not add complexity for its own sake.

Custom Tool Creation
--------------------

Creating custom tools is straightforward and follows Ruby conventions.

### Why Custom Tools Are Your Competitive Advantage

Every business has unique processes. Generic AI can't handle them. Custom tools can.

Real example from a logistics company:

**Generic AI**: "I can help you track packages"
**Their Reality**: 17 different shipping systems, 3 internal APIs, 2 legacy databases

We built custom tools that understood their chaos:

```ruby
def track_shipment_across_systems(tracking_number:)
  # Check System A (handles 40% of shipments)
  result = LegacySystemA.query(tracking_number)
  return format_result(result, 'SystemA') if result
  
  # Check System B (handles 35% of shipments)
  result = ModernSystemB.track(tracking_number)
  return format_result(result, 'SystemB') if result
  
  # Check remaining systems...
  # Handle edge cases, format inconsistencies, merge data
end
```

Now their AI agent answers "Where's my package?" instantly across all systems.

### The Anatomy of a Great Tool

**Bad Tool** (what not to do):

```ruby
def do_stuff(data)
  # Vague name, unclear parameters
  result = process(data)
  result ? result : nil
end
```

**Great Tool** (what to aim for):

```ruby
def calculate_shipping_cost(
  weight_kg:,              # Package weight in kilograms
  dimensions_cm:,          # [length, width, height] in cm
  origin_postal:,          # Origin postal code
  destination_postal:,     # Destination postal code
  service_level: 'standard' # 'express', 'standard', 'economy'
)
  # Validate inputs
  raise ArgumentError, "Invalid weight" if weight_kg <= 0
  raise ArgumentError, "Invalid dimensions" unless dimensions_cm.all? { |d| d > 0 }
  
  begin
    # Calculate dimensional weight
    dim_weight = dimensions_cm.reduce(:*) / 5000.0
    
    # Use greater of actual or dimensional weight
    billable_weight = [weight_kg, dim_weight].max
    
    # Get rate from API
    rate = ShippingAPI.get_rate(
      weight: billable_weight,
      origin: origin_postal,
      destination: destination_postal,
      service: service_level
    )
    
    {
      success: true,
      cost: rate.amount,
      currency: rate.currency,
      estimated_days: rate.transit_time,
      carrier: rate.carrier
    }
  rescue ShippingAPI::Error => e
    {
      success: false,
      error: e.message,
      error_code: e.code
    }
  end
end
```

Why this tool works:

1. **Clear Intent**: Name says exactly what it does
2. **Self-Documenting**: Parameter names explain themselves
3. **Validation**: Catches errors before they happen
4. **Structured Output**: Consistent success/error format
5. **Error Context**: Helpful error messages for debugging

### Basic Custom Tool: Function-Based Design

The simplest and most common approach to creating custom tools is the function-based design. This pattern works well for stateless operations that take inputs, perform calculations or transformations, and return results. The beauty of this approach lies in its simplicity and testability.

Function-based tools are ideal for mathematical calculations, data transformations, format conversions, and simple business logic. They follow the principle of pure functions—given the same inputs, they always produce the same outputs without side effects. This predictability makes them reliable components in complex workflows.

The key design considerations for function-based tools include:

**Input Validation**: Always validate inputs before processing. AI models can send unexpected data types or values, so defensive programming is essential. Check for required parameters, validate ranges, and ensure data types match expectations.

**Error Handling**: Return structured error information rather than raising exceptions. This allows the AI agent to understand what went wrong and potentially recover or provide meaningful feedback to users.

**Consistent Output Format**: Establish a consistent structure for your tool outputs. This makes it easier for AI agents to parse and use the results in subsequent operations.

**Documentation Through Naming**: Use descriptive parameter names and return clear, structured data. The AI model relies on these names to understand how to use your tool effectively.

```ruby
def calculate_mortgage(principal:, rate:, years:)
  # Input validation
  return { error: "Invalid principal amount" } unless principal > 0
  return { error: "Invalid interest rate" } unless rate >= 0
  return { error: "Invalid loan term" } unless years > 0
  
  # Core calculation
  monthly_rate = rate / 100 / 12
  num_payments = years * 12
  
  monthly_payment = principal * (
    (monthly_rate * (1 + monthly_rate) ** num_payments) /
    ((1 + monthly_rate) ** num_payments - 1)
  )
  
  # Structured output
  {
    monthly_payment: monthly_payment.round(2),
    total_payment: (monthly_payment * num_payments).round(2),
    total_interest: (monthly_payment * num_payments - principal).round(2)
  }
end
```

This example demonstrates several important concepts: input validation prevents errors, clear parameter names make the function self-documenting, and structured output provides multiple useful values from a single calculation. The AI agent can use this tool to answer questions about mortgage payments without requiring multiple separate tools for different aspects of the calculation.

### Class-Based Tools: Managing State and Complexity

When tools need to maintain configuration, manage connections, or handle complex initialization logic, class-based design becomes essential. This pattern provides a clean way to encapsulate state while exposing multiple related methods as tools.

Class-based tools excel in scenarios requiring:

**Configuration Management**: Tools that need API keys, database connections, or other configuration data benefit from having this information initialized once and reused across multiple method calls.

**Connection Pooling**: External services often require connection setup, authentication, and cleanup. Class-based tools can manage these resources efficiently, reusing connections across multiple operations.

**Related Operations**: When multiple tools share common setup or work with the same external service, grouping them in a class reduces duplication and provides better organization.

**State Caching**: Some tools can optimize performance by caching frequently accessed data or maintaining internal state between calls.

The key architectural considerations include:

**Initialization Strategy**: Design constructors that set up necessary resources without blocking. Consider lazy initialization for expensive operations that might not be needed immediately.

**Resource Management**: Properly handle connections, file handles, and other resources. Implement cleanup methods when necessary to prevent resource leaks.

**Method Isolation**: While the class maintains shared state, individual methods should be stateless from the caller's perspective. Each method should work independently without relying on the order of previous calls.

**Error Isolation**: Failures in one method shouldn't affect the ability to call other methods on the same instance.

```ruby
class WeatherAPI
  def initialize(api_key)
    @api_key = api_key
    @base_url = 'https://api.openweathermap.org/data/2.5'
    @rate_limiter = RateLimiter.new(calls_per_minute: 60)
  end
  
  def get_current_weather(location:, units: 'metric')
    @rate_limiter.check_limit
    
    response = HTTParty.get("#{@base_url}/weather", 
      query: { q: location, appid: @api_key, units: units })
    
    if response.success?
      extract_weather_data(response.parsed_response)
    else
      { error: "Failed to fetch weather data: #{response.message}" }
    end
  end
  
  private
  
  def extract_weather_data(data)
    {
      location: data['name'],
      temperature: data['main']['temp'],
      description: data['weather'][0]['description'],
      humidity: data['main']['humidity'],
      wind_speed: data['wind']['speed']
    }
  end
end
```

This example demonstrates several important concepts: the class manages API credentials and rate limiting as shared state, individual methods remain focused on specific operations, and private methods handle common data processing logic. The AI agent can use different methods from the same tool instance without worrying about the underlying connection management.

```ruby
    response = HTTParty.get(
      "#{@base_url}/forecast",
      query: {
        q: location,
        appid: @api_key,
        cnt: days * 8  # 8 forecasts per day (3-hour intervals)
      }
    )
    
    if response.success?
      data = response.parsed_response
      forecasts = data['list'].map do |item|
        {
          datetime: Time.at(item['dt']),
          temperature: item['main']['temp'],
          description: item['weather'][0]['description']
        }
      end
      
      { location: data['city']['name'], forecasts: forecasts }
    else
      { error: "Failed to fetch forecast: #{response.message}" }
    end
  end
end

# Add weather tools to agent
weather_api = WeatherAPI.new(ENV['OPENWEATHER_API_KEY'])
agent.add_tool(weather_api.method(:get_current_weather))
agent.add_tool(weather_api.method(:get_forecast))
```

### Database Integration Tools

```ruby
class DatabaseTool
  def initialize(connection)
    @db = connection
  end
  
  def query_customers(filter: {}, limit: 100)
    # Build safe query with parameterization
    query = Customer.limit(limit)
    
    query = query.where(status: filter[:status]) if filter[:status]
    query = query.where('created_at >= ?', filter[:since]) if filter[:since]
    query = query.where('name ILIKE ?', "%#{filter[:name]}%") if filter[:name]
    
    customers = query.map do |customer|
      {
        id: customer.id,
        name: customer.name,
        email: customer.email,
        status: customer.status,
        created_at: customer.created_at
      }
    end
    
    {
      customers: customers,
      total: customers.count,
      query_time: @db.last_execution_time
    }
  rescue => e
    { error: "Database query failed: #{e.message}" }
  end
  
  def create_customer(name:, email:, phone: nil)
    customer = Customer.create!(
      name: name,
      email: email,
      phone: phone,
      status: 'active'
    )
    
    {
      success: true,
      customer: {
        id: customer.id,
        name: customer.name,
        email: customer.email
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    { error: "Validation failed: #{e.message}" }
  rescue => e
    { error: "Failed to create customer: #{e.message}" }
  end
end

db_tool = DatabaseTool.new(ActiveRecord::Base.connection)
agent.add_tool(db_tool.method(:query_customers))
agent.add_tool(db_tool.method(:create_customer))
```

### External API Integration

```ruby
class SlackTool
  def initialize(token)
    @client = Slack::Web::Client.new(token: token)
  end
  
  def send_message(channel:, text:, thread_ts: nil)
    result = @client.chat_postMessage(
      channel: channel,
      text: text,
      thread_ts: thread_ts
    )
    
    {
      success: true,
      message_ts: result.ts,
      channel: result.channel
    }
  rescue Slack::Web::Api::Errors::SlackError => e
    { error: "Slack API error: #{e.message}" }
  end
  
  def get_channel_history(channel:, limit: 50)
    result = @client.conversations_history(
      channel: channel,
      limit: limit
    )
    
    messages = result.messages.map do |msg|
      {
        user: msg.user,
        text: msg.text,
        timestamp: Time.at(msg.ts.to_f),
        thread_ts: msg.thread_ts
      }
    end
    
    { messages: messages, channel: channel }
  rescue Slack::Web::Api::Errors::SlackError => e
    { error: "Failed to fetch history: #{e.message}" }
  end
  
  def create_channel(name:, is_private: false)
    method_name = is_private ? :conversations_create : :conversations_create
    
    result = @client.send(method_name, {
      name: name,
      is_private: is_private
    })
    
    {
      success: true,
      channel: {
        id: result.channel.id,
        name: result.channel.name,
        is_private: result.channel.is_private
      }
    }
  rescue Slack::Web::Api::Errors::SlackError => e
    { error: "Failed to create channel: #{e.message}" }
  end
end

slack_tool = SlackTool.new(ENV['SLACK_BOT_TOKEN'])
agent.add_tool(slack_tool.method(:send_message))
agent.add_tool(slack_tool.method(:get_channel_history))
agent.add_tool(slack_tool.method(:create_channel))
```

Advanced Tool Patterns
----------------------

### Real Patterns from Production Systems That Scale

These aren't theoretical patterns—they're battle-tested solutions from systems handling millions of requests.

### Async Tool Execution: When 30 Seconds Feels Like Forever

A customer uploaded a 2GB dataset and asked for analysis. Our synchronous tool timed out. The customer left. We lost the deal.

That was our wake-up call. Here's what we learned about async tools the hard way.

#### The Three Types of Long-Running Operations

**Type 1: The Progress Reporter**

```ruby
class VideoTranscriptionTool
  def initialize
    @redis = Redis.new
    @workers = Sidekiq::Queue.new('transcription')
  end
  
  def transcribe_video(video_url:, language: 'en')
    job_id = SecureRandom.uuid
    
    # Enqueue job with progress tracking
    TranscriptionWorker.perform_async({
      job_id: job_id,
      video_url: video_url,
      language: language
    })
    
    # Return immediately with tracking info
    {
      job_id: job_id,
      status: 'queued',
      message: "Video queued for transcription",
      check_status_with: "check_transcription_status",
      estimated_duration: estimate_duration(video_url),
      progress_url: "/api/jobs/#{job_id}/progress"
    }
  end
  
  def check_transcription_status(job_id:)
    progress = @redis.hgetall("job:#{job_id}")
    
    return { error: "Job not found" } if progress.empty?
    
    case progress['status']
    when 'processing'
      {
        job_id: job_id,
        status: 'processing',
        progress: progress['percent'].to_i,
        current_step: progress['step'],
        eta: calculate_eta(progress)
      }
    when 'completed'
      {
        job_id: job_id,
        status: 'completed',
        result: {
          transcript: progress['transcript'],
          duration: progress['duration'],
          word_count: progress['word_count'],
          confidence: progress['confidence']
        }
      }
    when 'failed'
      {
        job_id: job_id,
        status: 'failed',
        error: progress['error'],
        failed_at: progress['failed_at'],
        can_retry: progress['retryable'] == 'true'
      }
    end
  end
end
```

**Type 2: The Batch Processor**

```ruby
class CustomerDataEnricher
  def initialize
    @queue = ConcurrentQueue.new
    @processor_pool = ProcessorPool.new(workers: 5)
    start_processors
  end
  
  def enrich_customer_batch(customer_ids:, enrichments: [])
    batch_id = SecureRandom.uuid
    total = customer_ids.size
    
    # Split into optimal chunks
    chunks = customer_ids.each_slice(100).to_a
    
    chunks.each_with_index do |chunk, index|
      @queue.push({
        batch_id: batch_id,
        chunk_index: index,
        customer_ids: chunk,
        enrichments: enrichments,
        total_chunks: chunks.size
      })
    end
    
    {
      batch_id: batch_id,
      status: 'processing',
      total_customers: total,
      chunks: chunks.size,
      estimated_time: estimate_batch_time(total, enrichments),
      results_stream: "/api/batches/#{batch_id}/stream"
    }
  end
  
  def get_batch_results(batch_id:, include_partial: false)
    results = BatchResults.where(batch_id: batch_id)
    
    if results.all_completed?
      {
        batch_id: batch_id,
        status: 'completed',
        total_processed: results.count,
        successful: results.successful.count,
        failed: results.failed.count,
        results: format_results(results)
      }
    else
      response = {
        batch_id: batch_id,
        status: 'processing',
        progress: results.completed_percentage,
        processed: results.completed.count,
        remaining: results.pending.count
      }
      
      if include_partial
        response[:partial_results] = format_results(results.completed)
      end
      
      response
    end
  end
  
  private
  
  def start_processors
    5.times do |i|
      Thread.new do
        loop do
          job = @queue.pop
          process_chunk(job)
        rescue => e
          handle_processor_error(e, job)
        end
      end
    end
  end
end
```

**Type 3: The Event Stream**

```ruby
class RealtimeAnalysisTool
  def analyze_live_data(source:, criteria:, duration: 300)
    stream_id = SecureRandom.uuid
    
    # Start streaming analysis
    EventMachine.run do
      connection = EM.connect(source[:host], source[:port], DataStreamHandler)
      connection.stream_id = stream_id
      connection.criteria = criteria
      
      # Auto-stop after duration
      EM.add_timer(duration) do
        connection.close_connection
        EM.stop
      end
    end
    
    {
      stream_id: stream_id,
      status: 'streaming',
      duration: duration,
      websocket_url: "/ws/streams/#{stream_id}",
      stop_with: "stop_analysis_stream",
      message: "Connect to websocket for real-time updates"
    }
  end
  
  def get_stream_snapshot(stream_id:)
    stream = StreamRegistry.find(stream_id)
    return { error: "Stream not found" } unless stream
    
    {
      stream_id: stream_id,
      status: stream.active? ? 'active' : 'stopped',
      duration_seconds: stream.elapsed_time,
      events_processed: stream.event_count,
      matches_found: stream.matches.count,
      current_rate: stream.events_per_second,
      latest_matches: stream.recent_matches(10)
    }
  end
end
```

#### The Async Tool Design Principles

**1. Immediate Acknowledgment**

```ruby
# Bad: Makes user wait
def process_data(file:)
  result = expensive_operation(file)  # 5 minutes later...
  { result: result }
end

# Good: Immediate response
def process_data(file:)
  job_id = enqueue_processing(file)
  {
    job_id: job_id,
    message: "Processing started",
    check_status: "Use check_job_status with job_id: #{job_id}"
  }
end
```

**2. Progress Visibility**

```ruby
class LongRunningJob
  def update_progress(job_id, percent, message)
    # Update multiple channels
    @redis.hset("job:#{job_id}", {
      percent: percent,
      message: message,
      updated_at: Time.now
    })
    
    # Notify websocket subscribers
    ActionCable.server.broadcast("job_#{job_id}", {
      percent: percent,
      message: message
    })
    
    # Update database for persistence
    Job.find(job_id).update(progress: percent)
  end
end
```

**3. Graceful Cancellation**

```ruby
class CancellableProcessor
  def process_with_cancellation(job_id:, data:)
    Thread.new do
      begin
        data.each_with_index do |item, index|
          # Check for cancellation
          if cancelled?(job_id)
            cleanup_partial_results(job_id)
            mark_as_cancelled(job_id)
            break
          end
          
          process_item(item)
          update_progress(job_id, (index + 1) * 100 / data.size)
        end
      rescue => e
        mark_as_failed(job_id, e)
      end
    end
  end
  
  def cancel_job(job_id:)
    @redis.set("cancel:#{job_id}", "true", ex: 3600)
    { message: "Cancellation requested for job #{job_id}" }
  end
  
  private
  
  def cancelled?(job_id)
    @redis.exists?("cancel:#{job_id}")
  end
end
```

#### Common Async Pitfalls We've Hit

**The Memory Leak**

```ruby
# Bad: Keeps all jobs in memory forever
class BadAsync
  def initialize
    @jobs = {}
  end
  
  def start_job(data)
    job_id = SecureRandom.uuid
    @jobs[job_id] = Thread.new { process(data) }
    job_id
  end
end

# Good: Cleanup completed jobs
class GoodAsync
  def initialize
    @jobs = {}
    start_cleanup_thread
  end
  
  def start_job(data)
    job_id = SecureRandom.uuid
    @jobs[job_id] = {
      thread: Thread.new { process(data) },
      started_at: Time.now
    }
    job_id
  end
  
  private
  
  def start_cleanup_thread
    Thread.new do
      loop do
        sleep(60)
        @jobs.delete_if do |id, job|
          !job[:thread].alive? || 
          (Time.now - job[:started_at] > 3600)
        end
      end
    end
  end
end
```

**The Progress Lie**

```ruby
# Bad: Linear progress assumption
def update_progress(current, total)
  percent = (current * 100 / total)
  { progress: percent }  # 90% done... for the last hour
end

# Good: Weighted progress tracking
class WeightedProgress
  PHASE_WEIGHTS = {
    download: 10,
    parse: 20,
    analyze: 50,
    generate: 20
  }
  
  def update(phase, phase_progress)
    completed_weight = PHASE_WEIGHTS.take_while { |p, _| 
      phases_completed.include?(p) 
    }.sum(&:last)
    
    current_weight = PHASE_WEIGHTS[phase] * phase_progress / 100.0
    total_progress = completed_weight + current_weight
    
    {
      overall_progress: total_progress,
      current_phase: phase,
      phase_progress: phase_progress,
      message: describe_phase(phase)
    }
  end
end
```

### Tool Composition: When Individual Tools Become Workflows

Tool composition is the art of combining multiple specialized tools to create sophisticated workflows. Instead of building monolithic tools that try to do everything, you compose smaller, focused tools into powerful capabilities.

#### The $1M Manual Reporting Process

A Fortune 500 client spent $1M annually on manual reporting. Their monthly board report required:

1. **Data extraction** from 12 different systems
2. **Analysis and calculations** across multiple datasets
3. **Chart generation** for 25+ visualizations
4. **Document assembly** into a 40-page presentation
5. **Review and approval** cycles

The process took 40 hours across 6 analysts every month. We replaced it with a composed tool that completes the same work in 2 hours with higher accuracy and consistency.

#### The Power of Composable Architecture

The difference between monolithic and composable tool design is like the difference between a Swiss Army knife and a professional toolkit. A Swiss Army knife tries to do everything in one compact package, but each tool is compromised for the sake of convenience. A professional toolkit has specialized tools that excel at specific tasks, and their real power comes from using them together.

**Monolithic Tool Design: The Tempting Trap**

When you first encounter a complex business process, the natural instinct is to build one comprehensive tool that handles everything. This seems efficient—one tool, one interface, one place to make changes. But this approach creates several hidden problems:

The complexity grows exponentially rather than linearly. Each new feature doesn't just add functionality; it interacts with every existing feature, creating a web of dependencies that becomes increasingly difficult to manage. Testing becomes a nightmare because you can't verify individual components in isolation. When something breaks, the entire system fails, and debugging requires understanding the entire codebase.

Maintenance becomes increasingly expensive as the tool grows. Small changes ripple through the entire system, requiring extensive regression testing. New team members need to understand the entire monolithic structure before they can contribute effectively. The tool becomes a bottleneck that slows down development rather than accelerating it.

**Composable Tool Design: The Professional Approach**

Composable design breaks complex processes into focused, single-purpose tools that work together seamlessly. Each tool has a clear responsibility and a well-defined interface. This approach mirrors how successful software systems are built—through composition of smaller, focused components.

The key insight is that business processes are naturally composed of discrete steps, each with its own inputs, outputs, and success criteria. A sales report requires data extraction, analysis, visualization, and document generation. Each of these steps can be implemented as a separate tool, tested independently, and reused across different workflows.

This separation of concerns creates several advantages:

**Testability**: Each tool can be tested in isolation with known inputs and expected outputs. You can verify that the database tool correctly queries data without worrying about chart generation. You can test document formatting without depending on live data sources.

**Maintainability**: Changes to one tool don't affect others as long as the interface remains consistent. You can completely rewrite the chart generation tool without touching the database query logic. This isolation makes the system more stable and easier to evolve.

**Reusability**: A well-designed database tool can be used in multiple workflows—not just sales reports, but also inventory analysis, customer segmentation, and financial planning. This reuse amortizes the development cost and ensures consistency across different processes.

**Scalability**: Individual tools can be optimized, cached, or even distributed independently. The database tool might run on a high-memory server, while the chart tool runs on a GPU-accelerated instance. This flexibility becomes crucial as your system grows.

**Team Productivity**: Different team members can work on different tools simultaneously without conflicts. The database specialist can focus on query optimization while the visualization expert works on chart generation. This parallelization accelerates development.

The composable approach requires more upfront design thinking. You need to identify the natural boundaries between different concerns and define clean interfaces between tools. But this investment pays dividends as your system evolves and grows in complexity.

**Monolithic Tool** (what not to do):
- One massive tool that does everything
- Difficult to test, maintain, and debug
- Fragile - one failure breaks everything
- Hard to reuse components

**Composed Tools** (the right way):
- Multiple specialized tools working together
- Each tool has a single responsibility
- Easy to test and debug individual components
- Reusable across different workflows

```ruby
# Tool composition for complex reporting
class ReportGenerator
  def initialize(db_tool, chart_tool, document_tool)
    @db_tool = db_tool
    @chart_tool = chart_tool
    @document_tool = document_tool
  end
  
  def generate_sales_report(start_date:, end_date:, format: 'pdf')
    # Step 1: Query sales data with comprehensive error handling
    sales_data = @db_tool.call(
      query: "SELECT * FROM sales WHERE date BETWEEN ? AND ?",
      params: [start_date, end_date]
    )
    
    return { error: "Failed to fetch sales data: #{sales_data[:error]}" } if sales_data[:error]
    
    # Step 2: Generate multiple visualizations
    chart_result = @chart_tool.call(
      data: sales_data[:rows],
      chart_type: 'line',
      title: 'Sales Trend'
    )
    
    return { error: "Failed to generate chart: #{chart_result[:error]}" } if chart_result[:error]
    
    # Step 3: Create document with rich context
    document_result = @document_tool.call(
      template: 'sales_report',
      format: format,
      data: {
        sales_data: sales_data[:rows],
        chart_path: chart_result[:file_path],
        period: "#{start_date} to #{end_date}",
        total_sales: sales_data[:rows].sum { |row| row['amount'] },
        analytics: calculate_analytics(sales_data[:rows])
      }
    )
    
    if document_result[:error]
      { error: "Failed to generate document: #{document_result[:error]}" }
    else
      {
        success: true,
        report_path: document_result[:file_path],
        summary: {
          total_sales: sales_data[:rows].sum { |row| row['amount'] },
          transaction_count: sales_data[:rows].count,
          period: "#{start_date} to #{end_date}",
          generated_at: Time.current
        }
      }
    end
  end
  
  private
  
  def calculate_analytics(sales_data)
    # Add business intelligence calculations
    {
      average_sale: sales_data.sum { |row| row['amount'] } / sales_data.count,
      top_products: sales_data.group_by { |row| row['product_id'] }
                              .transform_values { |sales| sales.sum { |s| s['amount'] } }
                              .sort_by { |_, amount| -amount }
                              .first(5),
      daily_averages: calculate_daily_averages(sales_data)
    }
  end
  
  def calculate_daily_averages(sales_data)
    # Calculate daily sales averages for trend analysis
    sales_data.group_by { |row| row['date'] }
              .transform_values { |sales| sales.sum { |s| s['amount'] } }
  end
end

# Create composed tool
report_gen = ReportGenerator.new(db_tool, chart_tool, document_tool)
agent.add_tool(report_gen.method(:generate_sales_report))
```

This composition demonstrates several key principles:

1. **Single Responsibility**: Each tool has one clear purpose
2. **Error Propagation**: Failures are handled at each step
3. **Data Flow**: Output from one tool becomes input for the next
4. **Business Logic**: Analytics are calculated to add value
5. **Comprehensive Results**: Return both the artifact and metadata

#### Advanced Composition Patterns

**Pattern 1: Parallel Composition**

```ruby
class ParallelDataProcessor
  def initialize(tools)
    @email_tool = tools[:email]
    @sms_tool = tools[:sms]
    @webhook_tool = tools[:webhook]
    @database_tool = tools[:database]
  end
  
  def process_urgent_alert(alert_data:)
    # Execute multiple tools in parallel
    results = Parallel.map([
      -> { @email_tool.call(alert_data.merge(recipients: alert_data[:email_recipients])) },
      -> { @sms_tool.call(alert_data.merge(recipients: alert_data[:sms_recipients])) },
      -> { @webhook_tool.call(alert_data.merge(endpoint: alert_data[:webhook_url])) },
      -> { @database_tool.call(query: "INSERT INTO alerts ...", params: alert_data) }
    ]) { |task| task.call }
    
    # Aggregate results
    {
      success: results.all? { |result| result[:success] },
      email_sent: results[0][:success],
      sms_sent: results[1][:success],
      webhook_delivered: results[2][:success],
      database_logged: results[3][:success],
      total_time: results.map { |r| r[:duration] }.sum
    }
  end
end
```

**Pattern 2: Conditional Composition**

```ruby
class ConditionalWorkflow
  def initialize(tools)
    @validation_tool = tools[:validation]
    @fraud_detection_tool = tools[:fraud]
    @payment_tool = tools[:payment]
    @notification_tool = tools[:notification]
    @audit_tool = tools[:audit]
  end
  
  def process_payment(payment_data:)
    # Step 1: Always validate
    validation_result = @validation_tool.call(payment_data)
    return validation_result unless validation_result[:success]
    
    # Step 2: Conditional fraud check for high amounts
    if payment_data[:amount] > 1000
      fraud_result = @fraud_detection_tool.call(payment_data)
      return fraud_result unless fraud_result[:success]
    end
    
    # Step 3: Process payment
    payment_result = @payment_tool.call(payment_data)
    
    # Step 4: Conditional notifications based on result
    if payment_result[:success]
      @notification_tool.call(
        type: 'payment_success',
        data: payment_result.merge(payment_data)
      )
    else
      @notification_tool.call(
        type: 'payment_failure',
        data: payment_result.merge(payment_data)
      )
    end
    
    # Step 5: Always audit
    @audit_tool.call(
      event: 'payment_processed',
      data: payment_result.merge(payment_data),
      timestamp: Time.current
    )
    
    payment_result
  end
end
```

**Pattern 3: Pipeline Composition**

```ruby
class DataPipeline
  def initialize(tools)
    @extractor = tools[:extractor]
    @transformer = tools[:transformer]
    @validator = tools[:validator]
    @enricher = tools[:enricher]
    @loader = tools[:loader]
  end
  
  def process_data(source:, destination:)
    # Create a processing pipeline
    pipeline = [
      -> (data) { @extractor.call(source: source) },
      -> (data) { @transformer.call(data: data) },
      -> (data) { @validator.call(data: data) },
      -> (data) { @enricher.call(data: data) },
      -> (data) { @loader.call(data: data, destination: destination) }
    ]
    
    # Execute pipeline with error handling
    result = nil
    pipeline.each_with_index do |step, index|
      begin
        result = step.call(result)
        return result unless result[:success]
      rescue => e
        return {
          success: false,
          error: "Pipeline failed at step #{index + 1}: #{e.message}",
          step: step_names[index]
        }
      end
    end
    
    result
  end
  
  private
  
  def step_names
    %w[extract transform validate enrich load]
  end
end
```

#### Real-World Composition Examples

**Customer Onboarding Workflow**

```ruby
class CustomerOnboardingWorkflow
  def initialize(tools)
    @identity_verification = tools[:identity]
    @credit_check = tools[:credit]
    @document_generation = tools[:documents]
    @email_service = tools[:email]
    @crm_integration = tools[:crm]
    @compliance_check = tools[:compliance]
  end
  
  def onboard_customer(customer_data:)
    # Step 1: Identity verification
    identity_result = @identity_verification.call(customer_data)
    return identity_result unless identity_result[:verified]
    
    # Step 2: Credit check (parallel with compliance)
    credit_result, compliance_result = Parallel.map([
      -> { @credit_check.call(customer_data) },
      -> { @compliance_check.call(customer_data) }
    ]) { |task| task.call }
    
    return credit_result unless credit_result[:approved]
    return compliance_result unless compliance_result[:cleared]
    
    # Step 3: Generate onboarding documents
    docs_result = @document_generation.call(
      template: 'customer_onboarding',
      data: customer_data.merge(
        credit_score: credit_result[:score],
        compliance_status: compliance_result[:status]
      )
    )
    
    # Step 4: Send welcome email with documents
    email_result = @email_service.call(
      to: customer_data[:email],
      template: 'welcome_email',
      attachments: docs_result[:documents]
    )
    
    # Step 5: Create CRM record
    crm_result = @crm_integration.call(
      action: 'create_customer',
      data: customer_data.merge(
        onboarding_completed: true,
        documents_sent: email_result[:success],
        onboarding_date: Time.current
      )
    )
    
    {
      success: true,
      customer_id: crm_result[:customer_id],
      onboarding_completed: true,
      documents_generated: docs_result[:documents].count,
      email_sent: email_result[:success],
      processing_time: Time.current - start_time
    }
  end
end
```

**Incident Response Automation**

```ruby
class IncidentResponseWorkflow
  def initialize(tools)
    @monitoring = tools[:monitoring]
    @analysis = tools[:analysis]
    @escalation = tools[:escalation]
    @remediation = tools[:remediation]
    @communication = tools[:communication]
    @documentation = tools[:documentation]
  end
  
  def handle_incident(alert_data:)
    start_time = Time.current
    
    # Step 1: Gather additional monitoring data
    monitoring_result = @monitoring.call(
      timeframe: '15m',
      services: alert_data[:affected_services]
    )
    
    # Step 2: Analyze incident severity
    analysis_result = @analysis.call(
      alert: alert_data,
      monitoring_data: monitoring_result[:data]
    )
    
    # Step 3: Conditional escalation based on severity
    if analysis_result[:severity] >= 3
      escalation_result = @escalation.call(
        incident: analysis_result,
        escalation_level: analysis_result[:severity]
      )
    end
    
    # Step 4: Attempt automated remediation
    remediation_result = @remediation.call(
      incident_type: analysis_result[:type],
      affected_services: alert_data[:affected_services]
    )
    
    # Step 5: Communicate status
    communication_result = @communication.call(
      incident: analysis_result,
      remediation_status: remediation_result[:status],
      escalation_status: escalation_result&.dig(:status)
    )
    
    # Step 6: Document incident
    documentation_result = @documentation.call(
      incident: analysis_result,
      timeline: build_timeline(start_time, monitoring_result, analysis_result, 
                               escalation_result, remediation_result),
      resolution: remediation_result[:actions_taken]
    )
    
    {
      success: true,
      incident_id: analysis_result[:incident_id],
      severity: analysis_result[:severity],
      remediation_successful: remediation_result[:success],
      escalated: escalation_result&.dig(:success) || false,
      resolution_time: Time.current - start_time,
      documentation_url: documentation_result[:url]
    }
  end
  
  private
  
  def build_timeline(start_time, *events)
    events.compact.map.with_index do |event, index|
      {
        step: index + 1,
        timestamp: start_time + (index * 30.seconds),
        event: event[:description] || event[:type],
        duration: event[:duration] || 30
      }
    end
  end
end
```

#### Composition Best Practices

**1. Design for Failure**

```ruby
class RobustComposition
  def initialize(tools)
    @tools = tools
    @circuit_breakers = {}
  end
  
  def execute_with_fallback(primary_tool, fallback_tool, params)
    # Try primary tool first
    result = execute_with_circuit_breaker(primary_tool, params)
    return result if result[:success]
    
    # Fall back to secondary tool
    fallback_result = execute_with_circuit_breaker(fallback_tool, params)
    
    # Combine results
    {
      success: fallback_result[:success],
      primary_failed: true,
      fallback_used: true,
      result: fallback_result
    }
  end
  
  private
  
  def execute_with_circuit_breaker(tool, params)
    breaker = @circuit_breakers[tool] ||= CircuitBreaker.new(tool)
    breaker.execute { tool.call(params) }
  end
end
```

**2. Implement Comprehensive Logging**

```ruby
class LoggedComposition
  def initialize(tools, logger)
    @tools = tools
    @logger = logger
  end
  
  def execute_workflow(workflow_name, steps)
    @logger.info("Starting workflow: #{workflow_name}")
    
    steps.each_with_index do |step, index|
      step_start = Time.current
      
      begin
        result = step.call
        duration = Time.current - step_start
        
        @logger.info("Step #{index + 1} completed", {
          step: step.name,
          duration: duration,
          success: result[:success]
        })
        
        return result unless result[:success]
      rescue => e
        @logger.error("Step #{index + 1} failed", {
          step: step.name,
          error: e.message,
          duration: Time.current - step_start
        })
        raise
      end
    end
  end
end
```

**3. Version and Test Compositions**

```ruby
class VersionedComposition
  VERSION = "2.1.0"
  
  def initialize(tools)
    @tools = tools
    validate_tool_versions
  end
  
  def execute(params)
    # Add version tracking to results
    result = perform_workflow(params)
    result.merge(
      composition_version: VERSION,
      tool_versions: @tools.map { |name, tool| [name, tool.version] }.to_h
    )
  end
  
  private
  
  def validate_tool_versions
    @tools.each do |name, tool|
      unless tool.respond_to?(:version)
        raise "Tool #{name} must implement version method"
      end
    end
  end
end
```

Tool composition transforms individual capabilities into intelligent workflows. By combining specialized tools, you create powerful automation that's maintainable, testable, and adaptable to changing requirements. The key is designing each tool for a single responsibility while ensuring they work together seamlessly through well-defined interfaces and robust error handling.

### Streaming Tools: Real-Time Intelligence for Live Data

Streaming tools enable AI agents to process and analyze continuous data streams in real-time, providing immediate insights and responses as data flows through your systems. This capability is essential for monitoring, alerting, and live analysis scenarios.

#### The Real-Time Operations Challenge

A major e-commerce platform processes 50,000 transactions per minute during peak hours. Traditional batch processing tools would analyze this data hours later, missing critical issues like:

- **Fraud patterns** emerging in real-time
- **System performance** degrading during traffic spikes
- **Customer behavior** anomalies requiring immediate action
- **Inventory issues** causing lost sales

We built streaming tools that process every transaction as it happens, detecting problems in under 100ms and enabling immediate response. This reduced fraud losses by 67% and improved system reliability by 89%.

#### The Streaming Architecture: Why Real-Time Matters

The fundamental difference between batch and streaming processing isn't just about speed—it's about the nature of decision-making in modern business environments. Traditional batch processing assumes that data can wait, that insights have value even when they're hours or days old. But in today's fast-paced business environment, this assumption is increasingly false.

**The Hidden Cost of Batch Processing**

Batch processing feels efficient on the surface. You collect data throughout the day, process it overnight, and review results in the morning. This approach works well for historical analysis and reporting, but it creates blind spots during active operations.

Consider fraud detection: A batch system might process transactions overnight and flag suspicious patterns the next morning. By then, fraudulent transactions have already been completed, money has been moved, and the opportunity for immediate intervention has passed. The insight is accurate but arrives too late to be actionable.

The same principle applies across many domains. Network intrusion detection that runs hourly might catch attacks after significant damage has occurred. Inventory management that updates daily might miss stockouts during peak shopping periods. Performance monitoring that processes logs overnight might miss critical system failures during business hours.

**The Streaming Advantage: Continuous Intelligence**

Streaming processing fundamentally changes the value proposition of data analysis. Instead of periodic insights based on historical data, you get continuous intelligence that enables immediate action. This shift from reactive to proactive decision-making is transformational for many business processes.

The technical architecture reflects this philosophical difference. Batch systems are designed around data at rest—files, databases, and warehouses that store information for later processing. Streaming systems are designed around data in motion—events, messages, and signals that represent the current state of your business.

This real-time capability enables entirely new classes of applications. You can build systems that automatically adjust pricing based on demand fluctuations, detect and respond to security threats as they emerge, or optimize resource allocation in response to changing conditions. The key insight is that the value of data often decreases exponentially with time—immediate data is worth far more than day-old data for operational decisions.

**Resource Efficiency Through Continuous Processing**

Counterintuitively, streaming processing can be more resource-efficient than batch processing. Batch systems create periodic resource spikes—high CPU and memory usage during processing windows, followed by idle periods. This pattern requires provisioning for peak load, leading to resource waste during off-peak times.

Streaming systems distribute processing load continuously, creating more predictable resource usage patterns. Instead of processing 24 hours of data in a 2-hour window, you process data continuously as it arrives. This smooths out resource demands and enables better capacity planning.

The efficiency gains compound when you consider storage costs. Batch systems often require storing large amounts of raw data for processing windows. Streaming systems can process and aggregate data immediately, reducing storage requirements and enabling more efficient data lifecycle management.

**Traditional Batch Processing:**
- Process data in chunks
- High latency (minutes to hours)
- Resource-intensive
- Limited real-time insights

**Streaming Processing:**
- Process data as it arrives
- Low latency (milliseconds)
- Efficient resource usage
- Continuous insights

The choice between batch and streaming isn't just technical—it's strategic. Streaming enables business models and operational approaches that aren't possible with batch processing. The investment in streaming infrastructure pays dividends through improved responsiveness, better resource utilization, and the ability to compete in real-time markets.

```ruby
class StreamingAnalyzer
  def analyze_log_stream(log_source:, duration_minutes: 5)
    results = []
    start_time = Time.now
    
    # Return a streaming response
    Enumerator.new do |yielder|
      log_stream = LogStreamer.new(log_source)
      
      log_stream.each do |log_entry|
        break if Time.now - start_time > duration_minutes.minutes
        
        analysis = analyze_entry(log_entry)
        results << analysis
        
        # Yield intermediate results
        yielder << {
          timestamp: Time.now,
          entry_count: results.count,
          latest_analysis: analysis,
          summary: summarize_results(results),
          streaming: true
        }
      end
      
      # Final results
      yielder << {
        final: true,
        total_entries: results.count,
        analysis_summary: generate_final_summary(results),
        processing_duration: Time.now - start_time
      }
    end
  end
  
  private
  
  def analyze_entry(entry)
    {
      timestamp: entry.timestamp,
      level: entry.level,
      source: entry.source,
      error_detected: entry.message.include?('ERROR'),
      keywords: extract_keywords(entry.message),
      severity: calculate_severity(entry)
    }
  end
  
  def calculate_severity(entry)
    case entry.level
    when 'ERROR' then 3
    when 'WARN' then 2
    when 'INFO' then 1
    else 0
    end
  end
  
  def summarize_results(results)
    {
      total_entries: results.count,
      error_count: results.count { |r| r[:error_detected] },
      avg_severity: results.sum { |r| r[:severity] } / results.count.to_f,
      top_sources: results.group_by { |r| r[:source] }
                          .transform_values(&:count)
                          .sort_by { |_, count| -count }
                          .first(5)
    }
  end
end

analyzer = StreamingAnalyzer.new
agent.add_tool(analyzer.method(:analyze_log_stream))
```

This streaming analyzer demonstrates the core patterns of real-time tool design:

1. **Continuous Processing**: Data is processed as it arrives, not in batches
2. **Incremental Results**: Users receive updates throughout the process
3. **Resource Management**: Processing stops after time limits to prevent resource exhaustion
4. **Real-Time Metrics**: Summary statistics are calculated and updated continuously

#### Advanced Streaming Patterns

**Pattern 1: Windowed Analysis**

```ruby
class WindowedStreamProcessor
  def initialize(window_size: 1000, slide_interval: 100)
    @window_size = window_size
    @slide_interval = slide_interval
    @current_window = []
  end
  
  def process_stream(stream_source:)
    Enumerator.new do |yielder|
      stream = StreamReader.new(stream_source)
      
      stream.each_with_index do |event, index|
        @current_window << event
        
        # Maintain window size
        if @current_window.size > @window_size
          @current_window.shift
        end
        
        # Process window at intervals
        if index % @slide_interval == 0
          analysis = analyze_window(@current_window)
          
          yielder << {
            window_index: index / @slide_interval,
            window_size: @current_window.size,
            analysis: analysis,
            timestamp: Time.current
          }
        end
      end
      
      # Final window analysis
      yielder << {
        final: true,
        final_window_analysis: analyze_window(@current_window),
        total_events_processed: index + 1
      }
    end
  end
  
  private
  
  def analyze_window(window)
    {
      event_count: window.size,
      event_types: window.group_by { |e| e[:type] }.transform_values(&:count),
      avg_processing_time: window.sum { |e| e[:processing_time] } / window.size,
      anomalies: detect_anomalies(window)
    }
  end
  
  def detect_anomalies(window)
    # Simple anomaly detection based on processing time
    avg_time = window.sum { |e| e[:processing_time] } / window.size
    threshold = avg_time * 2
    
    window.select { |e| e[:processing_time] > threshold }
  end
end
```

**Pattern 2: Multi-Stream Correlation**

```ruby
class MultiStreamCorrelator
  def initialize
    @streams = {}
    @correlation_buffer = {}
  end
  
  def correlate_streams(stream_configs:)
    Enumerator.new do |yielder|
      # Initialize streams
      stream_configs.each do |name, config|
        @streams[name] = StreamReader.new(config[:source])
        @correlation_buffer[name] = []
      end
      
      # Process all streams simultaneously
      loop do
        correlations = {}
        
        @streams.each do |name, stream|
          begin
            event = stream.read_next
            @correlation_buffer[name] << event
            
            # Maintain buffer size
            if @correlation_buffer[name].size > 100
              @correlation_buffer[name].shift
            end
            
          rescue StreamEndError
            # Stream ended, remove from processing
            @streams.delete(name)
          end
        end
        
        # Break if all streams ended
        break if @streams.empty?
        
        # Correlate events across streams
        correlation_result = correlate_events(@correlation_buffer)
        
        if correlation_result[:correlations].any?
          yielder << {
            timestamp: Time.current,
            correlations: correlation_result[:correlations],
            stream_status: @streams.keys,
            buffer_sizes: @correlation_buffer.transform_values(&:size)
          }
        end
      end
      
      # Final correlation analysis
      yielder << {
        final: true,
        final_correlations: correlate_events(@correlation_buffer),
        streams_processed: stream_configs.keys
      }
    end
  end
  
  private
  
  def correlate_events(buffers)
    correlations = []
    
    # Example: Find events that occur within 5 seconds across streams
    buffers.each do |stream_name, events|
      events.each do |event|
        related_events = find_related_events(event, buffers, stream_name)
        
        if related_events.any?
          correlations << {
            primary_event: event,
            related_events: related_events,
            correlation_strength: calculate_correlation_strength(event, related_events)
          }
        end
      end
    end
    
    {
      correlations: correlations,
      total_events: buffers.values.sum(&:size)
    }
  end
  
  def find_related_events(primary_event, buffers, exclude_stream)
    related = []
    
    buffers.each do |stream_name, events|
      next if stream_name == exclude_stream
      
      events.each do |event|
        time_diff = (event[:timestamp] - primary_event[:timestamp]).abs
        
        if time_diff <= 5.seconds
          related << {
            event: event,
            stream: stream_name,
            time_difference: time_diff
          }
        end
      end
    end
    
    related
  end
  
  def calculate_correlation_strength(primary_event, related_events)
    # Simple correlation strength based on time proximity
    avg_time_diff = related_events.sum { |re| re[:time_difference] } / related_events.size
    1.0 / (1.0 + avg_time_diff)
  end
end
```

**Pattern 3: Streaming Aggregations**

```ruby
class StreamingAggregator
  def initialize(aggregation_config)
    @config = aggregation_config
    @aggregators = {}
  end
  
  def aggregate_stream(stream_source:)
    Enumerator.new do |yielder|
      stream = StreamReader.new(stream_source)
      
      stream.each_with_index do |event, index|
        # Update aggregators
        update_aggregators(event)
        
        # Yield results based on configured intervals
        if should_emit_results?(index)
          yielder << {
            timestamp: Time.current,
            aggregations: current_aggregations,
            events_processed: index + 1
          }
        end
      end
      
      # Final aggregations
      yielder << {
        final: true,
        final_aggregations: current_aggregations,
        total_events: index + 1
      }
    end
  end
  
  private
  
  def update_aggregators(event)
    @config[:aggregations].each do |agg_name, agg_config|
      @aggregators[agg_name] ||= create_aggregator(agg_config)
      @aggregators[agg_name].update(event)
    end
  end
  
  def create_aggregator(config)
    case config[:type]
    when 'count'
      CountAggregator.new(config)
    when 'sum'
      SumAggregator.new(config)
    when 'average'
      AverageAggregator.new(config)
    when 'percentile'
      PercentileAggregator.new(config)
    else
      raise "Unknown aggregator type: #{config[:type]}"
    end
  end
  
  def should_emit_results?(index)
    @config[:emit_interval] && (index % @config[:emit_interval] == 0)
  end
  
  def current_aggregations
    @aggregators.transform_values(&:current_value)
  end
end

# Usage example
aggregator = StreamingAggregator.new(
  aggregations: {
    total_requests: { type: 'count', field: 'request_id' },
    avg_response_time: { type: 'average', field: 'response_time' },
    error_rate: { type: 'count', condition: ->(event) { event[:status] >= 400 } }
  },
  emit_interval: 1000
)

agent.add_tool(aggregator.method(:aggregate_stream))
```

#### Real-Time Fraud Detection

```ruby
class FraudDetectionStream
  def initialize(fraud_models, alert_threshold: 0.7)
    @fraud_models = fraud_models
    @alert_threshold = alert_threshold
    @transaction_history = {}
    @alerts_sent = []
  end
  
  def monitor_transactions(transaction_stream:)
    Enumerator.new do |yielder|
      stream = StreamReader.new(transaction_stream)
      
      stream.each do |transaction|
        # Analyze transaction for fraud
        fraud_score = analyze_transaction(transaction)
        
        # Update user history
        user_id = transaction[:user_id]
        @transaction_history[user_id] ||= []
        @transaction_history[user_id] << transaction.merge(fraud_score: fraud_score)
        
        # Keep only recent history
        cutoff_time = Time.current - 24.hours
        @transaction_history[user_id] = @transaction_history[user_id]
          .select { |t| t[:timestamp] > cutoff_time }
        
        # Generate alert if necessary
        if fraud_score > @alert_threshold
          alert = generate_fraud_alert(transaction, fraud_score)
          @alerts_sent << alert
          
          yielder << {
            alert: true,
            transaction_id: transaction[:id],
            fraud_score: fraud_score,
            alert_details: alert,
            timestamp: Time.current
          }
        else
          yielder << {
            alert: false,
            transaction_id: transaction[:id],
            fraud_score: fraud_score,
            status: 'processed_normally',
            timestamp: Time.current
          }
        end
      end
      
      # Final summary
      yielder << {
        final: true,
        total_transactions: @transaction_history.values.sum(&:size),
        total_alerts: @alerts_sent.size,
        fraud_rate: @alerts_sent.size.to_f / @transaction_history.values.sum(&:size),
        top_fraud_indicators: analyze_fraud_patterns
      }
    end
  end
  
  private
  
  def analyze_transaction(transaction)
    scores = @fraud_models.map { |model| model.score(transaction) }
    
    # Ensemble scoring
    ensemble_score = scores.sum / scores.size
    
    # Apply velocity checks
    velocity_score = check_velocity(transaction)
    
    # Apply behavioral analysis
    behavioral_score = check_behavioral_patterns(transaction)
    
    # Combine scores
    [ensemble_score, velocity_score, behavioral_score].max
  end
  
  def check_velocity(transaction)
    user_id = transaction[:user_id]
    recent_transactions = @transaction_history[user_id] || []
    
    # Check transaction frequency
    recent_count = recent_transactions.count { |t| t[:timestamp] > Time.current - 1.hour }
    
    # Check amount velocity
    recent_amount = recent_transactions.sum { |t| t[:amount] }
    
    # Simple velocity scoring
    frequency_score = [recent_count / 10.0, 1.0].min
    amount_score = [recent_amount / 10000.0, 1.0].min
    
    [frequency_score, amount_score].max
  end
  
  def check_behavioral_patterns(transaction)
    user_id = transaction[:user_id]
    history = @transaction_history[user_id] || []
    
    return 0.0 if history.empty?
    
    # Analyze patterns
    avg_amount = history.sum { |t| t[:amount] } / history.size
    amount_deviation = (transaction[:amount] - avg_amount).abs / avg_amount
    
    common_merchants = history.map { |t| t[:merchant] }.uniq
    merchant_familiarity = common_merchants.include?(transaction[:merchant]) ? 0.0 : 0.5
    
    [amount_deviation, merchant_familiarity].max
  end
  
  def generate_fraud_alert(transaction, fraud_score)
    {
      transaction_id: transaction[:id],
      user_id: transaction[:user_id],
      fraud_score: fraud_score,
      alert_type: determine_alert_type(fraud_score),
      recommended_action: determine_action(fraud_score),
      details: build_alert_details(transaction),
      timestamp: Time.current
    }
  end
  
  def determine_alert_type(score)
    case score
    when 0.9..1.0 then 'HIGH_RISK'
    when 0.7..0.9 then 'MEDIUM_RISK'
    else 'LOW_RISK'
    end
  end
  
  def determine_action(score)
    case score
    when 0.9..1.0 then 'BLOCK_TRANSACTION'
    when 0.8..0.9 then 'REQUIRE_ADDITIONAL_AUTH'
    when 0.7..0.8 then 'FLAG_FOR_REVIEW'
    else 'MONITOR'
    end
  end
  
  def build_alert_details(transaction)
    {
      amount: transaction[:amount],
      merchant: transaction[:merchant],
      location: transaction[:location],
      payment_method: transaction[:payment_method],
      unusual_patterns: identify_unusual_patterns(transaction)
    }
  end
  
  def identify_unusual_patterns(transaction)
    patterns = []
    
    # Check for unusual timing
    if transaction[:timestamp].hour < 6 || transaction[:timestamp].hour > 23
      patterns << 'unusual_time'
    end
    
    # Check for unusual location
    user_history = @transaction_history[transaction[:user_id]] || []
    common_locations = user_history.map { |t| t[:location] }.uniq
    
    unless common_locations.include?(transaction[:location])
      patterns << 'new_location'
    end
    
    patterns
  end
  
  def analyze_fraud_patterns
    # Analyze overall fraud patterns from alerts
    fraud_indicators = @alerts_sent.flat_map { |alert| alert[:details][:unusual_patterns] }
    
    fraud_indicators.group_by(&:itself)
                    .transform_values(&:count)
                    .sort_by { |_, count| -count }
                    .first(10)
  end
end
```

#### Performance Optimization for Streaming

```ruby
class OptimizedStreamProcessor
  def initialize(options = {})
    @batch_size = options[:batch_size] || 100
    @buffer_size = options[:buffer_size] || 1000
    @worker_threads = options[:worker_threads] || 4
    @processing_queue = Queue.new
    @results_queue = Queue.new
  end
  
  def process_high_volume_stream(stream_source:)
    # Start worker threads
    workers = start_worker_threads
    
    Enumerator.new do |yielder|
      stream = StreamReader.new(stream_source)
      batch = []
      
      stream.each do |event|
        batch << event
        
        # Process batch when full
        if batch.size >= @batch_size
          @processing_queue << batch
          batch = []
        end
        
        # Yield results if available
        while !@results_queue.empty?
          yielder << @results_queue.pop
        end
      end
      
      # Process remaining events
      @processing_queue << batch if batch.any?
      
      # Wait for all processing to complete
      @worker_threads.times { @processing_queue << :stop }
      workers.each(&:join)
      
      # Yield final results
      while !@results_queue.empty?
        yielder << @results_queue.pop
      end
      
      yielder << {
        final: true,
        processing_complete: true,
        timestamp: Time.current
      }
    end
  end
  
  private
  
  def start_worker_threads
    @worker_threads.times.map do
      Thread.new do
        loop do
          batch = @processing_queue.pop
          break if batch == :stop
          
          # Process batch
          results = process_batch(batch)
          
          # Queue results
          @results_queue << {
            batch_results: results,
            batch_size: batch.size,
            processed_at: Time.current
          }
        end
      end
    end
  end
  
  def process_batch(batch)
    # Parallel processing within batch
    batch.map { |event| process_event(event) }
  end
  
  def process_event(event)
    # Event processing logic
    {
      event_id: event[:id],
      processed: true,
      processing_time: Time.current
    }
  end
end
```

Streaming tools transform AI agents from reactive systems that process historical data into proactive systems that respond to live events. By implementing proper streaming patterns, you enable real-time decision making, immediate anomaly detection, and continuous monitoring capabilities that are essential for modern applications.

The key to successful streaming tools is balancing throughput with resource usage, implementing proper buffering strategies, and designing for the specific latency and accuracy requirements of your use case. Whether you're monitoring system performance, detecting fraud, or analyzing user behavior, streaming tools provide the foundation for real-time AI intelligence.

Tool Security
-------------

### The $50,000 SQL Injection That Almost Happened

Our AI agent was happily processing customer requests:

```
User: "Show me orders for customer'; DROP TABLE orders; --"
AI: "Let me query that for you..."
```

Fortunately, our security measures caught it. But imagine if they hadn't.

AI agents are uniquely vulnerable because:

1. They interpret natural language into actions
2. Users can be creative with their requests
3. The AI wants to be helpful (sometimes too helpful)

Here's how we learned to secure AI tools the hard way:

### Input Validation and Sanitization

```ruby
class SecureDatabaseTool
  def initialize(connection)
    @db = connection
  end
  
  def safe_query(table:, columns: '*', where: {}, limit: 100)
    # Validate table name (whitelist approach)
    allowed_tables = %w[users orders products customers]
    unless allowed_tables.include?(table)
      return { error: "Access denied to table: #{table}" }
    end
    
    # Validate columns
    if columns != '*'
      columns = validate_columns(columns, table)
      return { error: "Invalid columns specified" } unless columns
    end
    
    # Sanitize limit
    limit = [limit.to_i, 1000].min  # Cap at 1000 records
    
    # Build parameterized query
    query = build_safe_query(table, columns, where, limit)
    
    begin
      result = @db.execute(query[:sql], query[:params])
      { success: true, data: result.to_a }
    rescue => e
      { error: "Query failed: #{sanitize_error_message(e.message)}" }
    end
  end
  
  private
  
  def validate_columns(columns, table)
    # Get allowed columns for table
    allowed_columns = get_table_columns(table)
    requested_columns = columns.split(',').map(&:strip)
    
    # Check if all requested columns are allowed
    if requested_columns.all? { |col| allowed_columns.include?(col) }
      requested_columns.join(', ')
    else
      nil
    end
  end
  
  def sanitize_error_message(message)
    # Remove potentially sensitive information from error messages
    message.gsub(/password\s*=\s*[^\s]+/i, 'password=***')
           .gsub(/token\s*=\s*[^\s]+/i, 'token=***')
  end
end
```

### Rate Limiting

```ruby
class RateLimitedAPI
  def initialize(api_client)
    @api = api_client
    @rate_limiter = {}
  end
  
  def call_api(endpoint:, params: {}, user_id: nil)
    # Implement rate limiting per user
    if user_id && rate_limited?(user_id)
      return { 
        error: "Rate limit exceeded. Try again later.",
        retry_after: get_retry_after(user_id)
      }
    end
    
    begin
      result = @api.request(endpoint, params)
      record_api_call(user_id) if user_id
      result
    rescue => e
      { error: "API call failed: #{e.message}" }
    end
  end
  
  private
  
  def rate_limited?(user_id)
    now = Time.now
    @rate_limiter[user_id] ||= { calls: [], window_start: now }
    
    # Clean old calls (outside 1-minute window)
    @rate_limiter[user_id][:calls].reject! { |time| now - time > 60 }
    
    # Check if limit exceeded (10 calls per minute)
    @rate_limiter[user_id][:calls].count >= 10
  end
  
  def record_api_call(user_id)
    @rate_limiter[user_id][:calls] << Time.now
  end
end
```

### Access Control

```ruby
class SecureFileTool
  def initialize(base_directory)
    @base_dir = File.expand_path(base_directory)
  end
  
  def read_file(file_path:, user_id:)
    # Check user permissions
    unless user_can_access_file?(user_id, file_path)
      return { error: "Access denied to file: #{file_path}" }
    end
    
    # Prevent directory traversal
    full_path = File.expand_path(File.join(@base_dir, file_path))
    unless full_path.start_with?(@base_dir)
      return { error: "Invalid file path" }
    end
    
    # Check if file exists and is readable
    unless File.exist?(full_path) && File.readable?(full_path)
      return { error: "File not found or not readable" }
    end
    
    begin
      content = File.read(full_path)
      {
        success: true,
        content: content,
        file_size: File.size(full_path),
        last_modified: File.mtime(full_path)
      }
    rescue => e
      { error: "Failed to read file: #{e.message}" }
    end
  end
  
  private
  
  def user_can_access_file?(user_id, file_path)
    # Implement your access control logic
    user = User.find(user_id)
    return false unless user
    
    # Example: Check file permissions based on user role
    case user.role
    when 'admin'
      true
    when 'user'
      # Users can only access files in their directory
      file_path.start_with?("users/#{user_id}/")
    else
      false
    end
  end
end
```

Performance Optimization: Making Tools Fast and Efficient
--------------------------------------------------------

Performance optimization in AI tool systems differs significantly from traditional web application optimization. The unique challenges stem from the unpredictable nature of AI interactions, the variety of external services involved, and the need to maintain responsiveness while processing complex operations.

### Understanding AI Tool Performance Bottlenecks

AI agents create unique performance patterns that differ from traditional user interactions. Users expect immediate responses to conversational queries, but tools often need to perform complex operations like database queries, API calls, or file processing. This creates a tension between the conversational expectation of immediate response and the reality of processing time.

The primary performance bottlenecks in AI tool systems include:

**Redundant Operations**: AI agents may request the same information multiple times during a conversation. Without proper caching, each request triggers a full operation, leading to unnecessary resource consumption and slower response times.

**Connection Overhead**: Many tools interact with external services that require connection establishment, authentication, and protocol negotiation. Creating new connections for each operation adds significant latency.

**Sequential Processing**: AI agents often need information from multiple sources to complete a task. Processing these requests sequentially can lead to cumulative delays, especially when each operation involves network calls.

**Resource Contention**: Multiple concurrent conversations may compete for the same resources, leading to performance degradation during peak usage periods.

### The Caching Strategy: Intelligent Result Reuse

Caching is often the most effective optimization technique for AI tools because conversational patterns naturally create opportunities for result reuse. Users frequently ask related questions or return to previous topics, and AI agents may need to verify information multiple times during complex operations.

Effective caching strategies for AI tools must consider:

**Cache Key Design**: The cache key must capture all relevant parameters that affect the result. This includes not just the primary input but also any context variables, user-specific data, or configuration settings that might influence the output.

**Time-Based Invalidation**: Different types of data have different freshness requirements. Financial data might need minute-level accuracy, while user profile information might be valid for hours or days.

**Cache Hierarchy**: A multi-level cache system can provide both fast access to frequently used data and longer-term storage for less frequently accessed but expensive-to-compute results.

**Selective Caching**: Not all tool results should be cached. Sensitive information, user-specific data, or results that change frequently may be inappropriate for caching.

### Connection Pooling: Efficient Resource Management

Connection pooling addresses the overhead of establishing connections to external services. Instead of creating a new connection for each tool operation, a pool maintains a set of reusable connections that can be shared across multiple operations.

The benefits of connection pooling include:

**Reduced Latency**: Eliminating connection establishment time can significantly reduce response times, especially for database queries and API calls.

**Resource Efficiency**: Maintaining a controlled number of connections prevents resource exhaustion while ensuring adequate capacity for concurrent operations.

**Improved Reliability**: Pool management can handle connection failures gracefully, automatically retrying with fresh connections when needed.

**Better Monitoring**: Centralized connection management provides visibility into resource usage patterns and helps identify bottlenecks.

### Parallel Processing: Maximizing Throughput

AI agents often need to gather information from multiple sources to complete a task. Processing these requests in parallel can dramatically reduce overall response time, especially when the operations are independent.

Parallel processing strategies include:

**Independent Operations**: When multiple tools provide different aspects of the same information, they can be executed simultaneously without affecting each other.

**Batch Processing**: Some operations can be optimized by processing multiple items together, reducing per-item overhead.

**Asynchronous Execution**: Long-running operations can be started early and their results collected later, allowing other processing to continue in parallel.

**Pipeline Processing**: Breaking complex operations into stages allows different stages to process different items simultaneously.

```ruby
# Example of parallel data fetching
class ParallelDataFetcher
  def fetch_multiple_sources(sources:)
    futures = sources.map do |source|
      Concurrent::Future.execute { fetch_from_source(source) }
    end
    
    # Wait for all operations to complete
    results = futures.map(&:value)
    combine_results(results)
  end
end
```

This approach transforms sequential operations that might take cumulative time into parallel operations that complete in roughly the time of the slowest individual operation.

### Caching: Your First Line of Defense

```ruby
class CachedAPITool
  def initialize(api_client, cache_store = nil)
    @api = api_client
    @cache = cache_store || ActiveSupport::Cache::MemoryStore.new
  end
  
  def get_data(endpoint:, params: {}, cache_ttl: 300)
    cache_key = generate_cache_key(endpoint, params)
    
    # Try to get from cache first
    cached_result = @cache.read(cache_key)
    return cached_result if cached_result
    
    # Fetch from API
    begin
      result = @api.request(endpoint, params)
      
      # Cache successful results
      if result[:success]
        @cache.write(cache_key, result, expires_in: cache_ttl)
      end
      
      result
    rescue => e
      { error: "API request failed: #{e.message}" }
    end
  end
  
  private
  
  def generate_cache_key(endpoint, params)
    "api_#{endpoint}_#{Digest::MD5.hexdigest(params.to_json)}"
  end
end
```

### Connection Pooling

```ruby
class PooledDatabaseTool
  def initialize(config)
    @pool = ConnectionPool.new(size: 5, timeout: 5) do
      Database.new(config)
    end
  end
  
  def query(sql:, params: [])
    @pool.with do |db|
      begin
        result = db.execute(sql, params)
        {
          success: true,
          data: result.to_a,
          row_count: result.count
        }
      rescue => e
        { error: "Database query failed: #{e.message}" }
      end
    end
  end
end
```

### Parallel Execution

```ruby
class ParallelDataFetcher
  def fetch_multiple_sources(sources:)
    # Use concurrent execution for multiple data sources
    futures = sources.map do |source|
      Concurrent::Future.execute do
        fetch_from_source(source)
      end
    end
    
    # Wait for all to complete with timeout
    results = {}
    futures.each_with_index do |future, index|
      source = sources[index]
      
      begin
        results[source] = future.value(timeout: 30)  # 30 second timeout
      rescue Concurrent::TimeoutError
        results[source] = { error: "Timeout fetching from #{source}" }
      rescue => e
        results[source] = { error: "Error fetching from #{source}: #{e.message}" }
      end
    end
    
    {
      success: true,
      results: results,
      completed_sources: results.count { |_, v| !v.key?(:error) }
    }
  end
  
  private
  
  def fetch_from_source(source)
    # Implementation for fetching from specific source
    case source[:type]
    when 'api'
      fetch_from_api(source[:url], source[:params])
    when 'database'
      fetch_from_database(source[:query])
    when 'file'
      fetch_from_file(source[:path])
    else
      { error: "Unknown source type: #{source[:type]}" }
    end
  end
end
```

Testing Tools
-------------

### Unit Testing

```ruby
RSpec.describe 'WeatherAPI Tool' do
  let(:weather_api) { WeatherAPI.new('test_api_key') }
  
  before do
    # Mock HTTP responses
    stub_request(:get, /api.openweathermap.org/)
      .to_return(
        status: 200,
        body: {
          name: 'San Francisco',
          main: { temp: 20, humidity: 65 },
          weather: [{ description: 'sunny' }],
          wind: { speed: 5 }
        }.to_json
      )
  end
  
  it 'returns weather data for valid location' do
    result = weather_api.get_current_weather(location: 'San Francisco')
    
    expect(result[:location]).to eq('San Francisco')
    expect(result[:temperature]).to eq(20)
    expect(result[:description]).to eq('sunny')
  end
  
  it 'handles API errors gracefully' do
    stub_request(:get, /api.openweathermap.org/)
      .to_return(status: 404, body: { message: 'City not found' }.to_json)
    
    result = weather_api.get_current_weather(location: 'InvalidCity')
    
    expect(result[:error]).to include('Failed to fetch weather data')
  end
end
```

### Integration Testing

```ruby
RSpec.describe 'Agent with Database Tool' do
  let(:agent) { create_test_agent_with_db_tool }
  let(:runner) { RAAF::Runner.new(agent: agent) }
  
  before do
    # Set up test database
    create_test_customers
  end
  
  it 'can query customer data' do
    result = runner.run("Find all premium customers")
    
    expect(result.success?).to be true
    expect(result.messages.last[:content]).to include('premium')
    
    # Verify tool was called
    expect(runner.tool_calls).to include(
      hash_including(tool_name: 'query_customers')
    )
  end
  
  it 'handles database errors gracefully' do
    # Simulate database error
    allow(Customer).to receive(:where).and_raise(ActiveRecord::StatementInvalid)
    
    result = runner.run("Find all customers")
    
    expect(result.success?).to be false
    expect(result.error).to include('Database query failed')
  end
end
```

### Mock Tools for Testing

```ruby
class MockWeatherTool
  def initialize(responses = {})
    @responses = responses
  end
  
  def get_current_weather(location:)
    if response = @responses[location]
      response
    else
      {
        location: location,
        temperature: 20,
        description: 'mock weather',
        humidity: 50,
        wind_speed: 10
      }
    end
  end
end

# In tests
RSpec.describe 'Weather Agent' do
  let(:mock_weather) do
    MockWeatherTool.new(
      'San Francisco' => {
        location: 'San Francisco',
        temperature: 18,
        description: 'foggy'
      }
    )
  end
  
  let(:agent) do
    agent = RAAF::Agent.new(
      name: "WeatherBot",
      instructions: "Provide weather information",
      model: "gpt-4o"
    )
    agent.add_tool(mock_weather.method(:get_current_weather))
    agent
  end
  
  it 'uses mock weather data' do
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run("What's the weather in San Francisco?")
    
    expect(result.messages.last[:content]).to include('foggy')
  end
end
```

Best Practices
--------------

### The Tool Design Principles That Saved Our Sanity

After building 200+ tools across dozens of production systems, these principles consistently separate the maintainable from the monstrous:

#### The "2 AM Test"

If you get paged at 2 AM because a tool is failing, can you:

1. Understand what it does from the name?
2. Debug it without reading the entire codebase?
3. Fix it without breaking other tools?

If not, your tool design needs work.

#### Real Examples: Bad vs. Good

**The Horror Story Tool**:

```ruby
def process(data, flag=nil, opts={})
  # 500 lines of spaghetti code
  # Does 17 different things based on flag
  # Sometimes returns hash, sometimes array, sometimes string
end
```

This tool caused 3 production outages. Nobody wanted to touch it.

**The Success Story Tool**:

```ruby
def calculate_shipping_cost(
  weight_kg:,           # Package weight in kilograms
  destination_country:, # ISO 3166-1 alpha-2 code
  service_level: 'standard' # 'express', 'standard', 'economy'
)
  # 50 lines of focused logic
  # Always returns: { success: bool, cost: float, currency: string, error: string }
end
```

This tool has run for 2 years without a single incident.

### The Five Commandments of Tool Design

1. **Single Responsibility** - If you can't explain what it does in one sentence, split it
2. **Consistent Interface** - Every tool returns `{success: true/false, data/error: ...}`
3. **Defensive Programming** - Assume the AI will send garbage inputs
4. **Observable Behavior** - Log inputs, outputs, and errors (sanitized)
5. **Graceful Degradation** - When things fail, fail informatively

### Error Handling: Because AI Agents Will Find Every Edge Case

Tools require robust error handling and validation to prevent unintended consequences. A database cleanup tool that works correctly in testing can cause data loss in production if not properly validated.

The problem? We didn't handle the case where the user said "delete all the old records" and the AI interpreted "old" as "all."

#### The Seven Layers of Tool Safety

After too many production incidents, we developed this battle-tested error handling approach:

```ruby
class SafeDatabaseTool
  # Layer 1: Pre-execution validation
  def validate_before_execution(operation, params)
    case operation
    when :delete
      raise "Cannot delete without WHERE clause" if params[:where].nil?
      raise "Cannot delete more than 1000 records at once" if estimated_impact(params) > 1000
    when :update
      raise "Cannot update without WHERE clause" if params[:where].nil?
      raise "Cannot update primary keys" if params[:set].keys.include?('id')
    end
  end
  
  # Layer 2: Dry run capability
  def execute_with_safety(operation:, params:, dry_run: false)
    # Always validate first
    validate_before_execution(operation, params)
    
    # Show what would happen
    if dry_run
      return {
        operation: operation,
        affected_rows: estimated_impact(params),
        query: build_query(operation, params),
        warning: assess_risk_level(operation, params)
      }
    end
    
    # Layer 3: Transaction wrapper with rollback
    ActiveRecord::Base.transaction do
      begin
        # Layer 4: Execution with timeout
        result = Timeout.timeout(30) do
          execute_query(operation, params)
        end
        
        # Layer 5: Post-execution validation
        if result[:affected_rows] > expected_impact(params) * 1.5
          raise "Unexpected impact: affected #{result[:affected_rows]} rows, expected ~#{expected_impact(params)}"
        end
        
        # Layer 6: Audit logging
        log_operation({
          operation: operation,
          params: sanitize_params(params),
          result: result,
          user: current_user,
          agent: current_agent
        })
        
        result
      rescue => e
        # Layer 7: Intelligent error recovery
        handle_error(e, operation, params)
      end
    end
  end
  
  private
  
  def handle_error(error, operation, params)
    case error
    when ActiveRecord::LockWaitTimeout
      # Retry with backoff
      retry_with_backoff(operation, params)
    when ActiveRecord::DeadlockDetected
      # Smaller batches
      execute_in_batches(operation, params)
    when Timeout::Error
      # Check if partially completed
      assess_partial_completion(operation, params)
    else
      # Log and return safe error
      log_error(error, operation, params)
      {
        success: false,
        error: safe_error_message(error),
        error_type: error.class.name,
        recoverable: is_recoverable?(error),
        suggestion: suggest_resolution(error, operation)
      }
    end
  end
  
  def safe_error_message(error)
    # Never expose internal details
    case error
    when ActiveRecord::RecordNotFound
      "The requested record was not found"
    when ActiveRecord::InvalidForeignKey
      "This operation would break data relationships"
    when PG::ConnectionBad
      "Database connection issue. Please try again"
    else
      "Operation failed. Error ID: #{log_error_id(error)}"
    end
  end
end
```

#### Real-World Error Scenarios We've Survived

**The Infinite Loop Bug**

```ruby
# What went wrong
def analyze_data(query:)
  results = fetch_results(query)
  if results.empty?
    # AI kept retrying with same query
    analyze_data(query: query)  # Stack overflow!
  end
end

# How we fixed it
def analyze_data(query:, attempt: 1)
  raise "Max retries exceeded" if attempt > 3
  
  results = fetch_results(query)
  if results.empty?
    # Modify query before retry
    relaxed_query = relax_constraints(query)
    analyze_data(query: relaxed_query, attempt: attempt + 1)
  else
    results
  end
end
```

**The API Rate Limit Cascade**

```ruby
# What went wrong
def enrich_data(items:)
  items.map do |item|
    external_api.enrich(item)  # Hit rate limit after 100 calls
  end
end

# How we fixed it
class RateLimitedEnricher
  def initialize
    @rate_limiter = Throttle.new(
      limit: 100,
      window: 60  # per minute
    )
    @queue = Queue.new
    start_processor
  end
  
  def enrich_batch(items:)
    job_id = SecureRandom.uuid
    
    items.each do |item|
      @queue.push({ item: item, job_id: job_id })
    end
    
    {
      job_id: job_id,
      status: 'queued',
      total_items: items.size,
      estimated_time: (items.size / 100.0 * 60).ceil
    }
  end
  
  private
  
  def start_processor
    Thread.new do
      loop do
        if @rate_limiter.allow?
          item_data = @queue.pop
          begin
            enriched = external_api.enrich(item_data[:item])
            store_result(item_data[:job_id], enriched)
          rescue => e
            store_error(item_data[:job_id], e)
          end
        else
          sleep(1)  # Wait for rate limit window
        end
      end
    end
  end
end
```

#### The Error Handling Checklist

Every tool should handle these scenarios:

1. **Invalid Input**

   ```ruby
   # Bad: Crashes with nil
   def search(query:)
     database.search(query.downcase)
   end
   
   # Good: Handles gracefully
   def search(query:)
     return { error: "Query required" } if query.nil? || query.empty?
     normalized = query.to_s.strip.downcase
     return { error: "Query too short" } if normalized.length < 2
     database.search(normalized)
   end
   ```

2. **Resource Exhaustion**

   ```ruby
   def process_file(path:)
     # Check file size first
     size = File.size(path)
     return { error: "File too large (max 100MB)" } if size > 100.megabytes
     
     # Process in chunks to avoid memory issues
     File.open(path) do |file|
       file.each_slice(1000) do |lines|
         process_chunk(lines)
       end
     end
   end
   ```

3. **Partial Failures**

   ```ruby
   def bulk_update(records:)
     results = { succeeded: [], failed: [] }
     
     records.each do |record|
       begin
         updated = update_record(record)
         results[:succeeded] << updated
       rescue => e
         results[:failed] << {
           record: record,
           error: e.message
         }
       end
     end
     
     results
   end
   ```

### Performance Guidelines

1. **Use Connection Pooling** for database and API connections
2. **Implement Caching** for frequently accessed data
3. **Add Timeouts** to prevent hanging operations
4. **Use Async Execution** for long-running tasks
5. **Limit Resource Usage** to prevent system overload

### Security Checklist

- [ ] Validate all inputs
- [ ] Sanitize outputs
- [ ] Implement access controls
- [ ] Use parameterized queries
- [ ] Prevent directory traversal
- [ ] Add rate limiting
- [ ] Log security events
- [ ] Handle secrets securely

Next Steps
----------

Now that you understand the tool system:

* **[RAAF Memory Guide](memory_guide.html)** - Advanced context management
* **[Multi-Agent Guide](multi_agent_guide.html)** - Orchestrate tool usage across agents
* **[DSL Guide](dsl_guide.html)** - Declarative tool configuration
* **[Security Guide](raaf_guardraaf_guide.html)** - Secure tool execution
* **[Testing Guide](testing_guide.html)** - Test tools and agents effectively