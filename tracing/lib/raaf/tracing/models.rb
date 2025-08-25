# frozen_string_literal: true

module RAAF
  module Tracing
    # Lazy loading approach for ActiveRecord models
    def self.const_missing(name)
      if (name == :TraceRecord || name == :SpanRecord) && defined?(::ApplicationRecord)
        case name
        when :TraceRecord
          const_set(:TraceRecord, Class.new(::ApplicationRecord) do
            self.table_name = "raaf_tracing_traces"
            
            # Disable JSON symbolization to prevent method aliasing conflicts
            disable_json_symbolization! if respond_to?(:disable_json_symbolization!)
            
            has_many :spans,
              class_name: "RAAF::Tracing::SpanRecord",
              foreign_key: :trace_id,
              primary_key: :trace_id,
              dependent: :destroy
            
            # Cleanup method for old traces
            def self.cleanup_old_traces(older_than: 30.days)
              where("started_at < ?", Time.current - older_than).delete_all
            end
          end)
        when :SpanRecord
          const_set(:SpanRecord, Class.new(::ApplicationRecord) do
            self.table_name = "raaf_tracing_spans"
            
            # Disable JSON symbolization to prevent method aliasing conflicts
            disable_json_symbolization! if respond_to?(:disable_json_symbolization!)
            
            belongs_to :trace,
              class_name: "RAAF::Tracing::TraceRecord",
              foreign_key: :trace_id,
              primary_key: :trace_id
            
            belongs_to :parent,
              class_name: "RAAF::Tracing::SpanRecord",
              foreign_key: :parent_id,
              primary_key: :span_id,
              optional: true
            
            has_many :children,
              class_name: "RAAF::Tracing::SpanRecord",
              foreign_key: :parent_id,
              primary_key: :span_id,
              dependent: :destroy
          end)
        end
      else
        super
      end
    end
  end
end