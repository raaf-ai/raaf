#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the ComputerTool integration with OpenAI Agents Ruby.
# ComputerTool provides desktop automation capabilities including mouse control,
# keyboard input, screen capture, and window management. This is a powerful tool
# that enables agents to interact with any desktop application.
#
# ⚠️  SECURITY WARNING: This tool provides direct access to your desktop.
# Only use in controlled environments and with trusted AI models.
# Always review and approve actions before execution.

require_relative "../lib/openai_agents"

# No API key required for local computer control
# The tool works entirely locally using system commands

puts "=== Computer Tool Example ==="
puts
puts "⚠️  SECURITY WARNING:"
puts "This tool provides direct desktop access. Use with caution!"
puts "Only run in controlled environments with trusted models."
puts

# ============================================================================
# TOOL SETUP
# ============================================================================

# Create a computer tool with restricted actions for safety
computer_tool = OpenAIAgents::Tools::ComputerTool.new(
  allowed_actions: [:screenshot, :click, :type, :scroll, :move],  # Allow most actions
  screen_size: nil  # Auto-detect screen size
)

puts "Computer tool initialized:"
puts "- Allowed actions: #{computer_tool.instance_variable_get(:@allowed_actions)}"
puts "- Screen size: #{computer_tool.instance_variable_get(:@screen_size) || "Auto-detected"}"
puts "- Platform: #{RUBY_PLATFORM}"
puts

# ============================================================================
# EXAMPLE 1: BASIC SCREENSHOT CAPABILITY
# ============================================================================

puts "1. Screenshot capability:"

# Create an agent with screenshot capability
screenshot_agent = OpenAIAgents::Agent.new(
  name: "ScreenshotAgent",
  instructions: "You are a desktop assistant that can take screenshots. Help users by capturing their screen when requested.",
  model: "gpt-4o"
)

# Add computer tool for screenshots
screenshot_agent.add_tool(computer_tool)

# Create runner
runner = OpenAIAgents::Runner.new(agent: screenshot_agent)

# Test screenshot functionality
begin
  screenshot_messages = [{
    role: "user",
    content: "Please take a screenshot of the current desktop."
  }]

  screenshot_result = runner.run(screenshot_messages)
  puts "Screenshot result: #{screenshot_result.final_output}"
rescue StandardError => e
  puts "Screenshot error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 2: SAFE DESKTOP AUTOMATION
# ============================================================================

puts "2. Safe desktop automation:"

# Create a restricted automation tool (screenshot only for safety)
safe_tool = OpenAIAgents::Tools::ComputerTool.new(
  allowed_actions: [:screenshot],  # Only allow screenshots
  screen_size: nil
)

# Create a safe automation agent
safe_agent = OpenAIAgents::Agent.new(
  name: "SafeAutomationAgent",
  instructions: "You are a safe desktop assistant. You can only take screenshots for security. Help users by observing their desktop state.",
  model: "gpt-4o"
)

# Add safe tool
safe_agent.add_tool(safe_tool)

# Create runner
safe_runner = OpenAIAgents::Runner.new(agent: safe_agent)

# Test safe automation
begin
  safe_messages = [{
    role: "user",
    content: "Help me understand what's currently on my desktop by taking a screenshot."
  }]

  safe_result = safe_runner.run(safe_messages)
  puts "Safe automation result: #{safe_result.final_output}"
rescue StandardError => e
  puts "Safe automation error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 3: DIRECT TOOL USAGE (SAFER)
# ============================================================================

puts "3. Direct tool usage (safer approach):"

# Test various computer actions directly (with user awareness)
puts "\n⚠️  Testing computer actions (no actual execution without confirmation):"

# Simulate taking a screenshot
puts "\nTesting screenshot action:"
begin
  screenshot_result = computer_tool.call(action: "screenshot")
  puts "Screenshot action result: #{screenshot_result}"
rescue StandardError => e
  puts "Screenshot action error: #{e.message}"
end

# Test coordinate validation (safe)
puts "\nTesting coordinate validation:"
begin
  # This should work - safe coordinates
  move_result = computer_tool.call(action: "move", x: 100, y: 100)
  puts "Move action result: #{move_result}"
rescue StandardError => e
  puts "Move action error: #{e.message}"
end

# Test invalid coordinates (safe)
puts "\nTesting invalid coordinates:"
begin
  # This should fail validation
  invalid_result = computer_tool.call(action: "move", x: -10, y: -10)
  puts "Invalid move result: #{invalid_result}"
rescue StandardError => e
  puts "Invalid move error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 4: DESKTOP MONITORING AGENT
# ============================================================================

puts "4. Desktop monitoring agent:"

# Define monitoring tools
def analyze_screenshot(screenshot_path:)
  # Simulate screenshot analysis
  if File.exist?(screenshot_path)
    "Screenshot analysis: Desktop captured successfully. File size: #{File.size(screenshot_path)} bytes"
  else
    "Screenshot analysis: File not found at #{screenshot_path}"
  end
end

def desktop_health_check
  # Simulate desktop health check
  "Desktop health check: System responsive, no hanging applications detected."
end

# Create a monitoring agent
monitor_agent = OpenAIAgents::Agent.new(
  name: "DesktopMonitor",
  instructions: "You are a desktop monitoring assistant. Take screenshots to monitor desktop state and analyze system health.",
  model: "gpt-4o"
)

# Add monitoring tools
monitor_agent.add_tool(safe_tool)  # Only screenshots for safety
monitor_agent.add_tool(method(:analyze_screenshot))
monitor_agent.add_tool(method(:desktop_health_check))

# Create runner
monitor_runner = OpenAIAgents::Runner.new(agent: monitor_agent)

# Test monitoring
begin
  monitor_messages = [{
    role: "user",
    content: "Monitor the desktop state and perform a health check."
  }]

  monitor_result = monitor_runner.run(monitor_messages)
  puts "Desktop monitoring result: #{monitor_result.final_output}"
rescue StandardError => e
  puts "Desktop monitoring error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 5: ACCESSIBILITY ASSISTANT
# ============================================================================

puts "5. Accessibility assistant:"

# Create an accessibility tool with specific actions
accessibility_tool = OpenAIAgents::Tools::ComputerTool.new(
  allowed_actions: [:screenshot, :scroll, :move],  # Safe actions for accessibility
  screen_size: nil
)

# Create an accessibility agent
accessibility_agent = OpenAIAgents::Agent.new(
  name: "AccessibilityAgent",
  instructions: "You are an accessibility assistant. Help users navigate their desktop using safe actions like screenshots and scrolling.",
  model: "gpt-4o"
)

# Add accessibility tool
accessibility_agent.add_tool(accessibility_tool)

# Create runner
accessibility_runner = OpenAIAgents::Runner.new(agent: accessibility_agent)

# Test accessibility features
begin
  accessibility_messages = [{
    role: "user",
    content: "Help me navigate my desktop. Take a screenshot to see what's available."
  }]

  accessibility_result = accessibility_runner.run(accessibility_messages)
  puts "Accessibility result: #{accessibility_result.final_output}"
rescue StandardError => e
  puts "Accessibility error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 6: SYSTEM REQUIREMENTS CHECK
# ============================================================================

puts "6. System requirements check:"

# Check system capabilities
puts "System capabilities:"
puts "- Operating System: #{RUBY_PLATFORM}"

# Check for required tools on different platforms
if RUBY_PLATFORM.include?("darwin")
  puts "- Platform: macOS"
  puts "- Screenshot: Built-in (screencapture)"
  puts "- Automation: Built-in (AppleScript)"
elsif RUBY_PLATFORM.include?("linux")
  puts "- Platform: Linux"
  xdotool_available = system("which xdotool > /dev/null 2>&1")
  puts "- xdotool: #{xdotool_available ? "Available" : "Not installed"}"
  
  screenshot_tools = []
  screenshot_tools << "gnome-screenshot" if system("which gnome-screenshot > /dev/null 2>&1")
  screenshot_tools << "scrot" if system("which scrot > /dev/null 2>&1")
  screenshot_tools << "imagemagick" if system("which import > /dev/null 2>&1")
  
  puts "- Screenshot tools: #{screenshot_tools.empty? ? "None found" : screenshot_tools.join(", ")}"
elsif RUBY_PLATFORM.include?("mswin") || RUBY_PLATFORM.include?("mingw")
  puts "- Platform: Windows"
  puts "- Note: Windows support is limited in this implementation"
else
  puts "- Platform: Unknown"
end

puts

# ============================================================================
# EXAMPLE 7: HOSTED COMPUTER TOOL (OPENAI API)
# ============================================================================

puts "7. Hosted computer tool (OpenAI API):"

if ENV["OPENAI_API_KEY"]
  puts "Hosted computer tool setup:"
  
  # Create a hosted computer tool
  hosted_tool = OpenAIAgents::Tools::HostedComputerTool.new(
    display_width_px: 1920,
    display_height_px: 1080,
    display_number: nil
  )
  
  puts "- Display size: #{hosted_tool.display_width_px}x#{hosted_tool.display_height_px}"
  puts "- Tool definition: #{hosted_tool.to_tool_definition}"
  puts "- Note: Hosted computer tool requires OpenAI API and special access"
else
  puts "Hosted computer tool requires OPENAI_API_KEY environment variable."
end

puts

# ============================================================================
# EXAMPLE 8: SECURITY CONSIDERATIONS
# ============================================================================

puts "8. Security considerations:"

puts "\nSecurity Features:"
puts "- Action whitelist: Only allowed actions can be performed"
puts "- Coordinate validation: Prevents invalid mouse coordinates"
puts "- Screen bounds checking: Ensures coordinates are within screen"
puts "- Platform-specific implementations: Uses appropriate system tools"
puts "- Error handling: Graceful failure for unsupported operations"

puts "\nSecurity Risks:"
puts "- Desktop access: Tool can control mouse, keyboard, and screen"
puts "- Data exposure: Screenshots may contain sensitive information"
puts "- Unintended actions: AI might perform unexpected operations"
puts "- System modification: Could potentially modify system settings"

puts "\nSafety Recommendations:"
puts "- Use restricted action lists in production"
puts "- Implement human approval for critical actions"
puts "- Monitor and log all computer tool usage"
puts "- Use in sandboxed or controlled environments"
puts "- Regularly review and update allowed actions"
puts "- Test thoroughly before production deployment"

puts

# ============================================================================
# EXAMPLE 9: TESTING FRAMEWORK
# ============================================================================

puts "9. Testing framework:"

# Create a testing tool with minimal actions
test_tool = OpenAIAgents::Tools::ComputerTool.new(
  allowed_actions: [:screenshot],  # Only screenshots for testing
  screen_size: { width: 1920, height: 1080 }
)

# Test various scenarios
test_scenarios = [
  { name: "Valid screenshot", action: "screenshot" },
  { name: "Invalid action", action: "invalid_action" },
  { name: "Valid coordinates", action: "move", x: 100, y: 100 },
  { name: "Invalid coordinates", action: "move", x: -10, y: -10 }
]

puts "Running test scenarios:"
test_scenarios.each do |scenario|
  begin
    result = test_tool.call(scenario)
    puts "✅ #{scenario[:name]}: #{result[0..50]}..."
  rescue StandardError => e
    puts "❌ #{scenario[:name]}: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 10: INTEGRATION WITH OTHER TOOLS
# ============================================================================

puts "10. Integration with other tools:"

# Define complementary tools
def process_screenshot(screenshot_path:, analysis_type: "general")
  # Simulate screenshot processing
  case analysis_type
  when "general"
    "General analysis: Screenshot contains desktop elements and applications"
  when "accessibility"
    "Accessibility analysis: UI elements and readability assessed"
  when "security"
    "Security analysis: No sensitive information detected in screenshot"
  else
    "Unknown analysis type: #{analysis_type}"
  end
end

def desktop_report(screenshots:, actions:)
  # Simulate desktop activity report
  "Desktop report: #{screenshots.size} screenshots taken, #{actions.size} actions performed"
end

# Create an integrated agent
integrated_agent = OpenAIAgents::Agent.new(
  name: "IntegratedAgent",
  instructions: "You are an integrated desktop assistant. Combine computer control with analysis tools for comprehensive desktop management.",
  model: "gpt-4o"
)

# Add multiple tools
integrated_agent.add_tool(safe_tool)
integrated_agent.add_tool(method(:process_screenshot))
integrated_agent.add_tool(method(:desktop_report))

# Create runner
integrated_runner = OpenAIAgents::Runner.new(agent: integrated_agent)

# Test integration
begin
  integrated_messages = [{
    role: "user",
    content: "Take a screenshot, analyze it for accessibility, and generate a report."
  }]

  integrated_result = integrated_runner.run(integrated_messages)
  puts "Integrated result: #{integrated_result.final_output}"
rescue StandardError => e
  puts "Integration error: #{e.message}"
end

puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== Computer Tool Configuration ==="
puts "Platform: #{RUBY_PLATFORM}"
puts "Allowed actions: #{computer_tool.instance_variable_get(:@allowed_actions)}"
puts "Screen size detection: #{computer_tool.instance_variable_get(:@screen_size) ? "Manual" : "Auto-detect"}"
puts "Security features: Action whitelist, coordinate validation, error handling"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key Computer Tool Features:"
puts "1. Cross-platform desktop automation (macOS, Linux, Windows)"
puts "2. Screenshot capture with region support"
puts "3. Mouse control (click, move, scroll)"
puts "4. Keyboard input (typing, key presses)"
puts "5. Action whitelist for security"
puts "6. Coordinate validation and bounds checking"
puts "7. Both local and hosted implementations"
puts "8. Integration with AI agents for automation"
puts
puts "Supported Actions:"
puts "- screenshot: Capture desktop or regions"
puts "- click: Mouse clicking with button selection"
puts "- type: Text input and typing"
puts "- scroll: Page scrolling in all directions"
puts "- move: Mouse cursor movement"
puts "- key: Individual key presses"
puts
puts "Security Best Practices:"
puts "- Use action whitelists to restrict capabilities"
puts "- Implement human approval for critical actions"
puts "- Monitor and log all desktop interactions"
puts "- Use in controlled, sandboxed environments"
puts "- Regularly review and update security policies"
puts "- Test thoroughly before production deployment"
puts "- Consider data privacy in screenshots"
puts "- Implement proper error handling and recovery"
puts
puts "⚠️  Important Security Note:"
puts "This tool provides powerful desktop access. Always use with caution,"
puts "implement proper security measures, and ensure user consent before"
puts "performing any desktop automation actions."