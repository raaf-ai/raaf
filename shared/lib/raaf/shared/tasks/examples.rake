# frozen_string_literal: true

require_relative "../example_validator"
require "shellwords"

namespace :examples do
  desc "Validate all examples in this gem"
  task :validate do
    # Determine gem name and directory
    gem_dir = Rake.original_dir
    gemspec_path = Dir.glob(File.join(gem_dir, "*.gemspec")).first
    
    unless gemspec_path
      puts "❌ No gemspec found in #{gem_dir}"
      exit(1)
    end
    
    gem_name = File.basename(gemspec_path, ".gemspec").sub(/^raaf-/, "")
    
    # Configure validator options based on gem
    options = configure_validator_options(gem_name)
    
    # Run validator
    validator = RAAF::Shared::ExampleValidator.new(gem_name, gem_dir, options)
    exit_code = validator.run
    
    exit(exit_code)
  end
  
  desc "Validate examples with test mode (no real API calls)"
  task :validate_test do
    ENV["RAAF_TEST_MODE"] = "true"
    Rake::Task["examples:validate"].invoke
  end
  
  desc "Validate only syntax of examples"
  task :validate_syntax do
    gem_dir = Rake.original_dir
    gemspec_path = Dir.glob(File.join(gem_dir, "*.gemspec")).first
    gem_name = File.basename(gemspec_path, ".gemspec").sub(/^raaf-/, "")
    
    options = configure_validator_options(gem_name)
    options[:syntax_only_files] = Dir.glob(File.join(gem_dir, "examples", "*.rb")).map { |f| File.basename(f) }
    
    validator = RAAF::Shared::ExampleValidator.new(gem_name, gem_dir, options)
    exit_code = validator.run
    
    exit(exit_code)
  end
  
  desc "List all example files"
  task :list do
    gem_dir = Rake.original_dir
    examples_dir = File.join(gem_dir, "examples")
    
    if File.directory?(examples_dir)
      example_files = Dir.glob(File.join(examples_dir, "*.rb")).sort
      puts "📁 Example files in #{File.basename(gem_dir)}:"
      example_files.each do |file|
        puts "  • #{File.basename(file)}"
      end
      puts "\nTotal: #{example_files.length} examples"
    else
      puts "ℹ️  No examples directory found"
    end
  end
  
  desc "Run a specific example file"
  task :run, [:filename] do |_t, args|
    unless args[:filename]
      puts "❌ Please specify an example filename"
      puts "Usage: rake examples:run[example_name.rb]"
      exit(1)
    end
    
    gem_dir = Rake.original_dir
    example_path = File.join(gem_dir, "examples", args[:filename])
    
    unless File.exist?(example_path)
      puts "❌ Example file not found: #{args[:filename]}"
      exit(1)
    end
    
    puts "🏃 Running #{args[:filename]}..."
    system("bundle exec ruby #{Shellwords.escape(example_path)}")
  end
end

# Helper method to configure validator options per gem
def configure_validator_options(gem_name)
  options = {
    # Default options for all gems
    required_env: ["OPENAI_API_KEY"],
    validate_readme: true,
    success_patterns: [
      /Created agent:/i,
      /=== .* Example/i,
      /Successfully/i,
      /Completed/i,
      /✓/
    ]
  }
  
  # Gem-specific configurations
  case gem_name
  when "dsl"
    options.merge!({
      required_env: ["OPENAI_API_KEY", "TAVILY_API_KEY"],
      skip_files: [
        # Add any DSL-specific files to skip
      ],
      success_patterns: options[:success_patterns] + [
        /Agent built successfully/i,
        /Tool built successfully/i,
        /Prompt rendered/i
      ]
    })
    
  when "core"
    options.merge!({
      success_patterns: options[:success_patterns] + [
        /Agent created/i,
        /Runner initialized/i,
        /Conversation started/i
      ]
    })
    
  when "tools"
    options.merge!({
      required_env: ["OPENAI_API_KEY", "TAVILY_API_KEY"],
      success_patterns: options[:success_patterns] + [
        /Tool registered/i,
        /Tool executed/i,
        /Search results/i
      ]
    })
    
  when "tracing"
    options.merge!({
      success_patterns: options[:success_patterns] + [
        /Span created/i,
        /Trace exported/i,
        /Processor registered/i
      ]
    })
    
  when "memory"
    options.merge!({
      success_patterns: options[:success_patterns] + [
        /Memory stored/i,
        /Memory retrieved/i,
        /Vector stored/i
      ]
    })
    
  when "guardrails"
    options.merge!({
      success_patterns: options[:success_patterns] + [
        /Filter applied/i,
        /Content validated/i,
        /Rule matched/i
      ]
    })
    
  when "providers"
    options.merge!({
      required_env: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY"],
      success_patterns: options[:success_patterns] + [
        /Provider initialized/i,
        /Model loaded/i,
        /Response generated/i
      ]
    })
    
  when "rails"
    options.merge!({
      success_patterns: options[:success_patterns] + [
        /Rails initialized/i,
        /Controller created/i,
        /Route added/i
      ]
    })
    
  when "streaming"
    options.merge!({
      success_patterns: options[:success_patterns] + [
        /Stream started/i,
        /Chunk received/i,
        /Stream completed/i
      ]
    })
  end
  
  options
end

# Add shorthand tasks at top level
desc "Validate examples (alias for examples:validate)"
task validate_examples: "examples:validate"

desc "Validate examples in test mode (alias for examples:validate_test)"
task validate_examples_test: "examples:validate_test"