# frozen_string_literal: true

# Mock agent classes for pipeline testing
module MockPipelineAgents
  class MockSearchAgent
    def initialize(context: {})
      @context = context
    end

    def run(context: {})
      companies = [
        { name: "Company A", website: "company-a.com" },
        { name: "Company B", website: "company-b.com" }
      ]
      { success: true, companies: companies }
    end
  end

  class MockEnrichmentAgent
    def initialize(context: {})
      @context = context
    end

    def run(context: {})
      companies = @context.get(:companies) || []
      enriched = companies.map do |company|
        company.merge(employee_count: 100, industry: "Technology")
      end
      { success: true, enriched_companies: enriched }
    end
  end

  class MockScoringAgent
    def initialize(context: {})
      @context = context
    end

    def run(context: {})
      companies = @context.get(:enriched_companies) || []
      scored = companies.map do |company|
        company.merge(score: 85, fit_level: "high")
      end
      { success: true, scored_prospects: scored }
    end
  end

  class MockFailingAgent
    def initialize(context: {})
      @context = context
    end

    def run(context: {})
      { success: false, error: "Agent execution failed" }
    end
  end

  class MockErrorAgent
    def initialize(context: {})
      @context = context
    end

    def run(context: {})
      raise StandardError, "Agent threw an exception"
    end
  end
end