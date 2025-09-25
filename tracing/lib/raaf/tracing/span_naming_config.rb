# frozen_string_literal: true

module RAAF
  module Tracing
    class SpanNamingConfig
      DEFAULT_PATTERN = "run.workflow.{component_type}.{component_name}.{method_name}"
      COMPACT_PATTERN = "{component_type}.{component_name}"
      DETAILED_PATTERN = "raaf.{trace_id}.{component_type}.{component_name}.{method_name}"

      attr_accessor :pattern, :include_method_names, :abbreviate_components

      def initialize
        @pattern = DEFAULT_PATTERN
        @include_method_names = true
        @abbreviate_components = false
      end

      def build_name(component_type, component_name, method_name)
        name = @pattern.dup
        name.gsub!("{component_type}", component_type.to_s)
        name.gsub!("{component_name}", format_component_name(component_name))

        if @include_method_names && method_name && method_name.to_s != "run"
          name.gsub!("{method_name}", method_name.to_s)
        else
          name.gsub!(".{method_name}", "")
        end

        name
      end

      private

      def format_component_name(name)
        return "" unless name && name != "Runner"

        if @abbreviate_components
          name.gsub(/Agent$|Tool$|Pipeline$/, "")
        else
          name
        end
      end
    end
  end
end