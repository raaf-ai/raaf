# frozen_string_literal: true

module RAAF
  module Eval
    module Comparison
      # Detects improvements and regressions across configurations
      class ImprovementDetector
        # Detect improvements (positive deltas)
        # @param field_deltas [Hash] Field deltas with configuration scores
        # @return [Hash] Improvements by configuration
        def self.detect_improvements(field_deltas)
          detect_by_delta(field_deltas) { |delta| delta > 0 }
        end

        # Detect regressions (negative deltas)
        # @param field_deltas [Hash] Field deltas with configuration scores
        # @return [Hash] Regressions by configuration
        def self.detect_regressions(field_deltas)
          detect_by_delta(field_deltas) { |delta| delta < 0 }
        end

        # Detect fields matching a delta condition
        # @param field_deltas [Hash] Field deltas with configuration scores
        # @yield [delta] Block that evaluates delta condition
        # @return [Hash] Fields matching condition by configuration
        def self.detect_by_delta(field_deltas, &condition)
          improvements_by_config = Hash.new { |h, k| h[k] = [] }

          field_deltas.each do |field_name, field_delta|
            field_delta[:configurations].each do |config_name, config_data|
              if condition.call(config_data[:delta])
                improvements_by_config[config_name] << field_name
              end
            end
          end

          improvements_by_config
        end
        private_class_method :detect_by_delta
      end
    end
  end
end
