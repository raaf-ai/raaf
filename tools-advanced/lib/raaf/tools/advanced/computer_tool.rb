# frozen_string_literal: true

require "selenium-webdriver"
require "base64"
require "tempfile"

module RubyAIAgentsFactory
  module Tools
    module Advanced
      ##
      # Computer control tool for AI agents
      #
      # Provides AI agents with the ability to control the computer including:
      # - Taking screenshots
      # - Clicking on elements
      # - Typing text
      # - Scrolling
      # - Browser automation
      # - Desktop application control
      #
      # @example Basic computer control
      #   computer = ComputerTool.new(display: ":0", browser: "chrome")
      #   
      #   agent = Agent.new(
      #     name: "ComputerAgent",
      #     instructions: "You can control the computer to help users"
      #   )
      #   agent.add_tool(computer)
      #
      # @example Screenshot and analysis
      #   result = computer.screenshot
      #   # Agent can analyze the screenshot and take actions
      #
      class ComputerTool < RubyAIAgentsFactory::FunctionTool
        include RubyAIAgentsFactory::Logging

        # @return [String] Display identifier
        attr_reader :display

        # @return [String] Browser type
        attr_reader :browser

        # @return [Integer] Operation timeout
        attr_reader :timeout

        ##
        # Initialize computer tool
        #
        # @param display [String] Display identifier (e.g., ":0")
        # @param browser [String] Browser type ("chrome", "firefox", "safari")
        # @param timeout [Integer] Operation timeout in seconds
        # @param headless [Boolean] Run browser in headless mode
        # @param sandbox [Boolean] Enable sandbox mode
        #
        def initialize(display: ":0", browser: "chrome", timeout: 30, headless: false, sandbox: true)
          @display = display
          @browser = browser
          @timeout = timeout
          @headless = headless
          @sandbox = sandbox
          @driver = nil

          super(
            method(:execute_computer_action),
            name: "computer",
            description: "Control the computer - take screenshots, click, type, scroll, and navigate"
          )
        end

        ##
        # Execute computer action
        #
        # @param action [String] Action to perform
        # @param coordinate [Array<Integer>, nil] X,Y coordinates for click/hover
        # @param text [String, nil] Text to type
        # @param url [String, nil] URL to navigate to
        # @param selector [String, nil] CSS selector for element
        # @param scroll_direction [String, nil] Scroll direction ("up", "down", "left", "right")
        # @param scroll_amount [Integer, nil] Amount to scroll
        # @return [Hash] Action result
        #
        def execute_computer_action(action:, coordinate: nil, text: nil, url: nil, selector: nil, scroll_direction: nil, scroll_amount: nil)
          validate_security!

          case action
          when "screenshot"
            take_screenshot
          when "click"
            click(coordinate: coordinate, selector: selector)
          when "double_click"
            double_click(coordinate: coordinate, selector: selector)
          when "right_click"
            right_click(coordinate: coordinate, selector: selector)
          when "hover"
            hover(coordinate: coordinate, selector: selector)
          when "type"
            type_text(text: text, selector: selector)
          when "key"
            press_key(key: text)
          when "scroll"
            scroll(direction: scroll_direction, amount: scroll_amount)
          when "navigate"
            navigate(url: url)
          when "wait"
            wait_for_element(selector: selector, timeout: timeout)
          when "get_text"
            get_text(selector: selector)
          when "get_attribute"
            get_attribute(selector: selector, attribute: text)
          when "refresh"
            refresh_page
          when "back"
            go_back
          when "forward"
            go_forward
          when "close"
            close_browser
          else
            raise ArgumentError, "Unknown action: #{action}"
          end
        rescue StandardError => e
          log_error("Computer tool error", action: action, error: e)
          {
            success: false,
            error: e.message,
            action: action
          }
        end

        private

        def validate_security!
          return if @sandbox

          raise SecurityError, "Computer control requires sandbox mode for security"
        end

        def ensure_driver
          return @driver if @driver

          options = driver_options
          @driver = case @browser.downcase
                    when "chrome"
                      Selenium::WebDriver.for(:chrome, options: options)
                    when "firefox"
                      Selenium::WebDriver.for(:firefox, options: options)
                    when "safari"
                      Selenium::WebDriver.for(:safari, options: options)
                    else
                      raise ArgumentError, "Unsupported browser: #{@browser}"
                    end

          @driver.manage.timeouts.implicit_wait = @timeout
          @driver
        end

        def driver_options
          case @browser.downcase
          when "chrome"
            options = Selenium::WebDriver::Chrome::Options.new
            options.add_argument("--headless") if @headless
            options.add_argument("--no-sandbox") if @sandbox
            options.add_argument("--disable-dev-shm-usage") if @sandbox
            options.add_argument("--disable-gpu") if @headless
            options.add_argument("--window-size=1920,1080")
            options.add_argument("--display=#{@display}") if @display
            options
          when "firefox"
            options = Selenium::WebDriver::Firefox::Options.new
            options.add_argument("--headless") if @headless
            options.add_argument("--display=#{@display}") if @display
            options
          when "safari"
            Selenium::WebDriver::Safari::Options.new
          else
            raise ArgumentError, "Unsupported browser: #{@browser}"
          end
        end

        def take_screenshot
          driver = ensure_driver
          screenshot_base64 = driver.screenshot_as(:base64)
          
          {
            success: true,
            action: "screenshot",
            screenshot: screenshot_base64,
            timestamp: Time.current.iso8601,
            window_size: driver.manage.window.size.to_h
          }
        end

        def click(coordinate: nil, selector: nil)
          driver = ensure_driver

          if selector
            element = find_element(selector)
            element.click
          elsif coordinate
            action = driver.action
            action.move_to_location(coordinate[0], coordinate[1])
            action.click
            action.perform
          else
            raise ArgumentError, "Either coordinate or selector must be provided"
          end

          {
            success: true,
            action: "click",
            coordinate: coordinate,
            selector: selector
          }
        end

        def double_click(coordinate: nil, selector: nil)
          driver = ensure_driver

          if selector
            element = find_element(selector)
            driver.action.double_click(element).perform
          elsif coordinate
            action = driver.action
            action.move_to_location(coordinate[0], coordinate[1])
            action.double_click
            action.perform
          else
            raise ArgumentError, "Either coordinate or selector must be provided"
          end

          {
            success: true,
            action: "double_click",
            coordinate: coordinate,
            selector: selector
          }
        end

        def right_click(coordinate: nil, selector: nil)
          driver = ensure_driver

          if selector
            element = find_element(selector)
            driver.action.context_click(element).perform
          elsif coordinate
            action = driver.action
            action.move_to_location(coordinate[0], coordinate[1])
            action.context_click
            action.perform
          else
            raise ArgumentError, "Either coordinate or selector must be provided"
          end

          {
            success: true,
            action: "right_click",
            coordinate: coordinate,
            selector: selector
          }
        end

        def hover(coordinate: nil, selector: nil)
          driver = ensure_driver

          if selector
            element = find_element(selector)
            driver.action.move_to(element).perform
          elsif coordinate
            driver.action.move_to_location(coordinate[0], coordinate[1]).perform
          else
            raise ArgumentError, "Either coordinate or selector must be provided"
          end

          {
            success: true,
            action: "hover",
            coordinate: coordinate,
            selector: selector
          }
        end

        def type_text(text:, selector: nil)
          driver = ensure_driver

          if selector
            element = find_element(selector)
            element.clear
            element.send_keys(text)
          else
            driver.action.send_keys(text).perform
          end

          {
            success: true,
            action: "type",
            text: text,
            selector: selector
          }
        end

        def press_key(key:)
          driver = ensure_driver
          
          selenium_key = case key.downcase
                        when "enter", "return"
                          :enter
                        when "escape", "esc"
                          :escape
                        when "tab"
                          :tab
                        when "space"
                          :space
                        when "backspace"
                          :backspace
                        when "delete"
                          :delete
                        when "up"
                          :arrow_up
                        when "down"
                          :arrow_down
                        when "left"
                          :arrow_left
                        when "right"
                          :arrow_right
                        else
                          key
                        end

          driver.action.send_keys(selenium_key).perform

          {
            success: true,
            action: "key",
            key: key
          }
        end

        def scroll(direction: "down", amount: 3)
          driver = ensure_driver

          case direction.downcase
          when "up"
            driver.execute_script("window.scrollBy(0, -#{amount * 100})")
          when "down"
            driver.execute_script("window.scrollBy(0, #{amount * 100})")
          when "left"
            driver.execute_script("window.scrollBy(-#{amount * 100}, 0)")
          when "right"
            driver.execute_script("window.scrollBy(#{amount * 100}, 0)")
          else
            raise ArgumentError, "Invalid scroll direction: #{direction}"
          end

          {
            success: true,
            action: "scroll",
            direction: direction,
            amount: amount
          }
        end

        def navigate(url:)
          driver = ensure_driver
          driver.navigate.to(url)

          {
            success: true,
            action: "navigate",
            url: url,
            current_url: driver.current_url,
            title: driver.title
          }
        end

        def wait_for_element(selector:, timeout: nil)
          driver = ensure_driver
          wait_timeout = timeout || @timeout

          wait = Selenium::WebDriver::Wait.new(timeout: wait_timeout)
          element = wait.until { driver.find_element(css: selector) }

          {
            success: true,
            action: "wait",
            selector: selector,
            found: !!element
          }
        end

        def get_text(selector:)
          element = find_element(selector)
          text = element.text

          {
            success: true,
            action: "get_text",
            selector: selector,
            text: text
          }
        end

        def get_attribute(selector:, attribute:)
          element = find_element(selector)
          value = element.attribute(attribute)

          {
            success: true,
            action: "get_attribute",
            selector: selector,
            attribute: attribute,
            value: value
          }
        end

        def refresh_page
          driver = ensure_driver
          driver.navigate.refresh

          {
            success: true,
            action: "refresh",
            current_url: driver.current_url
          }
        end

        def go_back
          driver = ensure_driver
          driver.navigate.back

          {
            success: true,
            action: "back",
            current_url: driver.current_url
          }
        end

        def go_forward
          driver = ensure_driver
          driver.navigate.forward

          {
            success: true,
            action: "forward",
            current_url: driver.current_url
          }
        end

        def close_browser
          return { success: true, action: "close" } unless @driver

          @driver.quit
          @driver = nil

          {
            success: true,
            action: "close"
          }
        end

        def find_element(selector)
          driver = ensure_driver
          driver.find_element(css: selector)
        end
      end
    end
  end
end