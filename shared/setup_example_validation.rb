#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to add example validation to a RAAF gem

require "fileutils"
require "pathname"

def setup_example_validation(gem_dir = Dir.pwd)
  gem_name = detect_gem_name(gem_dir)

  if gem_name.nil?
    puts "❌ No gemspec found in #{gem_dir}"
    puts "   Please run this script from a gem directory"
    exit 1
  end

  puts "🔧 Setting up example validation for: #{gem_name}"
  puts

  # Check if Rakefile exists
  rakefile_path = File.join(gem_dir, "Rakefile")
  unless File.exist?(rakefile_path)
    puts "❌ No Rakefile found. Creating one..."
    create_basic_rakefile(rakefile_path)
  end

  # Update Rakefile
  update_rakefile(rakefile_path)

  # Create examples directory if it doesn't exist
  examples_dir = File.join(gem_dir, "examples")
  unless File.directory?(examples_dir)
    puts "📁 Creating examples directory..."
    FileUtils.mkdir_p(examples_dir)
    create_sample_example(examples_dir, gem_name)
  end

  # Update CI workflow if it exists
  update_ci_workflow(gem_name)

  puts
  puts "✅ Example validation setup complete!"
  puts
  puts "Available rake tasks:"
  puts "  • rake examples:validate       - Validate all examples"
  puts "  • rake examples:validate_test  - Validate in test mode (no API calls)"
  puts "  • rake examples:list          - List all example files"
  puts "  • rake examples:run[file]     - Run a specific example"
  puts
  puts "To test:"
  puts "  bundle exec rake examples:list"
  puts "  bundle exec rake examples:validate_test"
end

def detect_gem_name(gem_dir)
  gemspec_path = Dir.glob(File.join(gem_dir, "*.gemspec")).first
  return nil unless gemspec_path

  File.basename(gemspec_path, ".gemspec").sub(/^raaf-/, "")
end

def create_basic_rakefile(rakefile_path)
  content = <<~RUBY
    # frozen_string_literal: true

    require "bundler/gem_tasks"
    require "rspec/core/rake_task"
    require "rubocop/rake_task"

    RSpec::Core::RakeTask.new(:spec)
    RuboCop::RakeTask.new

    task default: %i[spec rubocop]
  RUBY

  File.write(rakefile_path, content)
  puts "✅ Created basic Rakefile"
end

def update_rakefile(rakefile_path)
  content = File.read(rakefile_path)

  # Check if already configured
  if content.include?("raaf/shared/tasks")
    puts "✅ Rakefile already configured for example validation"
    return
  end

  # Find a good insertion point
  lines = content.lines
  insert_index = find_insertion_point(lines)

  # Add the shared tasks loading code
  shared_tasks_code = <<~RUBY

    # Load shared tasks from the root shared directory
    $LOAD_PATH.unshift(File.expand_path("../shared/lib", __dir__))
    require "raaf/shared/tasks"
    RAAF::Shared::Tasks.load("examples")
  RUBY

  # Also add CI task if not present
  ci_task_code = <<~RUBY

    # CI task
    desc "Run all CI checks (specs, rubocop, and example validation)"
    task ci: [:spec, :rubocop, "examples:validate_test"]
  RUBY

  # Insert shared tasks
  lines.insert(insert_index, shared_tasks_code)

  # Add CI task at the end if not present
  lines << ci_task_code unless content.include?("task ci:")

  File.write(rakefile_path, lines.join)
  puts "✅ Updated Rakefile with example validation tasks"
end

def find_insertion_point(lines)
  # Try to find a good place after the default task
  default_task_index = lines.find_index { |line| line.include?("task default:") }
  return default_task_index + 1 if default_task_index

  # Otherwise, after the requires
  last_require_index = lines.rindex { |line| line.strip.start_with?("require ") }
  return last_require_index + 1 if last_require_index

  # Otherwise, at the beginning after frozen_string_literal
  frozen_index = lines.find_index { |line| line.include?("frozen_string_literal") }
  return frozen_index + 2 if frozen_index

  # Otherwise, at the very beginning
  0
end

def create_sample_example(examples_dir, gem_name)
  example_file = File.join(examples_dir, "basic_example.rb")

  content = <<~RUBY
    #!/usr/bin/env ruby
    # frozen_string_literal: true

    # Basic example for #{gem_name} gem

    require_relative "../lib/raaf-#{gem_name}"

    puts "=== #{gem_name.capitalize} Example ==="
    puts

    # Add your example code here
    # For example:
    # obj = RAAF::#{gem_name.capitalize}::SomeClass.new
    # result = obj.some_method
    # puts "Result: \#{result}"

    puts "✅ Example completed successfully"
  RUBY

  File.write(example_file, content)
  puts "✅ Created sample example: examples/basic_example.rb"
end

def update_ci_workflow(gem_name)
  workflow_path = File.join("..", ".github", "workflows", "#{gem_name}-ci.yml")

  unless File.exist?(workflow_path)
    puts "ℹ️  No CI workflow found for #{gem_name}"
    return
  end

  content = File.read(workflow_path)

  # Check if already using rake task
  if content.include?("rake examples:validate")
    puts "✅ CI workflow already uses rake task for validation"
    return
  end

  # Look for old validation script usage
  if content.include?("scripts/validate_examples.rb")
    updated_content = content.gsub(
      "bundle exec ruby scripts/validate_examples.rb",
      "bundle exec rake examples:validate_test"
    )

    File.write(workflow_path, updated_content)
    puts "✅ Updated CI workflow to use rake task"
  else
    puts "ℹ️  CI workflow doesn't appear to validate examples yet"
    puts "   Add this step to your workflow:"
    puts
    puts "    - name: Validate examples"
    puts "      run: |"
    puts "        cd #{gem_name}"
    puts "        bundle exec rake examples:validate_test"
    puts "      env:"
    puts "        CI: true"
    puts "        RAAF_TEST_MODE: true"
  end
end

# Run the setup if this script is executed directly
setup_example_validation if __FILE__ == $0
