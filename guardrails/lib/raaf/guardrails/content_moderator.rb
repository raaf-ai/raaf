# frozen_string_literal: true

require_relative 'base'

module RAAF
  module Guardrails
    # Moderates content based on configurable categories and thresholds
    class ContentModerator < Base
      # Default content categories with thresholds
      DEFAULT_CATEGORIES = {
        violence: { 
          threshold: 0.8, 
          patterns: [
            /\b(?:violent|violence|attack|assault)\b/i,
            /\b(?:weapon|gun|knife|bomb)\b/i
          ],
          description: 'Content containing violence or violent themes'
        },
        adult_content: { 
          threshold: 0.6, 
          patterns: [
            /\b(?:adult|explicit|nsfw)\s+content\b/i,
            /\b(?:nude|nudity|naked)\b/i
          ],
          description: 'Adult or sexually explicit content'
        },
        gambling: { 
          threshold: 0.7, 
          patterns: [
            /\b(?:gambl(?:e|ing)|bet(?:ting)?|casino|lottery)\b/i,
            /\b(?:poker|blackjack|slots|roulette)\b/i
          ],
          description: 'Gambling-related content'
        },
        medical_advice: { 
          threshold: 0.5, 
          patterns: [
            /\b(?:diagnos(?:is|e)|treatment|prescription|medication)\b/i,
            /\b(?:medical|health)\s+advice\b/i,
            /\b(?:symptom|disease|illness|condition)\b/i
          ],
          description: 'Medical advice or diagnosis'
        },
        financial_advice: { 
          threshold: 0.5, 
          patterns: [
            /\b(?:invest(?:ment)?|stock|trading|portfolio)\s+advice\b/i,
            /\b(?:buy|sell)\s+(?:stock|crypto|bitcoin)\b/i,
            /\bguaranteed\s+(?:return|profit|income)\b/i
          ],
          description: 'Financial investment advice'
        },
        legal_advice: { 
          threshold: 0.6, 
          patterns: [
            /\b(?:legal|lawyer|attorney)\s+advice\b/i,
            /\b(?:sue|lawsuit|litigation)\b/i,
            /\byour\s+(?:legal\s+)?rights\b/i
          ],
          description: 'Legal advice or counsel'
        }
      }.freeze

      attr_reader :categories, :action_mode, :age_appropriate

      def initialize(action: :context_aware, categories: nil, age_appropriate: nil, **options)
        super(action: action, **options)
        @action_mode = action
        @categories = setup_categories(categories)
        @age_appropriate = age_appropriate || default_age_settings
      end

      protected

      def perform_check(content, context)
        violations = []
        
        # Check each category
        @categories.each do |category_name, config|
          score = calculate_category_score(content, config)
          
          if score >= config[:threshold]
            violations << {
              type: category_name,
              score: score,
              threshold: config[:threshold],
              severity: severity_for_category(category_name, score),
              description: config[:description]
            }
          end
        end
        
        # Check age appropriateness if enabled
        if @age_appropriate[:enable]
          age_violations = check_age_appropriateness(content, context)
          violations.concat(age_violations)
        end
        
        return safe_result if violations.empty?
        
        # Determine action based on context and violations
        determined_action = determine_contextual_action(violations, context)
        
        result = violation_result(violations)
        result.instance_variable_set(:@action, determined_action)
        result
      end

      private

      def setup_categories(custom_categories)
        return DEFAULT_CATEGORIES.dup unless custom_categories
        
        # Merge custom categories with defaults
        categories = DEFAULT_CATEGORIES.dup
        
        custom_categories.each do |name, config|
          if categories.key?(name)
            # Update existing category
            categories[name] = categories[name].merge(config)
          else
            # Add new category
            categories[name] = {
              threshold: config[:threshold] || 0.7,
              patterns: config[:patterns] || [],
              description: config[:description] || "Custom category: #{name}"
            }.merge(config)
          end
        end
        
        categories
      end

      def default_age_settings
        {
          enable: false,
          default_age_group: :adult,
          content_ratings: {
            general: { min_age: 0, max_age: 999 },
            teen: { min_age: 13, max_age: 17 },
            adult: { min_age: 18, max_age: 999 }
          }
        }
      end

      def calculate_category_score(content, config)
        return 0.0 unless config[:patterns]
        
        matches = 0
        total_patterns = config[:patterns].size
        
        config[:patterns].each do |pattern|
          matches += 1 if content.match?(pattern)
        end
        
        # Simple scoring: percentage of patterns matched
        return 0.0 if total_patterns == 0
        
        base_score = matches.to_f / total_patterns
        
        # Boost score based on frequency of matches
        frequency_boost = 0
        config[:patterns].each do |pattern|
          frequency_boost += content.scan(pattern).size * 0.1
        end
        
        (base_score + frequency_boost).clamp(0.0, 1.0)
      end

      def severity_for_category(category, score)
        # Special handling for certain categories
        case category
        when :violence, :adult_content
          score >= 0.9 ? :critical : :high
        when :medical_advice, :financial_advice, :legal_advice
          score >= 0.8 ? :high : :medium
        when :gambling
          score >= 0.9 ? :high : :medium
        else
          score >= 0.8 ? :high : score >= 0.5 ? :medium : :low
        end
      end

      def check_age_appropriateness(content, context)
        violations = []
        
        age_group = context[:age_group] || @age_appropriate[:default_age_group]
        age_range = @age_appropriate[:content_ratings][age_group]
        
        return violations unless age_range
        
        # Check for content inappropriate for age group
        if age_group == :general || age_group == :teen
          # Check for adult content
          adult_score = calculate_category_score(content, @categories[:adult_content])
          if adult_score > 0.3
            violations << {
              type: :age_inappropriate,
              age_group: age_group,
              severity: :high,
              description: "Content inappropriate for #{age_group} audience"
            }
          end
        end
        
        if age_group == :general
          # Check for violence
          violence_score = calculate_category_score(content, @categories[:violence])
          if violence_score > 0.5
            violations << {
              type: :age_inappropriate,
              age_group: age_group,
              severity: :medium,
              description: "Violent content inappropriate for general audience"
            }
          end
        end
        
        violations
      end

      def determine_contextual_action(violations, context)
        return @action unless @action_mode == :context_aware
        
        # Collect all violation types and severities
        violation_types = violations.map { |v| v[:type] }
        max_severity = violations.map { |v| v[:severity] }.max_by { |s| severity_score(s) }
        
        # Contextual rules
        if violation_types.include?(:medical_advice) || 
           violation_types.include?(:financial_advice) || 
           violation_types.include?(:legal_advice)
          # For advice categories, flag for review rather than block
          return :flag
        end
        
        if violation_types.include?(:age_inappropriate)
          # Always block age-inappropriate content
          return :block
        end
        
        # Use severity-based action for other categories
        case max_severity
        when :critical
          :block
        when :high
          context[:strict_mode] ? :block : :flag
        when :medium
          :flag
        else
          :log
        end
      end

      def severity_score(severity)
        {
          low: 1,
          medium: 2,
          high: 3,
          critical: 4
        }[severity] || 0
      end
    end
  end
end