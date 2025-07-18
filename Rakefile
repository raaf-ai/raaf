# frozen_string_literal: true

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

desc "Show available tasks"
task :help do
  puts "Available tasks:"
  puts "  rake validate_code    - Validate code examples in guides"
  puts "  rake guides:help      - Show guides-specific help"
end

task default: :help
