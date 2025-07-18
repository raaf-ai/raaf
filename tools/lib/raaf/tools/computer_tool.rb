# frozen_string_literal: true

# rubocop:disable Naming/MethodParameterName

require "raaf/function_tool"

##
# Computer Control Tools for RAAF
#
# This module provides computer automation capabilities through two implementations:
# - HostedComputerTool: Uses OpenAI's hosted computer use API
# - ComputerTool: Local computer control with cross-platform support
#
# == Security Warning
#
# **CRITICAL**: Computer control tools provide direct access to the operating system.
# Only use these tools in secure, controlled environments. Never enable computer
# control for untrusted agents or in production systems accessible to external users.
#
# == Platform Support
#
# * **macOS**: Full support via AppleScript and system tools
# * **Linux**: Support via xdotool and standard utilities
# * **Windows**: Limited support (screenshots only, expandable)
#
# @example Basic computer control setup
#   # Local computer control with restricted actions
#   tool = ComputerTool.new(allowed_actions: [:screenshot, :click])
#   agent.add_tool(tool)
#
# @example Hosted computer control
#   # Uses OpenAI's hosted environment
#   tool = HostedComputerTool.new(display_width_px: 1920, display_height_px: 1080)
#   agent.add_tool(tool)
#
# @author RAAF (Ruby AI Agents Factory) Team
# @since 0.1.0
# @see https://platform.openai.com/docs/assistants/tools/computer-use OpenAI Computer Use documentation
module RAAF
  module Tools
    ##
    # Hosted computer use tool for OpenAI API
    #
    # This tool provides access to OpenAI's hosted computer use capability,
    # allowing agents to interact with a controlled desktop environment hosted
    # by OpenAI. This is the recommended approach for production applications
    # requiring computer automation without local system access.
    #
    # @example Basic hosted computer tool
    #   tool = HostedComputerTool.new(
    #     display_width_px: 1920,
    #     display_height_px: 1080
    #   )
    #   agent.add_tool(tool)
    #
    # @example With display configuration
    #   tool = HostedComputerTool.new(
    #     display_width_px: 1024,
    #     display_height_px: 768,
    #     display_number: 1
    #   )
    #
    # @see https://platform.openai.com/docs/assistants/tools/computer-use OpenAI Computer Use API
    class HostedComputerTool
      attr_reader :display_width_px, :display_height_px, :display_number

      ##
      # Initialize hosted computer tool
      #
      # @param display_width_px [Integer] display width in pixels (default: 1024)
      # @param display_height_px [Integer] display height in pixels (default: 768)
      # @param display_number [Integer, nil] specific display number (optional)
      #
      # @example Standard desktop resolution
      #   tool = HostedComputerTool.new(
      #     display_width_px: 1920,
      #     display_height_px: 1080
      #   )
      def initialize(display_width_px: 1024, display_height_px: 768, display_number: nil)
        @display_width_px = display_width_px
        @display_height_px = display_height_px
        @display_number = display_number
      end

      ##
      # Tool name for OpenAI API
      #
      # @return [String] the tool name
      def name
        "computer"
      end

      ##
      # Convert to OpenAI tool definition format
      #
      # @return [Hash] tool definition for OpenAI API
      #
      # @example Tool definition output
      #   {
      #     type: "computer",
      #     name: "computer",
      #     computer: {
      #       display_width_px: 1920,
      #       display_height_px: 1080,
      #       display_number: 1
      #     }
      #   }
      def to_tool_definition
        {
          type: "computer",
          name: "computer",
          computer: {
            display_width_px: @display_width_px,
            display_height_px: @display_height_px,
            display_number: @display_number
          }.compact
        }
      end
    end

    ##
    # Local computer control tool implementation
    #
    # This tool provides direct control over the local computer system, including
    # screen capture, mouse control, keyboard input, and scrolling. It supports
    # multiple operating systems with platform-specific implementations.
    #
    # == Security Considerations
    #
    # **WARNING**: This tool provides unrestricted access to the local system.
    # - Only use in trusted, controlled environments
    # - Restrict allowed_actions to minimum required functionality
    # - Never enable for untrusted agents or external access
    # - Consider using HostedComputerTool for safer remote execution
    #
    # == Supported Actions
    #
    # * **screenshot**: Capture screen images
    # * **click**: Mouse clicking at coordinates
    # * **type**: Keyboard text input
    # * **scroll**: Scroll screen content
    # * **move**: Move mouse cursor
    # * **key**: Press specific keys (Return, Tab, etc.)
    #
    # == Platform Dependencies
    #
    # * **macOS**: Uses AppleScript (built-in)
    # * **Linux**: Requires xdotool (`sudo apt-get install xdotool`)
    # * **Windows**: Limited support (future expansion planned)
    #
    # @example Basic setup with safety restrictions
    #   tool = ComputerTool.new(
    #     allowed_actions: [:screenshot, :click],
    #     screen_size: { width: 1920, height: 1080 }
    #   )
    #   agent.add_tool(tool)
    #
    # @example Full control (use with extreme caution)
    #   tool = ComputerTool.new(
    #     allowed_actions: [:screenshot, :click, :type, :scroll, :move, :key]
    #   )
    #
    # @example Agent usage
    #   # Agent will call: computer_action(action: "screenshot")
    #   # Agent will call: computer_action(action: "click", x: 100, y: 200)
    #   # Agent will call: computer_action(action: "type", text: "Hello World")
    class ComputerTool < FunctionTool
      ##
      # Initialize local computer control tool
      #
      # @param allowed_actions [Array<Symbol>] permitted actions (default: [:screenshot, :click, :type, :scroll])
      # @param screen_size [Hash, nil] screen dimensions {width:, height:} (auto-detected if nil)
      #
      # @example Restricted tool for safer operation
      #   tool = ComputerTool.new(
      #     allowed_actions: [:screenshot],  # Only allow screenshots
      #     screen_size: { width: 1920, height: 1080 }
      #   )
      #
      # @example Full control tool
      #   tool = ComputerTool.new(
      #     allowed_actions: [:screenshot, :click, :type, :scroll, :move, :key]
      #   )
      def initialize(allowed_actions: %i[screenshot click type scroll], screen_size: nil)
        @allowed_actions = allowed_actions
        @screen_size = screen_size || detect_screen_size

        super(method(:computer_action),
              name: "computer_control",
              description: "Control computer screen, mouse, and keyboard with safety restrictions",
              parameters: computer_parameters)
      end

      ##
      # Execute computer action with safety validation
      #
      # This is the main method called by agents. It validates that the requested
      # action is allowed and then delegates to the appropriate platform-specific
      # implementation.
      #
      # @param action [String] the action to perform
      # @param kwargs [Hash] action-specific parameters
      # @return [String] result message describing the action outcome
      #
      # @example Screenshot action
      #   computer_action(action: "screenshot")
      #   # => "Screenshot saved to /tmp/screenshot_1234567890.png"
      #
      # @example Click action
      #   computer_action(action: "click", x: 100, y: 200, button: "left")
      #   # => "Clicked left mouse button at (100, 200)"
      #
      # @example Type action
      #   computer_action(action: "type", text: "Hello World")
      #   # => "Typed text: Hello World"
      def computer_action(action:, **kwargs)
        unless @allowed_actions.include?(action.to_sym)
          return "Action '#{action}' is not allowed. Allowed actions: #{@allowed_actions.join(", ")}"
        end

        case action.to_s
        when "screenshot"
          take_screenshot(**kwargs)
        when "click"
          click_mouse(**kwargs)
        when "type"
          type_text(**kwargs)
        when "scroll"
          scroll_screen(**kwargs)
        when "move"
          move_mouse(**kwargs)
        when "key"
          press_key(**kwargs)
        else
          "Unknown action: #{action}"
        end
      rescue StandardError => e
        "Error performing computer action: #{e.message}"
      end

      private

      def computer_parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[screenshot click type scroll move key],
              description: "Action to perform"
            },
            x: {
              type: "integer",
              description: "X coordinate for click/move actions"
            },
            y: {
              type: "integer",
              description: "Y coordinate for click/move actions"
            },
            text: {
              type: "string",
              description: "Text to type"
            },
            key: {
              type: "string",
              description: "Key to press (e.g., 'Return', 'Tab', 'Escape')"
            },
            button: {
              type: "string",
              enum: %w[left right middle],
              description: "Mouse button for click actions",
              default: "left"
            },
            direction: {
              type: "string",
              enum: %w[up down left right],
              description: "Scroll direction"
            },
            amount: {
              type: "integer",
              description: "Scroll amount (pixels or lines)",
              default: 100
            }
          },
          required: ["action"]
        }
      end

      def take_screenshot(filename: nil, region: nil)
        if mac_system?
          take_screenshot_mac(filename, region)
        elsif linux_system?
          take_screenshot_linux(filename, region)
        elsif windows_system?
          take_screenshot_windows(filename, region)
        else
          "Screenshot not supported on this operating system"
        end
      end

      def take_screenshot_mac(filename, region)
        filename ||= "/tmp/screenshot_#{Time.now.to_i}.png"

        cmd = "screencapture"
        cmd += " -R #{region[:x]},#{region[:y]},#{region[:width]},#{region[:height]}" if region
        cmd += " #{filename}"

        if system(cmd)
          "Screenshot saved to #{filename}"
        else
          "Failed to take screenshot"
        end
      end

      def take_screenshot_linux(filename, _region)
        filename ||= "/tmp/screenshot_#{Time.now.to_i}.png"

        cmd = if command_exists?("gnome-screenshot")
                "gnome-screenshot -f #{filename}"
              elsif command_exists?("scrot")
                "scrot #{filename}"
              elsif command_exists?("import")
                "import -window root #{filename}"
              else
                return "No screenshot tool found (gnome-screenshot, scrot, or imagemagick)"
              end

        if system(cmd)
          "Screenshot saved to #{filename}"
        else
          "Failed to take screenshot"
        end
      end

      def take_screenshot_windows(_filename, _region)
        "Screenshot not implemented for Windows yet"
      end

      def click_mouse(x:, y:, button: "left")
        validate_coordinates(x, y)

        if mac_system?
          click_mouse_mac(x, y, button)
        elsif linux_system?
          click_mouse_linux(x, y, button)
        else
          "Mouse click not supported on this operating system"
        end
      end

      def click_mouse_mac(x, y, button)
        # Use AppleScript for mouse clicks on Mac
        # rubocop:disable Lint/DuplicateBranch
        case button
        when "left" then 1
        when "right" then 2
        when "middle" then 3
        else 1
        end
        # rubocop:enable Lint/DuplicateBranch

        script = %(
          tell application "System Events"
            click at {#{x}, #{y}}
          end tell
        )

        if system("osascript", "-e", script)
          "Clicked #{button} mouse button at (#{x}, #{y})"
        else
          "Failed to click mouse"
        end
      end

      def click_mouse_linux(x, y, button)
        if command_exists?("xdotool")
          # rubocop:disable Lint/DuplicateBranch
          button_num = case button
                       when "left" then 1
                       when "right" then 3
                       when "middle" then 2
                       else 1
                       end
          # rubocop:enable Lint/DuplicateBranch

          if system("xdotool mousemove #{x} #{y} click #{button_num}")
            "Clicked #{button} mouse button at (#{x}, #{y})"
          else
            "Failed to click mouse"
          end
        else
          "xdotool not found. Install with: sudo apt-get install xdotool"
        end
      end

      def type_text(text:)
        if mac_system?
          type_text_mac(text)
        elsif linux_system?
          type_text_linux(text)
        else
          "Text typing not supported on this operating system"
        end
      end

      def type_text_mac(text)
        # Escape special characters for AppleScript
        escaped_text = text.gsub('"', '\\"')

        script = %(
          tell application "System Events"
            keystroke "#{escaped_text}"
          end tell
        )

        if system("osascript", "-e", script)
          "Typed text: #{text}"
        else
          "Failed to type text"
        end
      end

      def type_text_linux(text)
        if command_exists?("xdotool")
          if system("xdotool", "type", text)
            "Typed text: #{text}"
          else
            "Failed to type text"
          end
        else
          "xdotool not found. Install with: sudo apt-get install xdotool"
        end
      end

      def scroll_screen(direction:, amount: 100)
        if mac_system?
          scroll_screen_mac(direction, amount)
        elsif linux_system?
          scroll_screen_linux(direction, amount)
        else
          "Scrolling not supported on this operating system"
        end
      end

      def scroll_screen_mac(direction, amount)
        # Convert direction to scroll values
        x_delta, y_delta = case direction
                           when "up" then [0, amount]
                           when "down" then [0, -amount]
                           when "left" then [amount, 0]
                           when "right" then [-amount, 0]
                           else [0, 0]
                           end

        script = %(
          tell application "System Events"
            scroll {#{x_delta}, #{y_delta}}
          end tell
        )

        if system("osascript", "-e", script)
          "Scrolled #{direction} by #{amount} pixels"
        else
          "Failed to scroll"
        end
      end

      def scroll_screen_linux(direction, amount)
        if command_exists?("xdotool")
          button = case direction
                   when "up" then 4
                   when "down" then 5
                   else return "Invalid scroll direction"
                   end

          # Repeat scroll action based on amount
          times = [amount / 20, 1].max

          if system("xdotool click --repeat #{times} #{button}")
            "Scrolled #{direction} by #{amount} pixels"
          else
            "Failed to scroll"
          end
        else
          "xdotool not found. Install with: sudo apt-get install xdotool"
        end
      end

      def move_mouse(x:, y:)
        validate_coordinates(x, y)

        if mac_system?
          move_mouse_mac(x, y)
        elsif linux_system?
          move_mouse_linux(x, y)
        else
          "Mouse movement not supported on this operating system"
        end
      end

      def move_mouse_mac(x, y)
        script = %(
          tell application "System Events"
            set the mouseLoc to {#{x}, #{y}}
          end tell
        )

        if system("osascript", "-e", script)
          "Moved mouse to (#{x}, #{y})"
        else
          "Failed to move mouse"
        end
      end

      def move_mouse_linux(x, y)
        if command_exists?("xdotool")
          if system("xdotool mousemove #{x} #{y}")
            "Moved mouse to (#{x}, #{y})"
          else
            "Failed to move mouse"
          end
        else
          "xdotool not found. Install with: sudo apt-get install xdotool"
        end
      end

      def press_key(key:)
        if mac_system?
          press_key_mac(key)
        elsif linux_system?
          press_key_linux(key)
        else
          "Key press not supported on this operating system"
        end
      end

      def press_key_mac(key)
        # Map common key names to AppleScript key codes
        key_mapping = {
          "Return" => "return",
          "Enter" => "return",
          "Tab" => "tab",
          "Escape" => "escape",
          "Space" => "space",
          "Delete" => "delete",
          "Backspace" => "delete"
        }

        script_key = key_mapping[key] || key.downcase

        script = %{
          tell application "System Events"
            key code (ASCII character "#{script_key}")
          end tell
        }

        if system("osascript", "-e", script)
          "Pressed key: #{key}"
        else
          "Failed to press key"
        end
      end

      def press_key_linux(key)
        if command_exists?("xdotool")
          if system("xdotool key #{key}")
            "Pressed key: #{key}"
          else
            "Failed to press key"
          end
        else
          "xdotool not found. Install with: sudo apt-get install xdotool"
        end
      end

      def validate_coordinates(x, y)
        raise ArgumentError, "Coordinates must be integers" unless x.is_a?(Integer) && y.is_a?(Integer)

        raise ArgumentError, "Coordinates must be non-negative" unless x >= 0 && y >= 0

        return unless @screen_size
        return if x <= @screen_size[:width] && y <= @screen_size[:height]

        raise ArgumentError, "Coordinates exceed screen bounds"
      end

      def detect_screen_size
        if mac_system?
          output = `system_profiler SPDisplaysDataType | grep Resolution`
          { width: ::Regexp.last_match(1).to_i, height: ::Regexp.last_match(2).to_i } if output.match(/(\d+) x (\d+)/)
        elsif linux_system? && command_exists?("xdpyinfo")
          output = `xdpyinfo | grep dimensions`
          { width: ::Regexp.last_match(1).to_i, height: ::Regexp.last_match(2).to_i } if output.match(/(\d+)x(\d+)/)
        end
      rescue StandardError
        nil
      end

      def mac_system?
        RUBY_PLATFORM.include?("darwin")
      end

      def linux_system?
        RUBY_PLATFORM.include?("linux")
      end

      def windows_system?
        RUBY_PLATFORM.include?("mswin") || RUBY_PLATFORM.include?("mingw")
      end

      def command_exists?(command)
        system("which #{command} > /dev/null 2>&1")
      end
    end
  end
end

# rubocop:enable Naming/MethodParameterName
