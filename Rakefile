# frozen_string_literal: true

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

namespace :code do
  desc "Validate code examples across all gems"
  task :validate do
    failed_gems = []
    
    GEMS.each do |gem|
      gem_dir = File.join(__dir__, gem)
      next unless File.directory?(gem_dir)
      
      puts "\n" + "=" * 60
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
    
    puts "\n" + "=" * 60
    puts "SUMMARY"
    puts "=" * 60
    
    if failed_gems.empty?
      puts "✅ All gems passed validation!"
    else
      puts "❌ Failed gems: #{failed_gems.join(', ')}"
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
      puts "Available gems: #{GEMS.join(', ')}"
      exit(1)
    end
    
    unless GEMS.include?(gem_name)
      puts "❌ Unknown gem: #{gem_name}"
      puts "Available gems: #{GEMS.join(', ')}"
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
  puts "  rake code:validate          - Validate code examples across all gems"
  puts "  rake code:validate_test     - Validate in test mode (no API calls)"
  puts "  rake code:validate_gem[gem] - Validate a specific gem"
  puts "  rake code:list_gems         - List all gems with validation"
  puts "  rake validate_code          - Validate code examples in guides"
  puts "  rake guides:help            - Show guides-specific help"
end

task default: :help
