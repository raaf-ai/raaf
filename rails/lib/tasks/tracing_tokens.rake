# frozen_string_literal: true

namespace :raaf do
  namespace :tracing do
    desc "Copy token counts and model from span attributes into the native columns"
    task backfill_token_columns: :environment do
      dry_run = ENV["DRY_RUN"].present?
      batch_size = (ENV["BATCH"] || 1000).to_i

      span_class = RAAF::Rails::Tracing::SpanRecord
      columns = %i[input_tokens output_tokens total_tokens agent_model]
                .select { |column| span_class.column_names.include?(column.to_s) }

      if columns.empty?
        warn "raaf_tracing_spans has none of the token columns — run the migration that adds them first."
        next
      end

      # Every span is a candidate, not only the ones with a null column: a span
      # written before +total_tokens+ shipped has its input and output filled
      # and its total missing, so "any column is null" and "nothing to do" are
      # not the same question. The comparison below settles it per row, and
      # rows already correct are never written.
      scope = span_class.unscope(:order)
      total = scope.count
      examined = 0
      updated = 0
      unchanged = 0
      no_usage = 0

      puts "Backfilling #{columns.join(', ')} across #{total} spans#{' (dry run)' if dry_run}"

      scope.select(:span_id, :span_attributes, *columns).find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |span|
          examined += 1

          derived = RAAF::Tracing::ActiveRecordProcessor.persistable_token_columns(span.span_attributes)

          if derived.empty?
            no_usage += 1
            next
          end

          changes = derived.reject { |column, value| span.public_send(column) == value }

          if changes.empty?
            unchanged += 1
            next
          end

          # update_columns, so the per-row save callbacks — which recompute the
          # owning trace's status — do not fire thousands of times for a write
          # that cannot change any status.
          span.update_columns(changes) unless dry_run
          updated += 1
        end

        print "\r  examined #{examined}/#{total}"
      end

      puts
      puts "  #{dry_run ? 'would update' : 'updated'}: #{updated}"
      puts "  already correct: #{unchanged}"
      puts "  no usage recorded: #{no_usage}"
    end

    desc "Report how much token and cost data the span table can currently answer for"
    task token_coverage: :environment do
      span_class = RAAF::Rails::Tracing::SpanRecord

      rows = span_class.unscope(:order).group(:kind).pluck(
        :kind,
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(input_tokens)"),
        Arel.sql("COUNT(total_tokens)"),
        Arel.sql("COUNT(agent_model)")
      )

      puts format("%-12<kind>s %8<total>s %8<input>s %8<tokens>s %8<model>s",
                  kind: "kind", total: "spans", input: "input", tokens: "total", model: "model")

      rows.sort_by { |row| -row[1] }.each do |kind, count, input, total_tokens, model|
        puts format("%-12<kind>s %8<total>d %8<input>d %8<tokens>d %8<model>d",
                    kind: kind, total: count, input: input, tokens: total_tokens, model: model)
      end

      unpriced = span_class.unscope(:order).where.not(agent_model: nil)
                           .distinct.pluck(:agent_model)
                           .reject { |model| RAAF::Tracing::SpanUsage.priced?({ model: model }) }

      next if unpriced.empty?

      puts
      puts "Models with no pricing entry (their spans report tokens but no cost):"
      unpriced.sort.each { |model| puts "  #{model}" }
    end
  end
end
