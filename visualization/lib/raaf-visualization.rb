# frozen_string_literal: true

require_relative "raaf/visualization/version"
require_relative "raaf/visualization/chart_generator"
require_relative "raaf/visualization/dashboard_builder"
require_relative "raaf/visualization/analytics_engine"
require_relative "raaf/visualization/data_processor"
require_relative "raaf/visualization/report_generator"
require_relative "raaf/visualization/interactive_charts"
require_relative "raaf/visualization/export_manager"
require_relative "raaf/visualization/theme_manager"
require_relative "raaf/visualization/real_time_visualizer"
require_relative "raaf/visualization/metrics_collector"

module RubyAIAgentsFactory
  ##
  # Data visualization and analytics for Ruby AI Agents Factory
  #
  # The Visualization module provides comprehensive data visualization tools
  # including charts, graphs, dashboards, and analytics for AI agents performance
  # monitoring, conversation analysis, and business intelligence. It enables
  # organizations to gain insights from their AI agent data through rich
  # visualizations and interactive dashboards.
  #
  # Key features:
  # - **Chart Generation** - Create various chart types (line, bar, pie, etc.)
  # - **Dashboard Builder** - Build interactive dashboards with multiple charts
  # - **Analytics Engine** - Advanced analytics and statistical analysis
  # - **Data Processing** - Data transformation and aggregation
  # - **Report Generation** - Automated report creation with visualizations
  # - **Interactive Charts** - Web-based interactive visualizations
  # - **Export Management** - Export charts and reports in various formats
  # - **Theme Management** - Customizable themes and styling
  # - **Real-time Visualization** - Live updating charts and dashboards
  # - **Metrics Collection** - Automated metrics collection and visualization
  #
  # @example Basic chart generation
  #   require 'raaf-visualization'
  #   
  #   # Create chart generator
  #   chart_generator = RubyAIAgentsFactory::Visualization::ChartGenerator.new
  #   
  #   # Generate performance chart
  #   chart = chart_generator.line_chart(
  #     title: "Agent Response Times",
  #     data: {
  #       "Agent A" => [120, 135, 98, 145, 110],
  #       "Agent B" => [145, 120, 130, 125, 140]
  #     },
  #     x_labels: ["Mon", "Tue", "Wed", "Thu", "Fri"]
  #   )
  #   
  #   # Save chart
  #   chart.save("response_times.png")
  #
  # @example Dashboard creation
  #   require 'raaf-visualization'
  #   
  #   # Create dashboard builder
  #   dashboard = RubyAIAgentsFactory::Visualization::DashboardBuilder.new
  #   
  #   # Add charts to dashboard
  #   dashboard.add_chart(:performance_chart, type: :line) do |chart|
  #     chart.title = "Agent Performance"
  #     chart.data = performance_data
  #   end
  #   
  #   dashboard.add_chart(:usage_chart, type: :pie) do |chart|
  #     chart.title = "Agent Usage"
  #     chart.data = usage_data
  #   end
  #   
  #   # Generate dashboard
  #   dashboard.generate("agent_dashboard.html")
  #
  # @example Analytics and reporting
  #   require 'raaf-visualization'
  #   
  #   # Create analytics engine
  #   analytics = RubyAIAgentsFactory::Visualization::AnalyticsEngine.new
  #   
  #   # Analyze conversation data
  #   analysis = analytics.analyze_conversations(conversation_data)
  #   
  #   # Generate report
  #   report_generator = RubyAIAgentsFactory::Visualization::ReportGenerator.new
  #   report = report_generator.generate_performance_report(
  #     data: analysis,
  #     period: "monthly",
  #     format: :pdf
  #   )
  #
  # @example Real-time visualization
  #   require 'raaf-visualization'
  #   
  #   # Create real-time visualizer
  #   visualizer = RubyAIAgentsFactory::Visualization::RealTimeVisualizer.new
  #   
  #   # Start real-time dashboard
  #   visualizer.start_dashboard(port: 3000)
  #   
  #   # Update data in real-time
  #   visualizer.update_metric("response_time", 125)
  #   visualizer.update_metric("active_sessions", 45)
  #
  # @since 1.0.0
  module Visualization
    # Default configuration
    DEFAULT_CONFIG = {
      # Chart settings
      charts: {
        default_theme: :modern,
        default_size: [800, 600],
        default_format: :png,
        font_family: "Arial",
        font_size: 12,
        color_palette: [:blue, :green, :red, :orange, :purple, :brown, :pink, :gray]
      },
      
      # Dashboard settings
      dashboard: {
        default_layout: :grid,
        responsive: true,
        auto_refresh: true,
        refresh_interval: 30,
        max_charts_per_page: 12
      },
      
      # Analytics settings
      analytics: {
        enabled: true,
        statistical_analysis: true,
        trend_analysis: true,
        correlation_analysis: true,
        forecasting: true
      },
      
      # Data processing settings
      data_processing: {
        enabled: true,
        caching: true,
        aggregation: true,
        filtering: true,
        sampling: true
      },
      
      # Report settings
      reports: {
        enabled: true,
        formats: [:pdf, :html, :csv, :json],
        templates: [:executive, :technical, :summary],
        auto_generation: true,
        scheduling: true
      },
      
      # Interactive charts settings
      interactive_charts: {
        enabled: true,
        web_server: true,
        port: 3000,
        real_time_updates: true,
        user_interactions: true
      },
      
      # Export settings
      export: {
        enabled: true,
        formats: [:png, :jpg, :svg, :pdf, :html],
        compression: true,
        watermark: false,
        batch_export: true
      },
      
      # Theme settings
      themes: {
        enabled: true,
        custom_themes: true,
        dark_mode: true,
        responsive_design: true,
        accessibility: true
      },
      
      # Real-time settings
      real_time: {
        enabled: true,
        websocket_support: true,
        update_frequency: 1000,
        buffer_size: 1000,
        compression: true
      },
      
      # Metrics collection settings
      metrics: {
        enabled: true,
        auto_collection: true,
        retention_days: 90,
        aggregation_levels: [:minute, :hour, :day, :week, :month],
        custom_metrics: true
      }
    }.freeze

    class << self
      # @return [Hash] Current configuration
      attr_accessor :config

      ##
      # Configure visualization settings
      #
      # @param options [Hash] Configuration options
      # @yield [config] Configuration block
      #
      # @example Configure visualization
      #   RubyAIAgentsFactory::Visualization.configure do |config|
      #     config.charts.default_theme = :dark
      #     config.dashboard.auto_refresh = true
      #     config.analytics.forecasting = true
      #   end
      #
      def configure
        @config ||= deep_dup(DEFAULT_CONFIG)
        yield @config if block_given?
        @config
      end

      ##
      # Get current configuration
      #
      # @return [Hash] Current configuration
      def config
        @config ||= deep_dup(DEFAULT_CONFIG)
      end

      ##
      # Create chart generator
      #
      # @param options [Hash] Chart generator options
      # @return [ChartGenerator] Chart generator instance
      def create_chart_generator(**options)
        ChartGenerator.new(**config[:charts].merge(options))
      end

      ##
      # Create dashboard builder
      #
      # @param options [Hash] Dashboard builder options
      # @return [DashboardBuilder] Dashboard builder instance
      def create_dashboard_builder(**options)
        DashboardBuilder.new(**config[:dashboard].merge(options))
      end

      ##
      # Create analytics engine
      #
      # @param options [Hash] Analytics engine options
      # @return [AnalyticsEngine] Analytics engine instance
      def create_analytics_engine(**options)
        AnalyticsEngine.new(**config[:analytics].merge(options))
      end

      ##
      # Create data processor
      #
      # @param options [Hash] Data processor options
      # @return [DataProcessor] Data processor instance
      def create_data_processor(**options)
        DataProcessor.new(**config[:data_processing].merge(options))
      end

      ##
      # Create report generator
      #
      # @param options [Hash] Report generator options
      # @return [ReportGenerator] Report generator instance
      def create_report_generator(**options)
        ReportGenerator.new(**config[:reports].merge(options))
      end

      ##
      # Create interactive charts
      #
      # @param options [Hash] Interactive charts options
      # @return [InteractiveCharts] Interactive charts instance
      def create_interactive_charts(**options)
        InteractiveCharts.new(**config[:interactive_charts].merge(options))
      end

      ##
      # Create export manager
      #
      # @param options [Hash] Export manager options
      # @return [ExportManager] Export manager instance
      def create_export_manager(**options)
        ExportManager.new(**config[:export].merge(options))
      end

      ##
      # Create theme manager
      #
      # @param options [Hash] Theme manager options
      # @return [ThemeManager] Theme manager instance
      def create_theme_manager(**options)
        ThemeManager.new(**config[:themes].merge(options))
      end

      ##
      # Create real-time visualizer
      #
      # @param options [Hash] Real-time visualizer options
      # @return [RealTimeVisualizer] Real-time visualizer instance
      def create_real_time_visualizer(**options)
        RealTimeVisualizer.new(**config[:real_time].merge(options))
      end

      ##
      # Create metrics collector
      #
      # @param options [Hash] Metrics collector options
      # @return [MetricsCollector] Metrics collector instance
      def create_metrics_collector(**options)
        MetricsCollector.new(**config[:metrics].merge(options))
      end

      ##
      # Quick chart creation
      #
      # @param type [Symbol] Chart type
      # @param data [Hash] Chart data
      # @param options [Hash] Chart options
      # @return [Chart] Generated chart
      def quick_chart(type, data, **options)
        generator = create_chart_generator
        
        case type
        when :line
          generator.line_chart(data: data, **options)
        when :bar
          generator.bar_chart(data: data, **options)
        when :pie
          generator.pie_chart(data: data, **options)
        when :scatter
          generator.scatter_chart(data: data, **options)
        when :area
          generator.area_chart(data: data, **options)
        when :histogram
          generator.histogram(data: data, **options)
        else
          raise ArgumentError, "Unsupported chart type: #{type}"
        end
      end

      ##
      # Generate agent performance dashboard
      #
      # @param agents [Array<Agent>] Agents to include
      # @param options [Hash] Dashboard options
      # @return [Dashboard] Generated dashboard
      def generate_agent_dashboard(agents, **options)
        dashboard = create_dashboard_builder
        analytics = create_analytics_engine
        
        # Collect agent data
        agent_data = agents.map do |agent|
          {
            name: agent.name,
            performance: analytics.analyze_agent_performance(agent),
            usage: analytics.analyze_agent_usage(agent),
            conversations: analytics.analyze_agent_conversations(agent)
          }
        end
        
        # Add performance chart
        dashboard.add_chart(:performance, type: :line) do |chart|
          chart.title = "Agent Performance Over Time"
          chart.data = agent_data.each_with_object({}) do |data, hash|
            hash[data[:name]] = data[:performance][:response_times]
          end
        end
        
        # Add usage chart
        dashboard.add_chart(:usage, type: :pie) do |chart|
          chart.title = "Agent Usage Distribution"
          chart.data = agent_data.each_with_object({}) do |data, hash|
            hash[data[:name]] = data[:usage][:total_requests]
          end
        end
        
        # Add conversation quality chart
        dashboard.add_chart(:quality, type: :bar) do |chart|
          chart.title = "Conversation Quality Metrics"
          chart.data = agent_data.each_with_object({}) do |data, hash|
            hash[data[:name]] = data[:conversations][:quality_score]
          end
        end
        
        dashboard.generate(**options)
      end

      ##
      # Generate performance report
      #
      # @param data [Hash] Performance data
      # @param options [Hash] Report options
      # @return [String] Generated report
      def generate_performance_report(data, **options)
        report_generator = create_report_generator
        analytics = create_analytics_engine
        
        # Analyze data
        analysis = analytics.analyze_performance_data(data)
        
        # Generate report
        report_generator.generate_report(
          title: "Agent Performance Report",
          data: analysis,
          **options
        )
      end

      ##
      # Start real-time monitoring
      #
      # @param agents [Array<Agent>] Agents to monitor
      # @param options [Hash] Monitoring options
      # @return [RealTimeVisualizer] Real-time visualizer
      def start_real_time_monitoring(agents, **options)
        visualizer = create_real_time_visualizer
        metrics_collector = create_metrics_collector
        
        # Start collecting metrics
        metrics_collector.start_collection(agents)
        
        # Start real-time visualization
        visualizer.start_dashboard(**options)
        
        # Set up metric updates
        metrics_collector.on_metric_update do |metric_name, value, agent|
          visualizer.update_metric("#{agent.name}_#{metric_name}", value)
        end
        
        visualizer
      end

      ##
      # Export visualization data
      #
      # @param data [Hash] Data to export
      # @param format [Symbol] Export format
      # @param options [Hash] Export options
      # @return [String] Exported data
      def export_data(data, format, **options)
        export_manager = create_export_manager
        export_manager.export(data, format, **options)
      end

      ##
      # Get visualization statistics
      #
      # @return [Hash] Visualization statistics
      def statistics
        {
          charts_generated: ChartGenerator.charts_generated,
          dashboards_created: DashboardBuilder.dashboards_created,
          reports_generated: ReportGenerator.reports_generated,
          real_time_sessions: RealTimeVisualizer.active_sessions,
          metrics_collected: MetricsCollector.total_metrics
        }
      end

      ##
      # Create theme
      #
      # @param name [String] Theme name
      # @param options [Hash] Theme options
      # @return [Theme] Created theme
      def create_theme(name, **options)
        theme_manager = create_theme_manager
        theme_manager.create_theme(name, **options)
      end

      ##
      # Apply theme
      #
      # @param theme_name [String] Theme name
      def apply_theme(theme_name)
        theme_manager = create_theme_manager
        theme_manager.apply_theme(theme_name)
        
        # Update default configuration
        @config[:charts][:default_theme] = theme_name
      end

      ##
      # Generate sample data
      #
      # @param type [Symbol] Data type
      # @param size [Integer] Data size
      # @return [Hash] Sample data
      def generate_sample_data(type, size = 100)
        case type
        when :time_series
          generate_time_series_data(size)
        when :categorical
          generate_categorical_data(size)
        when :numerical
          generate_numerical_data(size)
        when :multi_dimensional
          generate_multi_dimensional_data(size)
        else
          raise ArgumentError, "Unsupported data type: #{type}"
        end
      end

      ##
      # Validate visualization data
      #
      # @param data [Hash] Data to validate
      # @return [Array<String>] Validation errors
      def validate_data(data)
        errors = []
        
        # Check data structure
        unless data.is_a?(Hash)
          errors << "Data must be a Hash"
          return errors
        end
        
        # Check for required fields
        if data.empty?
          errors << "Data cannot be empty"
        end
        
        # Check data types
        data.each do |key, value|
          unless value.is_a?(Array) || value.is_a?(Numeric)
            errors << "Invalid data type for key '#{key}': #{value.class}"
          end
        end
        
        errors
      end

      ##
      # Clean up visualization resources
      #
      def cleanup
        # Clean up temporary files
        FileUtils.rm_rf(Dir.glob("/tmp/raaf_viz_*"))
        
        # Stop real-time services
        RealTimeVisualizer.stop_all_sessions
        
        # Clear caches
        DataProcessor.clear_cache
        MetricsCollector.clear_cache
      end

      private

      def deep_dup(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key] = value.is_a?(Hash) ? deep_dup(value) : value.dup
        end
      rescue TypeError
        hash
      end

      def generate_time_series_data(size)
        base_time = Time.current - size.hours
        
        {
          "Series A" => (0...size).map { |i| [base_time + i.hours, rand(50..150)] },
          "Series B" => (0...size).map { |i| [base_time + i.hours, rand(75..125)] }
        }
      end

      def generate_categorical_data(size)
        categories = ["Category A", "Category B", "Category C", "Category D", "Category E"]
        
        categories.each_with_object({}) do |category, hash|
          hash[category] = rand(10..100)
        end
      end

      def generate_numerical_data(size)
        {
          "Dataset" => (0...size).map { rand(1..100) }
        }
      end

      def generate_multi_dimensional_data(size)
        {
          x: (0...size).map { rand(1..100) },
          y: (0...size).map { rand(1..100) },
          z: (0...size).map { rand(1..100) }
        }
      end
    end
  end
end