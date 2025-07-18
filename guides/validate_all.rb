#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive validation script for RAAF guides
# Runs all validation steps in sequence

require_relative 'code_validator'
require 'fileutils'

class GuideValidator
  def initialize
    @errors = []
    @warnings = []
  end

  def run_all_validations
    puts "🔍 Starting comprehensive guide validation..."
    
    validate_markdown_syntax
    validate_code_examples
    validate_guide_structure
    validate_cross_references
    
    print_summary
    
    @errors.empty?
  end

  private

  def validate_markdown_syntax
    puts "\n📝 Validating Markdown syntax..."
    
    result = system("bundle exec rake guides:lint:mdl")
    
    unless result
      @errors << "Markdown syntax validation failed"
      puts "❌ Markdown validation failed"
      return
    end
    
    puts "✅ Markdown syntax validation passed"
  end

  def validate_code_examples
    puts "\n💻 Validating Ruby code examples..."
    
    validator = CodeValidator.new
    code_blocks = validator.extract_code_blocks
    
    puts "Found #{code_blocks.length} Ruby code blocks"
    
    if code_blocks.empty?
      @warnings << "No Ruby code blocks found in guides"
      puts "⚠️  No Ruby code blocks found"
      return
    end
    
    results = validator.validate_code_blocks(code_blocks)
    failed_results = results.select(&:failed?)
    
    if failed_results.any?
      @errors << "#{failed_results.length} code examples failed validation"
      puts "❌ Code validation failed"
      
      # Write detailed results to file
      write_validation_results(failed_results)
    else
      puts "✅ All code examples validated successfully"
    end
  end

  def validate_guide_structure
    puts "\n📚 Validating guide structure..."
    
    # Check for required sections in each guide
    required_sections = {
      'getting_started.md' => ['Introduction', 'Installation', 'First Agent'],
      'core_guide.md' => ['Introduction', 'Agents', 'Runners', 'Tools'],
      'api_reference.md' => ['Classes', 'Methods']
    }
    
    missing_sections = []
    
    required_sections.each do |file, sections|
      file_path = "source/#{file}"
      next unless File.exist?(file_path)
      
      content = File.read(file_path)
      
      sections.each do |section|
        unless content.include?(section)
          missing_sections << "#{file}: Missing '#{section}' section"
        end
      end
    end
    
    if missing_sections.any?
      @warnings.concat(missing_sections)
      puts "⚠️  Some guides missing required sections"
    else
      puts "✅ Guide structure validation passed"
    end
  end

  def validate_cross_references
    puts "\n🔗 Validating cross-references..."
    
    # Check for broken internal links
    broken_links = []
    
    Dir.glob("source/*.md").each do |file|
      content = File.read(file)
      
      # Find internal links [text](file.md) or [text](file.html)
      internal_links = content.scan(/\[([^\]]+)\]\(([^)]+\.(?:md|html))\)/)
      
      internal_links.each do |text, link|
        # Convert to source file path
        source_file = link.gsub('.html', '.md')
        source_path = "source/#{source_file}"
        
        unless File.exist?(source_path)
          broken_links << "#{file}: Broken link to #{link}"
        end
      end
    end
    
    if broken_links.any?
      @errors.concat(broken_links)
      puts "❌ Cross-reference validation failed"
    else
      puts "✅ Cross-reference validation passed"
    end
  end

  def write_validation_results(failed_results)
    File.open("validation-results.txt", "w") do |f|
      f.puts "Code Validation Failures"
      f.puts "=" * 40
      f.puts
      
      failed_results.each do |result|
        f.puts "Location: #{result.code_block.location}"
        f.puts "Error: #{result.error}"
        f.puts "Code:"
        f.puts result.code_block.content.lines.first(5).join
        f.puts "..." if result.code_block.content.lines.length > 5
        f.puts
      end
    end
  end

  def print_summary
    puts "\n" + "=" * 50
    puts "Guide Validation Summary"
    puts "=" * 50
    
    if @errors.empty? && @warnings.empty?
      puts "🎉 All validations passed!"
    else
      puts "Errors: #{@errors.length}"
      puts "Warnings: #{@warnings.length}"
      
      if @errors.any?
        puts "\nErrors:"
        @errors.each { |error| puts "  ❌ #{error}" }
      end
      
      if @warnings.any?
        puts "\nWarnings:"
        @warnings.each { |warning| puts "  ⚠️  #{warning}" }
      end
    end
  end
end

# Run validation if called directly
if __FILE__ == $0
  validator = GuideValidator.new
  success = validator.run_all_validations
  
  exit(success ? 0 : 1)
end