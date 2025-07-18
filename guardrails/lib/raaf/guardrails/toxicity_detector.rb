# frozen_string_literal: true

module RAAF
  module Guardrails
    ##
    # Toxicity detection for content validation
    #
    # Detects toxic, hateful, offensive, or otherwise harmful content
    # using multiple detection methods including keyword matching,
    # machine learning models, and external APIs.
    #
    class ToxicityDetector
      include RAAF::Logging

      # @return [Float] Toxicity threshold (0.0-1.0)
      attr_reader :threshold

      # @return [Hash] Configuration options
      attr_reader :config

      ##
      # Initialize toxicity detector
      #
      # @param threshold [Float] Toxicity threshold (0.0-1.0)
      # @param config [Hash] Configuration options
      #
      def initialize(threshold: 0.7, **config)
        @threshold = threshold
        @config = config
        @keyword_patterns = load_keyword_patterns
        @ml_models = load_ml_models
      end

      ##
      # Validate content for toxicity
      #
      # @param content [String] Content to validate
      # @param context [Hash] Additional context
      # @return [ValidationResult] Validation result
      def validate(content, context = {})
        violations = []
        
        # Quick keyword check
        keyword_violations = detect_toxic_keywords(content, context)
        violations.concat(keyword_violations)
        
        # ML model check
        ml_violations = detect_with_ml_models(content, context)
        violations.concat(ml_violations)
        
        # External API check
        api_violations = detect_with_external_apis(content, context)
        violations.concat(api_violations)
        
        # Apply content filtering if violations found
        filtered_content = if violations.any?
                            filter_toxic_content(content, violations)
                          else
                            content
                          end

        ValidationResult.new(
          content: content,
          filtered_content: filtered_content,
          violations: violations,
          safe: violations.empty?,
          context: context,
          timestamp: Time.current
        )
      end

      private

      def load_keyword_patterns
        {
          hate_speech: {
            patterns: [
              /\b(hate|despise|loathe)\s+(you|them|people|everyone)\b/i,
              /\b(kill|murder|die)\s+(yourself|themselves)\b/i,
              /\b(stupid|idiot|moron|retard)\b/i
            ],
            severity: :high
          },
          
          threats: {
            patterns: [
              /\b(i will|gonna|going to)\s+(kill|hurt|harm|beat)\b/i,
              /\b(watch out|be careful|you better)\b/i,
              /\b(or else|consequences|pay for)\b/i
            ],
            severity: :critical
          },
          
          harassment: {
            patterns: [
              /\b(shut up|go away|leave me alone)\b/i,
              /\b(you suck|you're terrible|you're awful)\b/i,
              /\b(nobody likes you|everyone hates you)\b/i
            ],
            severity: :medium
          },
          
          profanity: {
            patterns: [
              /\b(fuck|shit|damn|hell|ass|bitch)\b/i,
              /\b(wtf|wth|omfg|stfu)\b/i
            ],
            severity: :low
          }
        }
      end

      def load_ml_models
        # In a real implementation, this would load pre-trained models
        # For now, we'll simulate with basic scoring
        {
          sentiment_model: method(:score_sentiment),
          toxicity_model: method(:score_toxicity),
          aggression_model: method(:score_aggression)
        }
      end

      def detect_toxic_keywords(content, context)
        violations = []
        
        @keyword_patterns.each do |category, config|
          config[:patterns].each do |pattern|
            if content.match?(pattern)
              violations << Violation.new(
                type: :toxicity,
                message: "Toxic #{category} detected",
                severity: config[:severity],
                metadata: {
                  category: category,
                  pattern: pattern.source,
                  match: content.match(pattern)&.to_s,
                  detector: :keyword
                }
              ).to_h
            end
          end
        end
        
        violations
      end

      def detect_with_ml_models(content, context)
        violations = []
        
        @ml_models.each do |model_name, model|
          begin
            score = model.call(content, context)
            
            if score > @threshold
              violations << Violation.new(
                type: :toxicity,
                message: "Toxic content detected by #{model_name}",
                severity: severity_for_score(score),
                metadata: {
                  model: model_name,
                  score: score,
                  threshold: @threshold,
                  detector: :ml_model
                }
              ).to_h
            end
          rescue StandardError => e
            log_error("ML model error", model: model_name, error: e)
          end
        end
        
        violations
      end

      def detect_with_external_apis(content, context)
        violations = []
        
        # Check with OpenAI Moderation API
        if defined?(OpenAI) && @config[:openai_api_key]
          openai_violations = check_openai_moderation(content, context)
          violations.concat(openai_violations)
        end
        
        # Check with Perspective API
        if @config[:perspective_api_key]
          perspective_violations = check_perspective_api(content, context)
          violations.concat(perspective_violations)
        end
        
        violations
      end

      def check_openai_moderation(content, context)
        begin
          client = OpenAI::Client.new(access_token: @config[:openai_api_key])
          
          response = client.moderations(
            parameters: {
              input: content
            }
          )
          
          result = response.dig("results", 0)
          return [] unless result
          
          violations = []
          
          if result["flagged"]
            result["categories"].each do |category, flagged|
              next unless flagged
              
              score = result.dig("category_scores", category) || 0
              
              violations << Violation.new(
                type: :toxicity,
                message: "Content flagged for #{category}",
                severity: severity_for_score(score),
                metadata: {
                  category: category,
                  score: score,
                  detector: :openai_moderation,
                  api_response: result
                }
              ).to_h
            end
          end
          
          violations
        rescue StandardError => e
          log_error("OpenAI moderation error", error: e)
          []
        end
      end

      def check_perspective_api(content, context)
        begin
          require 'faraday'
          
          conn = Faraday.new(url: 'https://commentanalyzer.googleapis.com')
          
          response = conn.post("/v1alpha1/comments:analyze") do |req|
            req.headers['Content-Type'] = 'application/json'
            req.params['key'] = @config[:perspective_api_key]
            req.body = JSON.generate({
              requestedAttributes: {
                TOXICITY: {},
                SEVERE_TOXICITY: {},
                IDENTITY_ATTACK: {},
                INSULT: {},
                PROFANITY: {},
                THREAT: {}
              },
              comment: {
                text: content
              }
            })
          end
          
          return [] unless response.success?
          
          result = JSON.parse(response.body)
          violations = []
          
          result.dig("attributeScores")&.each do |attribute, data|
            score = data.dig("summaryScore", "value") || 0
            
            if score > @threshold
              violations << Violation.new(
                type: :toxicity,
                message: "Content flagged for #{attribute.downcase}",
                severity: severity_for_score(score),
                metadata: {
                  attribute: attribute,
                  score: score,
                  detector: :perspective_api,
                  api_response: data
                }
              ).to_h
            end
          end
          
          violations
        rescue StandardError => e
          log_error("Perspective API error", error: e)
          []
        end
      end

      def score_sentiment(content, context)
        # Simple sentiment scoring based on keywords
        negative_words = %w[hate bad terrible awful horrible disgusting]
        positive_words = %w[love good great amazing wonderful fantastic]
        
        words = content.downcase.split
        negative_count = words.count { |word| negative_words.include?(word) }
        positive_count = words.count { |word| positive_words.include?(word) }
        
        # Return negative sentiment score (0.0-1.0)
        total_words = words.size
        return 0.0 if total_words == 0
        
        negative_ratio = negative_count.to_f / total_words
        positive_ratio = positive_count.to_f / total_words
        
        # Score is higher for more negative content
        (negative_ratio - positive_ratio).clamp(0.0, 1.0)
      end

      def score_toxicity(content, context)
        # Simple toxicity scoring based on patterns
        toxic_indicators = [
          /\b(kill|murder|die)\b/i,
          /\b(hate|despise|loathe)\b/i,
          /\b(stupid|idiot|moron)\b/i,
          /\b(fuck|shit|damn)\b/i,
          /[A-Z]{3,}/, # All caps words
          /!{2,}/, # Multiple exclamation marks
          /\?{2,}/ # Multiple question marks
        ]
        
        score = 0.0
        toxic_indicators.each do |pattern|
          matches = content.scan(pattern).size
          score += matches * 0.1
        end
        
        score.clamp(0.0, 1.0)
      end

      def score_aggression(content, context)
        # Simple aggression scoring
        aggressive_patterns = [
          /\b(fight|attack|destroy|crush)\b/i,
          /\b(you will|gonna|going to)\s+(regret|pay|suffer)\b/i,
          /\b(i don't care|whatever|shut up)\b/i
        ]
        
        score = 0.0
        aggressive_patterns.each do |pattern|
          score += 0.2 if content.match?(pattern)
        end
        
        score.clamp(0.0, 1.0)
      end

      def severity_for_score(score)
        case score
        when 0.0...0.3
          :low
        when 0.3...0.6
          :medium
        when 0.6...0.9
          :high
        else
          :critical
        end
      end

      def filter_toxic_content(content, violations)
        filtered = content.dup
        
        violations.each do |violation|
          case violation[:metadata][:detector]
          when :keyword
            if violation[:metadata][:match]
              # Replace toxic keywords with asterisks
              match = violation[:metadata][:match]
              replacement = '*' * match.length
              filtered.gsub!(match, replacement)
            end
          when :ml_model, :openai_moderation, :perspective_api
            # For ML/API detections, add warning message
            filtered = "[CONTENT_FILTERED: #{violation[:message]}]"
          end
        end
        
        filtered
      end
    end
  end
end