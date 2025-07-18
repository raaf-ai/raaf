#!/usr/bin/env ruby
# frozen_string_literal: true

# Run rubocop and get summary
output = `bundle exec rubocop 2>&1`
lines = output.split("\n")

# Find the summary line
summary_line = lines.find { |line| line.match?(/^\d+ files inspected/) }

if summary_line
  puts "\n✅ RuboCop Summary:"
  puts summary_line

  # Extract offense count
  if summary_line.match(/(\d+) offenses? detected/)
    offense_count = Regexp.last_match(1).to_i
    if offense_count.zero?
      puts "\n🎉 All RuboCop offenses have been fixed!"
    else
      puts "\n⚠️  #{offense_count} offenses remain"
    end
  end
else
  puts "Could not find RuboCop summary"
end
