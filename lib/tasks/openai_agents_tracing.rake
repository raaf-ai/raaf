namespace :openai_agents do
  namespace :tracing do
    desc "Clear all traces and spans from the database"
    task clear_all: :environment do
      puts "Clearing all traces and spans..."

      # Delete all spans first (due to foreign key constraints)
      span_count = OpenAIAgents::Tracing::SpanRecord.count
      OpenAIAgents::Tracing::SpanRecord.destroy_all
      puts "Deleted #{span_count} spans"

      # Then delete all traces
      trace_count = OpenAIAgents::Tracing::TraceRecord.count
      OpenAIAgents::Tracing::TraceRecord.destroy_all
      puts "Deleted #{trace_count} traces"

      puts "All traces and spans have been cleared!"
    end

    desc "Show token usage statistics"
    task token_stats: :environment do
      llm_spans = OpenAIAgents::Tracing::SpanRecord.where(kind: "llm")

      total_input_tokens = 0
      total_output_tokens = 0
      spans_with_tokens = 0

      llm_spans.each do |span|
        next unless span.span_attributes&.dig("llm", "usage")

        usage = span.span_attributes["llm"]["usage"]
        next unless usage["prompt_tokens"] || usage["completion_tokens"]

        spans_with_tokens += 1
        total_input_tokens += usage["prompt_tokens"].to_i
        total_output_tokens += usage["completion_tokens"].to_i
      end

      puts "Token Usage Statistics:"
      puts "======================"
      puts "Total LLM spans: #{llm_spans.count}"
      puts "Spans with token data: #{spans_with_tokens}"
      puts "Total input tokens: #{total_input_tokens}"
      puts "Total output tokens: #{total_output_tokens}"
      puts "Total tokens: #{total_input_tokens + total_output_tokens}"
    end
  end
end
