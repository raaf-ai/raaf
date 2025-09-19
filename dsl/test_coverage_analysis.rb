# frozen_string_literal: true

# Test Coverage Analysis for RAAF DSL
# Analyzes implementation files and their corresponding test files

require 'pathname'

class TestCoverageAnalysis
  BASE_DIR = "/Users/hajee/Enterprise Modules Dropbox/Bert Hajee/enterprisemodules/work/prospect_radar/vendor/local_gems/raaf/dsl"
  LIB_DIR = File.join(BASE_DIR, "lib")
  SPEC_DIR = File.join(BASE_DIR, "spec")

  def self.run
    new.run
  end

  def run
    puts "=== RAAF DSL Test Coverage Analysis ==="
    puts

    implementation_files = find_implementation_files
    spec_files = find_spec_files

    puts "📊 Current Statistics:"
    puts "  Implementation files: #{implementation_files.size}"
    puts "  Spec files: #{spec_files.size}"
    puts

    analyze_coverage(implementation_files, spec_files)
  end

  private

  def find_implementation_files
    Dir.glob("#{LIB_DIR}/**/*.rb").map do |file|
      relative_path = Pathname.new(file).relative_path_from(Pathname.new(LIB_DIR)).to_s
      {
        full_path: file,
        relative_path: relative_path,
        expected_spec_path: convert_to_spec_path(relative_path),
        has_actual_code: has_actual_code?(file)
      }
    end.select { |f| f[:has_actual_code] }
  end

  def find_spec_files
    Dir.glob("#{SPEC_DIR}/**/*_spec.rb").map do |file|
      relative_path = Pathname.new(file).relative_path_from(Pathname.new(SPEC_DIR)).to_s
      {
        full_path: file,
        relative_path: relative_path,
        corresponding_lib_path: convert_to_lib_path(relative_path)
      }
    end
  end

  def convert_to_spec_path(lib_relative_path)
    # Convert lib/raaf/dsl/agent.rb to raaf/dsl/agent_spec.rb
    base_name = File.basename(lib_relative_path, ".rb")
    dir_name = File.dirname(lib_relative_path)
    "#{dir_name}/#{base_name}_spec.rb"
  end

  def convert_to_lib_path(spec_relative_path)
    # Convert raaf/dsl/agent_spec.rb to raaf/dsl/agent.rb
    base_name = File.basename(spec_relative_path, "_spec.rb")
    dir_name = File.dirname(spec_relative_path)
    "#{dir_name}/#{base_name}.rb"
  end

  def has_actual_code?(file_path)
    # Check if the file has actual code (not just requires/comments)
    content = File.read(file_path)

    # Remove comments and requires
    lines = content.lines.reject do |line|
      stripped = line.strip
      stripped.empty? ||
      stripped.start_with?('#') ||
      stripped.start_with?('require') ||
      stripped.start_with?('require_relative')
    end

    # Check if there's meaningful code beyond basic module/class declarations
    meaningful_lines = lines.select do |line|
      stripped = line.strip
      !stripped.empty? &&
      !stripped.match?(/^\s*(module|class|end)\s*$/) &&
      !stripped.match?(/^\s*extend\s+/) &&
      !stripped.match?(/^\s*include\s+/)
    end

    meaningful_lines.size > 2 # More than just opening/closing
  end

  def analyze_coverage(implementation_files, spec_files)
    existing_specs = spec_files.map { |f| f[:relative_path] }.to_set
    existing_lib_files = implementation_files.map { |f| f[:relative_path] }.to_set

    # Find missing spec files
    missing_specs = implementation_files.reject do |impl_file|
      existing_specs.include?(impl_file[:expected_spec_path])
    end

    # Find orphaned spec files
    orphaned_specs = spec_files.reject do |spec_file|
      # Skip helper files and support files
      next true if spec_file[:relative_path].include?('/support/') ||
                  spec_file[:relative_path].include?('_helper.rb') ||
                  spec_file[:relative_path] == 'spec_helper.rb'

      existing_lib_files.include?(spec_file[:corresponding_lib_path])
    end

    puts "🔍 Coverage Analysis Results:"
    puts "  Missing spec files: #{missing_specs.size}"
    puts "  Orphaned spec files: #{orphaned_specs.size}"
    puts

    if missing_specs.any?
      puts "❌ Missing Spec Files:"
      missing_specs.each do |file|
        puts "  #{file[:relative_path]} → #{file[:expected_spec_path]}"
      end
      puts
    end

    if orphaned_specs.any?
      puts "🗑️  Orphaned Spec Files:"
      orphaned_specs.each do |file|
        puts "  #{file[:relative_path]} (no corresponding lib file: #{file[:corresponding_lib_path]})"
      end
      puts
    end

    # Store results for further processing
    @missing_specs = missing_specs
    @orphaned_specs = orphaned_specs
    @implementation_files = implementation_files
    @spec_files = spec_files

    puts "📋 Summary:"
    puts "  Total implementation files with code: #{implementation_files.size}"
    puts "  Total spec files (excluding helpers): #{spec_files.reject { |f| f[:relative_path].include?('/support/') || f[:relative_path].include?('_helper.rb') || f[:relative_path] == 'spec_helper.rb' }.size}"
    puts "  Coverage ratio: #{((implementation_files.size - missing_specs.size).to_f / implementation_files.size * 100).round(1)}%"
    puts
  end

  attr_reader :missing_specs, :orphaned_specs, :implementation_files, :spec_files
end

# Run the analysis
if __FILE__ == $0
  TestCoverageAnalysis.run
end