# frozen_string_literal: true

require "bundler"
require "fileutils"
require "shellwords"

# Load guides tasks
Dir.chdir("guides") do
  load "Rakefile"
end

desc "Run guides code validation"
task :validate_code do
  Dir.chdir("guides") do
    Rake::Task["guides:validate_code"].invoke
  end
end

# Load shared tasks
$LOAD_PATH.unshift(File.expand_path("shared/lib", __dir__))
require "raaf/shared/tasks"

# List of all gems in the monorepo
GEMS = %w[
  core
  dsl
  guardrails
  memory
  providers
  tools
  tracing
  rails
].freeze

# Gems with their own RSpec suite, in dependency order: core first, so a break
# there is reported before every downstream gem fails for the same reason.
SPEC_GEMS = %w[
  core
  providers
  tracing
  dsl
  memory
  guardrails
  tools
  eval
  rails
  testing
].freeze

# Run one gem's specs in its own bundle. Each gem has its own Gemfile, so the
# parent's BUNDLE_GEMFILE has to be cleared or every gem resolves against the
# root Gemfile instead of its own.
def run_gem_specs(gem_name, rspec_args = [])
  gem_dir = File.join(__dir__, gem_name)
  return :skipped unless File.directory?(File.join(gem_dir, "spec"))

  ok = Bundler.with_unbundled_env do
    Dir.chdir(gem_dir) do
      system("bundle", "exec", "rspec", *rspec_args)
    end
  end

  ok ? :passed : :failed
end

# ONLY=core,dsl narrows any of the spec tasks to those gems, matching the
# convention the guides tasks already use.
def selected_spec_gems
  requested = ENV["ONLY"].to_s.split(",").map(&:strip).reject(&:empty?)
  return SPEC_GEMS if requested.empty?

  unknown = requested - SPEC_GEMS
  unless unknown.empty?
    abort("❌ Unknown gem(s): #{unknown.join(", ")}\nAvailable: #{SPEC_GEMS.join(", ")}")
  end

  SPEC_GEMS & requested
end

desc "Run the RSpec suite of every gem (ONLY=core,dsl to narrow)"
task :spec do
  results = {}

  selected_spec_gems.each do |gem_name|
    puts "\n#{"=" * 60}"
    puts "Running #{gem_name} specs..."
    puts "=" * 60

    results[gem_name] = run_gem_specs(gem_name)
    puts "⚠️  No spec directory for #{gem_name}" if results[gem_name] == :skipped
  end

  puts "\n#{"=" * 60}"
  puts "SUMMARY"
  puts "=" * 60

  results.each do |gem_name, result|
    icon = { passed: "✅", failed: "❌", skipped: "⚠️ " }.fetch(result)
    puts "  #{icon} #{gem_name}"
  end

  failed = results.select { |_gem, result| result == :failed }.keys
  if failed.empty?
    puts "\n✅ All specs passed!"
  else
    puts "\n❌ Failing gems: #{failed.join(", ")}"
    exit(1)
  end
end

namespace :spec do
  desc "Run a single gem's specs, e.g. rake spec:gem[core] or spec:gem[core,spec/raaf/agent_spec.rb]"
  task :gem, [:gem_name, :rspec_args] do |_t, args|
    gem_name = args[:gem_name]
    unless gem_name
      abort("❌ Please specify a gem name\nUsage: rake spec:gem[core]\nAvailable: #{SPEC_GEMS.join(", ")}")
    end

    unless SPEC_GEMS.include?(gem_name)
      abort("❌ Unknown gem: #{gem_name}\nAvailable: #{SPEC_GEMS.join(", ")}")
    end

    rspec_args = Shellwords.split(args[:rspec_args].to_s)
    case run_gem_specs(gem_name, rspec_args)
    when :skipped then abort("❌ No spec directory for #{gem_name}")
    when :failed then exit(1)
    end
  end

  desc "List the gems with an RSpec suite"
  task :list do
    puts "🧪 Gems with specs:"
    SPEC_GEMS.each do |gem_name|
      count = Dir.glob(File.join(__dir__, gem_name, "spec", "**", "*_spec.rb")).size
      puts format("  %-10s %d spec file(s)", gem_name, count)
    end
  end
end

namespace :code do
  desc "Validate code examples across all gems"
  task :validate do
    failed_gems = []

    GEMS.each do |gem|
      gem_dir = File.join(__dir__, gem)
      next unless File.directory?(gem_dir)

      puts "\n" + ("=" * 60)
      puts "Validating #{gem}..."
      puts "=" * 60

      Dir.chdir(gem_dir) do
        # Check if gem has Rakefile with code:validate task
        if File.exist?("Rakefile") && system("bundle exec rake -T code:validate > /dev/null 2>&1")
          success = system("bundle exec rake code:validate")
          failed_gems << gem unless success
        else
          puts "⚠️  No code:validate task found for #{gem}"
        end
      end
    end

    puts "\n" + ("=" * 60)
    puts "SUMMARY"
    puts "=" * 60

    if failed_gems.empty?
      puts "✅ All gems passed validation!"
    else
      puts "❌ Failed gems: #{failed_gems.join(", ")}"
      exit(1)
    end
  end

  desc "Validate code examples in test mode (no API calls)"
  task :validate_test do
    ENV["RAAF_TEST_MODE"] = "true"
    Rake::Task["code:validate"].invoke
  end

  desc "Validate a specific gem's code examples"
  task :validate_gem, [:gem_name] do |_t, args|
    gem_name = args[:gem_name]
    unless gem_name
      puts "❌ Please specify a gem name"
      puts "Usage: rake code:validate_gem[core]"
      puts "Available gems: #{GEMS.join(", ")}"
      exit(1)
    end

    unless GEMS.include?(gem_name)
      puts "❌ Unknown gem: #{gem_name}"
      puts "Available gems: #{GEMS.join(", ")}"
      exit(1)
    end

    gem_dir = File.join(__dir__, gem_name)
    unless File.directory?(gem_dir)
      puts "❌ Gem directory not found: #{gem_dir}"
      exit(1)
    end

    Dir.chdir(gem_dir) do
      if File.exist?("Rakefile") && system("bundle exec rake -T code:validate > /dev/null 2>&1")
        system("bundle exec rake code:validate")
      else
        puts "❌ No code:validate task found for #{gem_name}"
        exit(1)
      end
    end
  end

  desc "List all gems with code validation"
  task :list_gems do
    puts "📦 Gems with code validation:"
    GEMS.each do |gem|
      gem_dir = File.join(__dir__, gem)
      next unless File.directory?(gem_dir)

      has_validation = Dir.chdir(gem_dir) do
        File.exist?("Rakefile") && system("bundle exec rake -T code:validate > /dev/null 2>&1")
      end

      status = has_validation ? "✅" : "❌"
      puts "  #{status} #{gem}"
    end
  end
end

desc "Show available tasks"
task :help do
  puts "Available tasks:"
  puts "  rake spec                   - Run every gem's specs (ONLY=core,dsl to narrow)"
  puts "  rake spec:gem[core]         - Run a single gem's specs"
  puts "  rake spec:list              - List the gems with an RSpec suite"
  puts "  rake code:validate          - Validate code examples across all gems"
  puts "  rake code:validate_test     - Validate in test mode (no API calls)"
  puts "  rake code:validate_gem[gem] - Validate a specific gem"
  puts "  rake code:list_gems         - List all gems with validation"
  puts "  rake validate_code          - Validate code examples in guides"
  puts "  rake guides:help            - Show guides-specific help"
end

task default: :help
