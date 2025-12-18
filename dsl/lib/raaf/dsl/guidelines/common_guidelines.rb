# frozen_string_literal: true

module RAAF
  module DSL
    module Guidelines
      ##
      # CommonGuidelines provides reusable guideline sets for common compliance patterns
      #
      # This module provides pre-built guideline configurations that can be easily
      # included in agents to enforce common behavioral constraints. Each guideline
      # set addresses a specific compliance or quality concern.
      #
      # @example Using factual guidelines in an agent
      #   class MyResearchAgent < RAAF::DSL::Agent
      #     include RAAF::DSL::Guidelines::CommonGuidelines
      #
      #     agent_name "ResearchAgent"
      #     model "gpt-4o"
      #
      #     # Apply factual guidelines to prevent hallucination
      #     use_factual_guidelines
      #   end
      #
      # @example Using multiple guideline sets
      #   class EUResearchAgent < RAAF::DSL::Agent
      #     include RAAF::DSL::Guidelines::CommonGuidelines
      #
      #     agent_name "EUResearchAgent"
      #     model "gpt-4o"
      #
      #     use_factual_guidelines
      #     use_gdpr_guidelines
      #     use_professional_tone_guidelines
      #   end
      #
      module CommonGuidelines
        def self.included(base)
          base.extend(ClassMethods)
        end

        ##
        # Class methods for defining common guideline sets
        #
        module ClassMethods
          ##
          # Apply factual accuracy guidelines to prevent hallucination
          #
          # These guidelines enforce that the agent only includes verifiable facts
          # from provided context and tools, never fabricating information.
          #
          # Guidelines included:
          # - :no_hallucination - Only use data from context/tools, never fabricate
          # - :cite_sources - Include source references for claims
          # - :acknowledge_uncertainty - Explicitly state when information is uncertain
          #
          # @param options [Hash] Optional configuration
          # @option options [Boolean] :strict (true) Whether to use strict mode
          #
          # @example
          #   class MyAgent < RAAF::DSL::Agent
          #     include RAAF::DSL::Guidelines::CommonGuidelines
          #     use_factual_guidelines
          #   end
          #
          def use_factual_guidelines(strict: true)
            guideline :no_hallucination,
                      condition: ->(_ctx, _input) { true },
                      action: "Only include information that comes from the provided context, tools, or verified data sources. Never fabricate, assume, or invent information. If information is not available, explicitly state that it is unknown.",
                      verification: "Check that all factual claims have a traceable source in the context or tool outputs",
                      priority: strict ? :critical : :high,
                      metadata: { category: :factual_accuracy }

            guideline :cite_sources,
                      condition: ->(_ctx, _input) { true },
                      action: "When presenting facts or claims, reference the source of that information (e.g., 'According to the company website...', 'Based on the search results...')",
                      verification: "Verify that factual statements reference their origin",
                      priority: :high,
                      metadata: { category: :factual_accuracy }

            guideline :acknowledge_uncertainty,
                      condition: ->(_ctx, _input) { true },
                      action: "When information is incomplete, uncertain, or conflicting, explicitly acknowledge this uncertainty. Use qualifiers like 'may', 'appears to', 'the available data suggests' when appropriate.",
                      verification: "Check for appropriate hedging language when certainty is not absolute",
                      priority: :normal,
                      metadata: { category: :factual_accuracy }
          end

          ##
          # Apply GDPR compliance guidelines for European data processing
          #
          # These guidelines enforce data protection principles when processing
          # data from EU/EEA regions. Activated when context contains European
          # region indicators.
          #
          # Guidelines included:
          # - :data_minimization - Only request/process necessary personal data
          # - :purpose_limitation - Only use data for specified purposes
          # - :transparency - Be transparent about data processing activities
          #
          # @example
          #   class MyAgent < RAAF::DSL::Agent
          #     include RAAF::DSL::Guidelines::CommonGuidelines
          #     use_gdpr_guidelines
          #   end
          #
          def use_gdpr_guidelines
            eu_regions = %w[EU EEA NL DE FR BE AT IT ES PT PL CZ HU SK SI HR BG RO GR CY MT LU IE DK SE FI EE LV LT IS NO LI]

            guideline :data_minimization,
                      condition: {
                        type: :schema,
                        field: :region,
                        operator: :in,
                        value: eu_regions
                      },
                      action: "Only request, collect, and process personal data that is strictly necessary for the specified purpose. Avoid collecting excessive or irrelevant personal information.",
                      verification: "Verify that no unnecessary personal data fields are requested or processed",
                      priority: :critical,
                      metadata: { category: :gdpr, regulation: "GDPR Art. 5(1)(c)" }

            guideline :purpose_limitation,
                      condition: {
                        type: :schema,
                        field: :region,
                        operator: :in,
                        value: eu_regions
                      },
                      action: "Only use personal data for the specific, explicit purposes for which it was collected. Do not repurpose data without proper consent or legal basis.",
                      verification: "Verify data usage aligns with stated collection purpose",
                      priority: :critical,
                      metadata: { category: :gdpr, regulation: "GDPR Art. 5(1)(b)" }

            guideline :transparency,
                      condition: {
                        type: :schema,
                        field: :region,
                        operator: :in,
                        value: eu_regions
                      },
                      action: "Be transparent about what personal data is being processed and for what purpose. Provide clear explanations when handling user data.",
                      verification: "Verify transparency in data handling descriptions",
                      priority: :high,
                      metadata: { category: :gdpr, regulation: "GDPR Art. 5(1)(a)" }
          end

          ##
          # Apply professional tone guidelines for business communications
          #
          # These guidelines ensure outputs maintain a professional, respectful,
          # and appropriate tone for business contexts.
          #
          # Guidelines included:
          # - :professional_language - Use clear, professional language
          # - :respectful_tone - Maintain respectful and objective tone
          # - :constructive_feedback - Frame feedback constructively
          #
          # @example
          #   class MyAgent < RAAF::DSL::Agent
          #     include RAAF::DSL::Guidelines::CommonGuidelines
          #     use_professional_tone_guidelines
          #   end
          #
          def use_professional_tone_guidelines
            guideline :professional_language,
                      condition: ->(_ctx, _input) { true },
                      action: "Use clear, professional language appropriate for business communication. Avoid slang, excessive jargon, or overly casual expressions unless the context specifically requires them.",
                      verification: "Verify language is appropriate for professional contexts",
                      priority: :normal,
                      metadata: { category: :tone }

            guideline :respectful_tone,
                      condition: ->(_ctx, _input) { true },
                      action: "Maintain a respectful, objective, and balanced tone. Avoid inflammatory, dismissive, or condescending language. Present information neutrally without bias.",
                      verification: "Verify tone is respectful and objective throughout",
                      priority: :high,
                      metadata: { category: :tone }

            guideline :constructive_feedback,
                      condition: /feedback|review|assessment|evaluation|critique/i,
                      action: "When providing feedback or assessments, frame observations constructively. Focus on actionable improvements rather than criticism alone.",
                      verification: "Verify feedback is framed constructively with actionable suggestions",
                      priority: :normal,
                      metadata: { category: :tone }
          end

          ##
          # Apply safety guidelines to prevent harmful outputs
          #
          # These guidelines prevent the generation of content that could
          # cause harm, including dangerous instructions, harmful advice,
          # or inappropriate content.
          #
          # Guidelines included:
          # - :no_harmful_content - Avoid generating harmful or dangerous content
          # - :no_personal_advice - Avoid giving medical, legal, or financial advice
          # - :escalation_awareness - Recognize when to escalate to humans
          #
          # @example
          #   class MyAgent < RAAF::DSL::Agent
          #     include RAAF::DSL::Guidelines::CommonGuidelines
          #     use_safety_guidelines
          #   end
          #
          def use_safety_guidelines
            guideline :no_harmful_content,
                      condition: ->(_ctx, _input) { true },
                      action: "Never generate content that could cause physical harm, promote illegal activities, enable violence, or provide instructions for dangerous activities. Refuse such requests politely.",
                      verification: "Verify output contains no harmful or dangerous content",
                      priority: :critical,
                      metadata: { category: :safety }

            guideline :no_personal_advice,
                      condition: /medical|health|legal|financial|investment|tax/i,
                      action: "Do not provide specific medical, legal, financial, or tax advice. When these topics arise, recommend consulting with qualified professionals and provide only general information with appropriate disclaimers.",
                      verification: "Verify no specific professional advice is given without disclaimers",
                      priority: :critical,
                      metadata: { category: :safety }

            guideline :escalation_awareness,
                      condition: /emergency|crisis|danger|suicide|self-harm|harm|threat|violence/i,
                      action: "Recognize situations that require human intervention. When detecting emergency situations, crisis mentions, or serious concerns, recommend appropriate emergency services or professional help rather than attempting to handle directly.",
                      verification: "Verify appropriate escalation for crisis situations",
                      priority: :critical,
                      metadata: { category: :safety }
          end

          ##
          # Apply B2B sales context guidelines
          #
          # These guidelines are specific to B2B sales and prospecting contexts,
          # ensuring outputs align with professional sales practices.
          #
          # Guidelines included:
          # - :respect_business_boundaries - Respect professional boundaries
          # - :value_proposition_focus - Focus on genuine value proposition
          # - :no_aggressive_tactics - Avoid aggressive or manipulative tactics
          #
          # @example
          #   class ProspectingAgent < RAAF::DSL::Agent
          #     include RAAF::DSL::Guidelines::CommonGuidelines
          #     use_b2b_sales_guidelines
          #   end
          #
          def use_b2b_sales_guidelines
            guideline :respect_business_boundaries,
                      condition: ->(_ctx, _input) { true },
                      action: "Respect professional boundaries in all business communications. Honor opt-out requests, avoid excessive follow-ups, and respect stated preferences.",
                      verification: "Verify communications respect stated boundaries and preferences",
                      priority: :high,
                      metadata: { category: :sales_ethics }

            guideline :value_proposition_focus,
                      condition: ->(_ctx, _input) { true },
                      action: "Focus on genuine value proposition and business fit. Emphasize how the solution addresses specific pain points rather than using generic sales language.",
                      verification: "Verify messaging focuses on genuine value rather than hype",
                      priority: :normal,
                      metadata: { category: :sales_ethics }

            guideline :no_aggressive_tactics,
                      condition: ->(_ctx, _input) { true },
                      action: "Avoid aggressive or manipulative sales tactics. Do not use artificial urgency, misleading claims, or pressure tactics. Build trust through honest, helpful communication.",
                      verification: "Verify no aggressive or manipulative tactics are employed",
                      priority: :high,
                      metadata: { category: :sales_ethics }
          end

          ##
          # Apply research and analysis guidelines
          #
          # These guidelines ensure thorough, objective research and analysis
          # with appropriate methodology and balanced perspectives.
          #
          # Guidelines included:
          # - :comprehensive_research - Cover multiple perspectives
          # - :balanced_analysis - Present balanced viewpoints
          # - :methodology_transparency - Be transparent about methodology
          #
          # @example
          #   class ResearchAgent < RAAF::DSL::Agent
          #     include RAAF::DSL::Guidelines::CommonGuidelines
          #     use_research_guidelines
          #   end
          #
          def use_research_guidelines
            guideline :comprehensive_research,
                      condition: /research|analyze|investigate|study|examine/i,
                      action: "Conduct comprehensive research by examining multiple sources and perspectives. Do not rely on a single source or viewpoint for conclusions.",
                      verification: "Verify multiple sources and perspectives are considered",
                      priority: :high,
                      metadata: { category: :research }

            guideline :balanced_analysis,
                      condition: /analyze|assessment|evaluation|comparison/i,
                      action: "Present balanced analysis that considers both strengths and weaknesses, advantages and disadvantages. Avoid one-sided presentations unless explicitly requested.",
                      verification: "Verify analysis considers multiple angles",
                      priority: :normal,
                      metadata: { category: :research }

            guideline :methodology_transparency,
                      condition: /research|analyze|investigate/i,
                      action: "Be transparent about research methodology, data sources, and any limitations. Acknowledge gaps in available information.",
                      verification: "Verify methodology and limitations are disclosed",
                      priority: :normal,
                      metadata: { category: :research }
          end
        end
      end
    end
  end
end
