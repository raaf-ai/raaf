# frozen_string_literal: true

namespace :raaf do
  namespace :continuous_evaluation do
    # Helper to format sampling configuration for display
    def format_sampling(policy)
      case policy.sampling_mode
      when 'percentage'
        "#{policy.sample_rate}% of spans"
      when 'every_n'
        "Every #{policy.sample_every_n}th span"
      when 'all'
        "All spans"
      else
        "Not configured"
      end
    end

    desc "Migrate DSL history configurations to database-backed EvaluationPolicy records"
    task migrate: :environment do
      puts "=" * 80
      puts "RAAF Continuous Evaluation Migration"
      puts "=" * 80
      puts
      puts "This task helps migrate from DSL-based history configuration to"
      puts "database-backed EvaluationPolicy records."
      puts
      puts "Note: The `history do...end` DSL block has been REMOVED (not deprecated)."
      puts "Using it will now raise RAAF::Eval::DeprecatedDSLError."
      puts
      puts "-" * 80
      puts "Scanning for registered evaluators..."
      puts

      # Get all registered evaluators from the registry
      evaluator_names = RAAF::Eval.registered_evaluators

      if evaluator_names.empty?
        puts "[INFO] No evaluators found in the registry."
        puts "       This is normal if evaluators haven't been loaded yet."
        puts "       Ensure your evaluator files are loaded before running this task."
        puts
        puts "To manually create evaluation policies, use the RAAF Dashboard UI or:"
        puts
        puts "  RAAF::Eval::Models::EvaluationPolicy.create!("
        puts "    name: 'my_policy',"
        puts "    enabled: true,"
        puts "    evaluators: ["
        puts "      { name: 'my_evaluator', config: { threshold: 0.85 } }"
        puts "    ],"
        puts "    agent_pattern: 'MyAgent',"
        puts "    sample_rate: 10.0"
        puts "  )"
        puts
      else
        puts "[INFO] Found #{evaluator_names.count} registered evaluators:"
        evaluator_names.each do |name|
          puts "       - #{name}"
        end
        puts
        puts "-" * 80
        puts "Checking for existing policies..."
        puts

        # Check for existing policies
        if defined?(RAAF::Eval::Models::EvaluationPolicy)
          existing_policies = RAAF::Eval::Models::EvaluationPolicy.count
          puts "[INFO] Found #{existing_policies} existing evaluation policies."
          puts
        else
          puts "[WARNING] EvaluationPolicy model not loaded."
          puts "          Ensure migrations have been run."
          puts
        end

        puts "-" * 80
        puts "Creating default policies for evaluators without policies..."
        puts

        created_count = 0
        skipped_count = 0

        evaluator_names.each do |name|
          policy_name = "auto_#{name}"

          if defined?(RAAF::Eval::Models::EvaluationPolicy)
            existing = RAAF::Eval::Models::EvaluationPolicy.find_by(name: policy_name)

            if existing
              puts "[SKIP] Policy '#{policy_name}' already exists (ID: #{existing.id})"
              skipped_count += 1
            else
              begin
                policy = RAAF::Eval::Models::EvaluationPolicy.create!(
                  name: policy_name,
                  description: "Auto-generated policy for #{name} evaluator",
                  enabled: false, # Disabled by default for safety
                  evaluators: [{ name: name.to_s, config: {} }],
                  sample_rate: 0.0, # No sampling by default
                  priority: 10
                )
                puts "[CREATE] Created policy '#{policy_name}' (ID: #{policy.id})"
                created_count += 1
              rescue StandardError => e
                puts "[ERROR] Failed to create policy '#{policy_name}': #{e.message}"
              end
            end
          else
            puts "[SKIP] Cannot create policy - EvaluationPolicy model not available"
            skipped_count += 1
          end
        end

        puts
        puts "-" * 80
        puts "Migration Summary"
        puts "-" * 80
        puts "  Created: #{created_count} policies"
        puts "  Skipped: #{skipped_count} policies"
        puts
        puts "IMPORTANT: Newly created policies are DISABLED by default."
        puts "Enable them via the RAAF Dashboard UI or:"
        puts
        puts "  policy = RAAF::Eval::Models::EvaluationPolicy.find_by(name: 'auto_my_evaluator')"
        puts "  policy.update!(enabled: true, sample_rate: 10.0)"
        puts
      end

      puts "=" * 80
      puts "Migration complete. See docs/CONTINUOUS_EVAL_MIGRATION.md for details."
      puts "=" * 80
    end

    desc "List all evaluation policies"
    task list: :environment do
      puts "=" * 80
      puts "RAAF Evaluation Policies"
      puts "=" * 80
      puts

      unless defined?(RAAF::Eval::Models::EvaluationPolicy)
        puts "[ERROR] EvaluationPolicy model not loaded."
        puts "        Ensure migrations have been run."
        exit 1
      end

      policies = RAAF::Eval::Models::EvaluationPolicy.order(:name)

      if policies.empty?
        puts "[INFO] No evaluation policies found."
        puts "       Create policies via the RAAF Dashboard UI or rake task."
      else
        policies.each do |policy|
          status = policy.active? ? "[ENABLED]" : "[DISABLED]"
          puts "#{status} #{policy.name} (ID: #{policy.id})"
          puts "         Description: #{policy.description || '(none)'}"
          puts "         Evaluators: #{policy.evaluators&.map { |e| e['name'] }&.join(', ') || 'none'}"
          puts "         Sampling: #{format_sampling(policy)}"
          # Format comma-separated agent names as separate items
          agent_names = policy.agent_name.present? ? policy.agent_name.split(",").map(&:strip) : ["*"]
          puts "         Agents: #{agent_names.join(', ')}"
          puts "         Environment: #{policy.environment || 'all'}"
          puts
        end
      end

      puts "=" * 80
    end

    desc "Check for deprecated DSL usage in evaluator files"
    task check_deprecated: :environment do
      puts "=" * 80
      puts "Checking for Deprecated DSL Usage"
      puts "=" * 80
      puts

      # Common locations for evaluator files
      search_paths = [
        Rails.root.join("app", "evaluators"),
        Rails.root.join("lib", "evaluators"),
        Rails.root.join("app", "models", "evaluators")
      ].select(&:exist?)

      if search_paths.empty?
        puts "[INFO] No evaluator directories found."
        puts "       Checked: app/evaluators, lib/evaluators, app/models/evaluators"
        puts
      else
        deprecated_files = []

        search_paths.each do |path|
          Dir.glob(path.join("**", "*.rb")).each do |file|
            content = File.read(file)

            # Check for history DSL usage
            if content.match?(/\bhistory\s+(do|\{|baseline:|last_n:|auto_save:|retention_days:|retention_count:)/)
              deprecated_files << {
                file: file,
                pattern: "history DSL block or options"
              }
            end

            # Check for HistoryDSL class usage
            if content.match?(/HistoryDSL/)
              deprecated_files << {
                file: file,
                pattern: "HistoryDSL class reference"
              }
            end

            # Check for configure_history method
            if content.match?(/configure_history/)
              deprecated_files << {
                file: file,
                pattern: "configure_history method"
              }
            end
          end
        end

        if deprecated_files.empty?
          puts "[OK] No deprecated DSL usage found in evaluator files."
        else
          puts "[WARNING] Found #{deprecated_files.count} files with deprecated DSL usage:"
          puts

          deprecated_files.each do |item|
            puts "  #{item[:file]}"
            puts "    Pattern: #{item[:pattern]}"
            puts
          end

          puts "-" * 80
          puts "To fix these issues:"
          puts "1. Remove history do...end blocks from evaluator definitions"
          puts "2. Create EvaluationPolicy records in the database instead"
          puts "3. See docs/CONTINUOUS_EVAL_MIGRATION.md for migration guide"
          puts
        end
      end

      puts "=" * 80
    end
  end
end
