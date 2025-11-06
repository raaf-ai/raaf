# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      # Helper methods for evaluations views
      module EvaluationsHelper
        def progress_bar_color(status)
          case status.to_s
          when 'completed'
            'bg-green-500'
          when 'failed'
            'bg-red-500'
          when 'running'
            'bg-blue-500'
          when 'pending'
            'bg-yellow-500'
          else
            'bg-gray-500'
          end
        end

        def render_status_icon(status)
          case status.to_s
          when 'completed'
            content_tag(:div, class: 'flex-shrink-0') do
              content_tag(:svg, class: 'w-5 h-5 text-green-500', fill: 'currentColor', viewBox: '0 0 20 20') do
                content_tag(:path, nil, fill_rule: 'evenodd', d: 'M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z', clip_rule: 'evenodd')
              end
            end
          when 'failed'
            content_tag(:div, class: 'flex-shrink-0') do
              content_tag(:svg, class: 'w-5 h-5 text-red-500', fill: 'currentColor', viewBox: '0 0 20 20') do
                content_tag(:path, nil, fill_rule: 'evenodd', d: 'M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z', clip_rule: 'evenodd')
              end
            end
          when 'running'
            content_tag(:div, class: 'flex-shrink-0') do
              content_tag(:svg, class: 'w-5 h-5 text-blue-500 animate-spin', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
                content_tag(:circle, nil, class: 'opacity-25', cx: '12', cy: '12', r: '10', stroke: 'currentColor', stroke_width: '4') +
                content_tag(:path, nil, class: 'opacity-75', fill: 'currentColor', d: 'M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z')
              end
            end
          else
            content_tag(:div, class: 'flex-shrink-0') do
              content_tag(:svg, class: 'w-5 h-5 text-gray-500', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
                content_tag(:path, nil, stroke_linecap: 'round', stroke_linejoin: 'round', stroke_width: '2', d: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z')
              end
            end
          end
        end

        def status_message(evaluation)
          case evaluation.status.to_s
          when 'pending'
            'Evaluation is queued and will start shortly...'
          when 'running'
            'Evaluation is currently running...'
          when 'completed'
            "Evaluation completed in #{format_duration(evaluation.duration_ms)}"
          when 'failed'
            'Evaluation failed. See error details below.'
          else
            'Unknown status'
          end
        end

        def format_time_remaining(seconds)
          return 'Unknown' if seconds.nil? || seconds <= 0

          if seconds < 60
            "#{seconds} second#{'s' unless seconds == 1}"
          elsif seconds < 3600
            minutes = (seconds / 60).to_i
            "#{minutes} minute#{'s' unless minutes == 1}"
          else
            hours = (seconds / 3600).to_i
            remaining_minutes = ((seconds % 3600) / 60).to_i
            "#{hours} hour#{'s' unless hours == 1} #{remaining_minutes} minute#{'s' unless remaining_minutes == 1}"
          end
        end

        def format_duration(milliseconds)
          return 'N/A' if milliseconds.nil?

          seconds = milliseconds / 1000.0
          if seconds < 1
            "#{milliseconds}ms"
          elsif seconds < 60
            "#{seconds.round(1)}s"
          else
            minutes = (seconds / 60).to_i
            remaining_seconds = (seconds % 60).to_i
            "#{minutes}m #{remaining_seconds}s"
          end
        end
      end
    end
  end
end
