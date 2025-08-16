# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'

RSpec.describe 'Tool Performance Benchmarks', type: :performance do
  let(:test_tool_class) do
    Class.new do
      include RAAF::DSL::Tools::ConventionOverConfiguration
      
      def self.name
        'TestTool'
      end
      
      def call(query:, limit: 10, filters: {})
        { results: ["item1", "item2"], query: query, limit: limit }
      end
    end
  end

  let(:complex_tool_class) do
    Class.new do
      include RAAF::DSL::Tools::ConventionOverConfiguration
      
      def self.name
        'ComplexSearchTool'
      end
      
      def call(
        query:,
        limit: 10,
        offset: 0,
        sort_by: "relevance",
        filters: {},
        include_metadata: true,
        format: "json",
        timeout: 30
      )
        {
          results: (1..limit).map { |i| "result_#{i}" },
          metadata: include_metadata ? { total: 100, query_time: 0.5 } : nil
        }
      end
    end
  end

  describe 'Method Generation Performance' do
    it 'benchmarks cached vs uncached method generation' do
      # Ensure tool is not cached initially
      test_tool_class.invalidate_cache! if test_tool_class.respond_to?(:invalidate_cache!)
      
      benchmark_results = test_tool_class.benchmark_method_generation(iterations: 1000)
      
      expect(benchmark_results).to include(:cached_access, :uncached_generation, :performance_ratio)
      expect(benchmark_results[:performance_ratio]).to be > 10.0 # Cached should be at least 10x faster
      
      puts "\nMethod Generation Benchmark Results:"
      puts "Cached access time: #{benchmark_results[:cached_access].total.round(6)}s"
      puts "Uncached generation time: #{benchmark_results[:uncached_generation].total.round(6)}s"
      puts "Performance ratio: #{benchmark_results[:performance_ratio].round(2)}x faster"
    end

    it 'verifies zero runtime overhead for generated methods' do
      # Warm up cache
      test_tool_class.cached_tool_definition
      
      # Benchmark method calls
      cached_time = Benchmark.measure do
        1000.times { test_tool_class.tool_name }
      end
      
      # Compare with simple method call
      simple_method_time = Benchmark.measure do
        1000.times { "test_tool" }
      end
      
      # Cached method should be nearly as fast as simple string return
      overhead_ratio = cached_time.total / simple_method_time.total
      expect(overhead_ratio).to be < 2.0 # Less than 2x overhead
      
      puts "\nRuntime Overhead Test:"
      puts "Cached method calls: #{cached_time.total.round(6)}s"
      puts "Simple string return: #{simple_method_time.total.round(6)}s"
      puts "Overhead ratio: #{overhead_ratio.round(2)}x"
    end
  end

  describe 'Tool Discovery Performance' do
    before do
      # Clear registry for clean testing
      RAAF::DSL::Tools::ToolRegistry.clear!
    end

    it 'benchmarks tool discovery performance' do
      # Register some tools
      RAAF::DSL::Tools::ToolRegistry.register(:test_tool, test_tool_class)
      RAAF::DSL::Tools::ToolRegistry.register(:complex_search, complex_tool_class)
      
      # Benchmark lookups
      discovery_time = Benchmark.measure do
        1000.times do
          RAAF::DSL::Tools::ToolRegistry.get(:test_tool)
          RAAF::DSL::Tools::ToolRegistry.get(:complex_search)
        end
      end
      
      # Should be very fast for registered tools
      expect(discovery_time.total).to be < 0.1 # Under 100ms for 1000 lookups
      
      puts "\nTool Discovery Performance:"
      puts "1000 tool lookups: #{discovery_time.total.round(6)}s"
      puts "Average per lookup: #{(discovery_time.total / 1000 * 1000000).round(2)}μs"
    end

    it 'measures auto-discovery performance' do
      # Force auto-discovery
      discovery_time = Benchmark.measure do
        RAAF::DSL::Tools::ToolRegistry.auto_discover_tools(force: true)
      end
      
      puts "\nAuto-discovery Performance:"
      puts "Full auto-discovery: #{discovery_time.total.round(6)}s"
      
      # Should complete reasonably quickly
      expect(discovery_time.total).to be < 1.0 # Under 1 second
    end
  end

  describe 'Parameter Processing Performance' do
    let(:tool_instance) { test_tool_class.new }
    let(:complex_tool_instance) { complex_tool_class.new }

    it 'benchmarks parameter processing with caching' do
      params = { query: "test", limit: 5, filters: { type: "article" } }
      
      # Benchmark with caching
      cached_time = Benchmark.measure do
        100.times do
          if tool_instance.respond_to?(:process_parameters_cached)
            tool_instance.process_parameters_cached(params)
          end
        end
      end
      
      # Benchmark without caching  
      uncached_time = Benchmark.measure do
        100.times do
          if tool_instance.respond_to?(:process_parameters_uncached, true)
            tool_instance.send(:process_parameters_uncached, params)
          end
        end
      end
      
      if cached_time.total > 0 && uncached_time.total > 0
        performance_ratio = uncached_time.total / cached_time.total
        expect(performance_ratio).to be > 1.0 # Cached should be faster
        
        puts "\nParameter Processing Performance:"
        puts "Cached processing: #{cached_time.total.round(6)}s"
        puts "Uncached processing: #{uncached_time.total.round(6)}s"
        puts "Performance ratio: #{performance_ratio.round(2)}x faster"
      end
    end

    it 'validates complex parameter schemas are generated efficiently' do
      schema_time = Benchmark.measure do
        100.times { complex_tool_class.parameter_schema }
      end
      
      # Should be very fast due to caching
      expect(schema_time.total).to be < 0.01 # Under 10ms for 100 calls
      
      puts "\nComplex Schema Generation:"
      puts "100 schema generations: #{schema_time.total.round(6)}s"
      puts "Average per generation: #{(schema_time.total / 100 * 1000000).round(2)}μs"
    end
  end

  describe 'Memory Usage' do
    it 'monitors cache memory usage' do
      # Generate some cached data
      10.times do |i|
        tool_class = Class.new do
          include RAAF::DSL::Tools::ConventionOverConfiguration
          
          define_singleton_method(:name) { "TestTool#{i}" }
          
          def call(query:)
            { result: query }
          end
        end
        
        # Trigger metadata generation
        tool_class.tool_name
        tool_class.tool_description
        tool_class.parameter_schema
      end
      
      if defined?(RAAF::DSL::Tools::PerformanceOptimizer)
        stats = RAAF::DSL::Tools::PerformanceOptimizer.global_cache_stats
        
        puts "\nMemory Usage Stats:"
        puts "Class cache entries: #{stats[:class_cache_size]}"
        puts "Instance cache entries: #{stats[:instance_cache_size]}"
        puts "Estimated memory usage: #{stats[:total_memory_usage]} bytes"
        
        # Memory usage should be reasonable
        expect(stats[:total_memory_usage]).to be < 1_000_000 # Under 1MB
      end
    end
  end

  describe 'Regression Tests' do
    it 'ensures performance optimizations maintain functionality' do
      # Test basic functionality still works
      expect(test_tool_class.tool_name).to eq('test_tool')
      expect(test_tool_class.tool_description).to include('test tool')
      
      schema = test_tool_class.parameter_schema
      expect(schema).to include(:type, :properties, :required)
      expect(schema[:properties]).to include('query', 'limit', 'filters')
      
      # Test tool definition generation
      definition = test_tool_class.cached_tool_definition
      expect(definition).to include(:type, :function)
      expect(definition[:function]).to include(:name, :description, :parameters)
    end

    it 'validates performance with realistic workload' do
      # Simulate realistic agent initialization
      tool_names = [:search, :process, :analyze, :report, :export]
      
      initialization_time = Benchmark.measure do
        100.times do
          # Simulate what happens during agent initialization
          tool_names.each do |name|
            begin
              RAAF::DSL::Tools::ToolRegistry.get(name, strict: false)
            rescue
              # Ignore errors for non-existent tools
            end
          end
        end
      end
      
      # Should handle realistic workload efficiently
      expect(initialization_time.total).to be < 0.5 # Under 500ms
      
      puts "\nRealistic Workload Performance:"
      puts "100 agent initializations: #{initialization_time.total.round(6)}s"
      puts "Average per initialization: #{(initialization_time.total / 100 * 1000).round(2)}ms"
    end
  end

  describe 'Comparative Performance' do
    it 'compares explicit vs generated method definitions' do
      # Explicit tool definition
      explicit_tool = Class.new do
        def self.tool_name
          "explicit_tool"
        end
        
        def self.tool_description
          "Explicitly defined tool"
        end
        
        def self.parameter_schema
          {
            type: "object",
            properties: {
              "query" => { type: "string", description: "Search query" },
              "limit" => { type: "integer", description: "Result limit" }
            },
            required: ["query"]
          }
        end
      end
      
      # Generated tool definition
      generated_tool = Class.new do
        include RAAF::DSL::Tools::ConventionOverConfiguration
        
        def self.name
          'GeneratedTool'
        end
        
        def call(query:, limit: 10)
          { results: [] }
        end
      end
      
      # Benchmark both approaches
      explicit_time = Benchmark.measure do
        1000.times do
          explicit_tool.tool_name
          explicit_tool.tool_description
          explicit_tool.parameter_schema
        end
      end
      
      generated_time = Benchmark.measure do
        1000.times do
          generated_tool.tool_name
          generated_tool.tool_description
          generated_tool.parameter_schema
        end
      end
      
      puts "\nExplicit vs Generated Performance:"
      puts "Explicit definitions: #{explicit_time.total.round(6)}s"
      puts "Generated definitions: #{generated_time.total.round(6)}s"
      
      # Generated should be competitive with explicit
      performance_ratio = generated_time.total / explicit_time.total
      expect(performance_ratio).to be < 3.0 # Generated should be within 3x of explicit
    end
  end
end