# frozen_string_literal: true

module RAAF
  module DSL
    module DebugUtils
      VALID_LEVELS = %w[debug info warn error fatal].freeze

      class << self
        def enabled?
          ENV.fetch("DEBUG", "false").downcase == "true"
        end

        def level
          ENV.fetch("DEBUG_LEVEL", "info").downcase
        end

        def output_target
          ENV.fetch("DEBUG_OUTPUT", "console").downcase
        end

        def ai_debug_enabled?
          ENV.fetch("AI_DEBUG", "false").downcase == "true"
        end

        def trace_debug_enabled?
          ENV.fetch("TRACE_DEBUG", "false").downcase == "true"
        end

        def raw_debug_enabled?
          ENV.fetch("RAW_DEBUG", "false").downcase == "true"
        end

        def log(level, message, context: {})
          return unless enabled? && should_log?(level)

          formatted_message = format_message(message, context)

          case output_target
          when "file"
            log_to_file(level, formatted_message)
          when "both"
            log_to_console(level, formatted_message)
            log_to_file(level, formatted_message)
          else
            log_to_console(level, formatted_message)
          end
        end

        def ai_log(message, context: {})
          return unless ai_debug_enabled?

          log(:debug, "[AI] #{message}", context: context)
        end

        def trace_log(message, context: {})
          return unless trace_debug_enabled?

          log(:debug, "[TRACE] #{message}", context: context)
        end

        def raw_log(message, context: {})
          return unless raw_debug_enabled?

          log(:debug, "[RAW] #{message}", context: context)
        end

        def breakpoint_if_enabled(condition: true)
          return unless enabled? && condition

          require "debug"
          debugger # rubocop:disable Lint/Debugger
        end

        def benchmark(label)
          return yield unless enabled?

          start_time = Time.current
          result = yield
          duration = Time.current - start_time

          log(:info, "BENCHMARK [#{label}]: #{duration.round(3)}s")
          result
        end

        def inspect_variables(binding_context, *var_names)
          return unless enabled?

          var_names.each do |var_name|
            value = binding_context.local_variable_get(var_name)
            log(:debug, "INSPECT [#{var_name}]: #{value.inspect}")
          end
        end

        private

        def should_log?(message_level)
          level_priority(message_level) >= level_priority(level)
        end

        def level_priority(level_name)
          VALID_LEVELS.index(level_name.to_s) || 0
        end

        def format_message(message, context)
          timestamp = Time.current.strftime("%Y-%m-%d %H:%M:%S")
          context_str = context.any? ? " | Context: #{context.inspect}" : ""
          "[#{timestamp}] DEBUG: #{message}#{context_str}"
        end

        def log_to_console(level, message)
          case level.to_sym
          when :error, :fatal
            puts message.colorize(:red)
          when :warn
            puts message.colorize(:yellow)
          when :info
            puts message.colorize(:blue)
          else
            puts message.colorize(:green)
          end
        end

        def log_to_file(_level, message)
          log_file = File.join(Dir.pwd, "log", "debug.log")
          FileUtils.mkdir_p(File.dirname(log_file))
          File.open(log_file, "a") { |f| f.puts message }
        end
      end
    end
  end
end
