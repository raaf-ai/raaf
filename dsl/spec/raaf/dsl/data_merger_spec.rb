# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::DataMerger do
  let(:merger) { described_class.new }

  describe "#merge_strategy" do
    it "defines a merge strategy for a data type" do
      merger.merge_strategy(:companies) do
        key_field :website_domain
        merge_arrays :technologies, :contact_emails
        prefer_latest :employee_count
        sum_fields :confidence_score
        combine_objects :enrichment_data
      end

      strategy = merger.instance_variable_get(:@merge_strategies)[:companies]
      expect(strategy).to be_a(RAAF::DSL::MergeStrategyConfig)
      expect(strategy.key_field).to eq(:website_domain)
      expect(strategy.array_merge_fields).to include(:technologies, :contact_emails)
      expect(strategy.latest_fields).to include(:employee_count)
      expect(strategy.sum_fields).to include(:confidence_score)
      expect(strategy.object_merge_fields).to include(:enrichment_data)
    end

    it "allows custom merge rules" do
      merger.merge_strategy(:companies) do
        key_field :domain
        custom_merge(:score) do |base_value, new_value|
          [base_value || 0, new_value || 0].max
        end
      end

      strategy = merger.instance_variable_get(:@merge_strategies)[:companies]
      expect(strategy.custom_merge_rules[:score]).to be_a(Proc)
    end
  end

  describe "#merge" do
    context "with no results" do
      it "returns empty hash" do
        result = merger.merge
        expect(result).to eq({})
      end
    end

    context "with single result" do
      it "returns the single result unchanged" do
        single_result = { success: true, data: [{ name: "Company A" }] }
        result = merger.merge(single_result)
        expect(result).to eq(single_result)
      end
    end

    context "with multiple results using default strategy" do
      let(:result1) do
        {
          success: true,
          data: [
            { name: "Company A", domain: "company-a.com" },
            { name: "Company B", domain: "company-b.com" }
          ]
        }
      end

      let(:result2) do
        {
          success: true,
          data: [
            { name: "Company C", domain: "company-c.com" }
          ]
        }
      end

      it "merges multiple results using default strategy" do
        result = merger.merge(result1, result2, data_type: :default)

        expect(result[:success]).to be true
        expect(result[:data]).to be_an(Array)
        expect(result[:data].size).to eq(3)
        expect(result[:merge_metadata][:sources]).to eq(2)
        expect(result[:merge_metadata][:merged_count]).to eq(3)
        expect(result[:source_results]).to eq([result1, result2])
      end

      it "includes merge metadata" do
        result = merger.merge(result1, result2)

        expect(result[:merge_metadata]).to include(
          sources: 2,
          strategy: :default,
          merged_count: 3,
          timestamp: kind_of(String)
        )
      end

      it "handles failed source results" do
        failed_result = { success: false, error: "Agent failed" }
        result = merger.merge(result1, failed_result)

        expect(result[:success]).to be false
        expect(result[:data]).to be_an(Array)
      end
    end

    context "with custom merge strategy" do
      before do
        merger.merge_strategy(:companies) do
          key_field :domain
          merge_arrays :technologies, :contact_emails
          prefer_latest :employee_count, :last_updated
          sum_fields :confidence_score
          combine_objects :enrichment_data
        end
      end

      let(:company_result1) do
        {
          success: true,
          data: [
            {
              name: "TechCorp",
              domain: "techcorp.com",
              technologies: ["React", "Node.js"],
              contact_emails: ["info@techcorp.com"],
              employee_count: 100,
              confidence_score: 75,
              last_updated: "2024-01-01",
              enrichment_data: { source: "agent1", verified: true }
            }
          ]
        }
      end

      let(:company_result2) do
        {
          success: true,
          data: [
            {
              name: "TechCorp Enhanced", # Should be updated
              domain: "techcorp.com",    # Same key for merging
              technologies: ["Python", "PostgreSQL"], # Should merge with existing
              contact_emails: ["support@techcorp.com"], # Should merge with existing
              employee_count: 120,       # Should use latest
              confidence_score: 85,      # Should sum
              last_updated: "2024-02-01", # Should use latest
              enrichment_data: { source: "agent2", funding: "Series A" } # Should deep merge
            }
          ]
        }
      end

      it "merges companies using custom strategy" do
        result = merger.merge(company_result1, company_result2, data_type: :companies)

        expect(result[:success]).to be true
        expect(result[:data].size).to eq(1) # Merged into one company

        merged_company = result[:data].first
        expect(merged_company[:name]).to eq("TechCorp Enhanced") # Latest value
        expect(merged_company[:domain]).to eq("techcorp.com")
        expect(merged_company[:technologies]).to contain_exactly("React", "Node.js", "Python", "PostgreSQL")
        expect(merged_company[:contact_emails]).to contain_exactly("info@techcorp.com", "support@techcorp.com")
        expect(merged_company[:employee_count]).to eq(120) # Latest
        expect(merged_company[:confidence_score]).to eq(160) # Sum: 75 + 85
        expect(merged_company[:last_updated]).to eq("2024-02-01") # Latest
        expect(merged_company[:enrichment_data]).to include(
          source: "agent2", # Latest from second agent
          verified: true,   # From first agent
          funding: "Series A" # From second agent
        )
      end

      it "handles different data extraction patterns" do
        # Test data in root level
        root_data_result = {
          success: true,
          companies: [{ domain: "root.com", name: "Root Company" }]
        }

        # Test data in data key
        data_key_result = {
          success: true,
          data: {
            companies: [{ domain: "data.com", name: "Data Company" }]
          }
        }

        result = merger.merge(root_data_result, data_key_result, data_type: :companies)

        expect(result[:data].size).to eq(2)
        expect(result[:data].map { |c| c[:name] }).to contain_exactly("Root Company", "Data Company")
      end

      it "handles string keys in merge strategy" do
        string_key_result = {
          success: true,
          data: [
            {
              "name" => "String Key Company",
              "domain" => "stringkey.com",
              "technologies" => ["JavaScript"],
              "employee_count" => 50
            }
          ]
        }

        result = merger.merge(company_result1, string_key_result, data_type: :companies)

        expect(result[:data].size).to eq(2) # Different domains, so not merged
        string_company = result[:data].find { |c| c["domain"] == "stringkey.com" }
        expect(string_company["name"]).to eq("String Key Company")
      end
    end

    context "with custom merge rules" do
      before do
        merger.merge_strategy(:test_data) do
          key_field :id
          custom_merge(:average_score) do |base_value, new_value|
            return new_value unless base_value
            return base_value unless new_value
            ((base_value + new_value) / 2.0).round(1)
          end
          custom_merge(:max_value) do |base_value, new_value|
            [base_value || 0, new_value || 0].max
          end
        end
      end

      it "applies custom merge rules" do
        result1 = {
          success: true,
          data: [{ id: "test1", average_score: 80, max_value: 100 }]
        }

        result2 = {
          success: true,
          data: [{ id: "test1", average_score: 90, max_value: 85 }]
        }

        result = merger.merge(result1, result2, data_type: :test_data)

        merged_item = result[:data].first
        expect(merged_item[:average_score]).to eq(85.0) # Average of 80 and 90
        expect(merged_item[:max_value]).to eq(100) # Max of 100 and 85
      end
    end
  end

  describe "#merge_data_arrays" do
    let(:strategy) do
      config = RAAF::DSL::MergeStrategyConfig.new
      config.key_field(:id)
      config.merge_arrays(:tags)
      config.prefer_latest(:name)
      config
    end

    it "merges arrays without grouping when no key field" do
      no_key_strategy = RAAF::DSL::MergeStrategyConfig.new
      arrays = [
        [{ name: "Item 1" }, { name: "Item 2" }],
        [{ name: "Item 3" }]
      ]

      result = merger.merge_data_arrays(arrays, no_key_strategy)
      expect(result.size).to eq(3)
      expect(result.map { |item| item[:name] }).to contain_exactly("Item 1", "Item 2", "Item 3")
    end

    it "groups and merges by key field" do
      arrays = [
        [{ id: "1", name: "First", tags: ["a"] }, { id: "2", name: "Second", tags: ["b"] }],
        [{ id: "1", name: "Updated First", tags: ["c"] }]
      ]

      result = merger.merge_data_arrays(arrays, strategy)
      expect(result.size).to eq(2)

      first_item = result.find { |item| item[:id] == "1" }
      expect(first_item[:name]).to eq("Updated First") # Latest value
      expect(first_item[:tags]).to contain_exactly("a", "c") # Merged arrays

      second_item = result.find { |item| item[:id] == "2" }
      expect(second_item[:name]).to eq("Second")
      expect(second_item[:tags]).to eq(["b"])
    end

    it "handles empty arrays" do
      result = merger.merge_data_arrays([], strategy)
      expect(result).to eq([])
    end

    it "handles arrays with nil values" do
      arrays = [
        [{ id: "1", name: "Item" }, nil],
        [{ id: "2", name: "Another" }]
      ]

      result = merger.merge_data_arrays(arrays, strategy)
      expect(result.size).to eq(2)
    end
  end

  describe "#merge_item_group" do
    let(:strategy) do
      config = RAAF::DSL::MergeStrategyConfig.new
      config.merge_arrays(:tags)
      config.prefer_latest(:name, :updated_at)
      config.sum_fields(:score)
      config.combine_objects(:metadata)
      config
    end

    it "merges a group of items with same key" do
      items = [
        {
          id: "1",
          name: "Original",
          tags: ["tag1"],
          score: 10,
          updated_at: "2024-01-01",
          metadata: { source: "agent1", valid: true }
        },
        {
          id: "1",
          name: "Updated",
          tags: ["tag2"],
          score: 15,
          updated_at: "2024-02-01",
          metadata: { source: "agent2", confidence: 0.9 }
        }
      ]

      result = merger.merge_item_group(items, strategy)

      expect(result[:id]).to eq("1")
      expect(result[:name]).to eq("Updated") # Latest
      expect(result[:tags]).to contain_exactly("tag1", "tag2") # Merged arrays
      expect(result[:score]).to eq(25) # Sum: 10 + 15
      expect(result[:updated_at]).to eq("2024-02-01") # Latest
      expect(result[:metadata]).to include(
        source: "agent2",    # Latest from second item
        valid: true,         # From first item
        confidence: 0.9      # From second item
      )
    end

    it "handles single item groups" do
      items = [{ id: "1", name: "Single" }]
      result = merger.merge_item_group(items, strategy)
      expect(result).to eq({ id: "1", name: "Single" })
    end
  end

  describe "#deep_merge_objects" do
    it "deeply merges nested hash objects" do
      base_obj = {
        level1: {
          level2: {
            value1: "original",
            array1: ["a", "b"]
          },
          other: "data"
        }
      }

      new_obj = {
        level1: {
          level2: {
            value2: "new",
            array1: ["c", "d"]
          },
          another: "field"
        }
      }

      result = merger.deep_merge_objects(base_obj, new_obj)

      expected = {
        level1: {
          level2: {
            value1: "original",
            value2: "new",
            array1: ["a", "b", "c", "d"]
          },
          other: "data",
          another: "field"
        }
      }

      expect(result).to eq(expected)
    end

    it "merges arrays within nested objects" do
      base_obj = { data: { items: [1, 2] } }
      new_obj = { data: { items: [3, 4] } }

      result = merger.deep_merge_objects(base_obj, new_obj)
      expect(result[:data][:items]).to contain_exactly(1, 2, 3, 4)
    end

    it "handles non-hash values" do
      base_obj = { value: "original" }
      new_obj = { value: "updated" }

      result = merger.deep_merge_objects(base_obj, new_obj)
      expect(result[:value]).to eq("updated")
    end
  end

  describe "private methods" do
    describe "#extract_data_array" do
      it "extracts data from various result structures" do
        # Data in root with specific key
        result1 = { companies: [{ name: "Co1" }] }
        extracted1 = merger.send(:extract_data_array, result1, :companies)
        expect(extracted1).to eq([{ name: "Co1" }])

        # Data in data key with specific key
        result2 = { data: { companies: [{ name: "Co2" }] } }
        extracted2 = merger.send(:extract_data_array, result2, :companies)
        expect(extracted2).to eq([{ name: "Co2" }])

        # Data as direct array
        result3 = { data: [{ name: "Co3" }] }
        extracted3 = merger.send(:extract_data_array, result3, :companies)
        expect(extracted3).to eq([{ name: "Co3" }])

        # Data as single object
        result4 = { data: { name: "Co4" } }
        extracted4 = merger.send(:extract_data_array, result4, :companies)
        expect(extracted4).to eq([{ name: "Co4" }])
      end

      it "handles non-hash results" do
        extracted = merger.send(:extract_data_array, "not a hash", :companies)
        expect(extracted).to eq([])
      end

      it "handles string keys" do
        result = { "data" => { "companies" => [{ name: "Co1" }] } }
        extracted = merger.send(:extract_data_array, result, :companies)
        expect(extracted).to eq([{ name: "Co1" }])
      end
    end
  end
end

RSpec.describe RAAF::DSL::MergeStrategyConfig do
  let(:config) { described_class.new }

  describe "#key_field" do
    it "sets the key field for grouping" do
      config.key_field(:domain)
      expect(config.key_field).to eq(:domain)
    end
  end

  describe "#merge_arrays" do
    it "adds fields to array merge list" do
      config.merge_arrays(:tags, :emails)
      expect(config.array_merge_fields).to contain_exactly(:tags, :emails)
    end

    it "handles multiple calls" do
      config.merge_arrays(:tags)
      config.merge_arrays(:emails, :phones)
      expect(config.array_merge_fields).to contain_exactly(:tags, :emails, :phones)
    end
  end

  describe "#prefer_latest" do
    it "adds fields to latest preference list" do
      config.prefer_latest(:updated_at, :name)
      expect(config.latest_fields).to contain_exactly(:updated_at, :name)
    end
  end

  describe "#sum_fields" do
    it "adds fields to sum list" do
      config.sum_fields(:score, :count)
      expect(config.sum_fields).to contain_exactly(:score, :count)
    end
  end

  describe "#combine_objects" do
    it "adds fields to object merge list" do
      config.combine_objects(:metadata, :config)
      expect(config.object_merge_fields).to contain_exactly(:metadata, :config)
    end

    it "accepts strategy parameter" do
      config.combine_objects(:data, strategy: :deep_merge)
      expect(config.object_merge_fields).to include(:data)
    end
  end

  describe "#custom_merge" do
    it "adds custom merge rules" do
      rule = ->(base, new) { base }
      config.custom_merge(:special_field, &rule)
      expect(config.custom_merge_rules[:special_field]).to eq(rule)
    end
  end
end

RSpec.describe RAAF::DSL::DefaultMergeStrategy do
  let(:strategy) { described_class.new }

  it "provides empty defaults for all fields" do
    expect(strategy.key_field).to be_nil
    expect(strategy.array_merge_fields).to eq([])
    expect(strategy.latest_fields).to eq([])
    expect(strategy.sum_fields).to eq([])
    expect(strategy.object_merge_fields).to eq([])
    expect(strategy.custom_merge_rules).to eq({})
  end
end

RSpec.describe RAAF::DSL::MergeUtils do
  describe ".merge_prospect_data" do
    let(:prospect_result1) do
      {
        success: true,
        data: [
          {
            company_domain: "company1.com",
            contact_emails: ["contact1@company1.com"],
            phone_numbers: ["555-0001"],
            confidence_score: 80,
            overall_score: 75,
            last_updated_at: "2024-01-01",
            enrichment_data: { source: "agent1" }
          }
        ]
      }
    end

    let(:prospect_result2) do
      {
        success: true,
        data: [
          {
            company_domain: "company1.com", # Same domain for merging
            contact_emails: ["info@company1.com"],
            phone_numbers: ["555-0002"],
            confidence_score: 90,
            overall_score: 85,
            last_updated_at: "2024-02-01",
            enrichment_data: { source: "agent2", verified: true }
          }
        ]
      }
    end

    it "merges prospect data using predefined strategy" do
      result = described_class.merge_prospect_data(prospect_result1, prospect_result2)

      expect(result[:success]).to be true
      expect(result[:data].size).to eq(1)

      merged_prospect = result[:data].first
      expect(merged_prospect[:company_domain]).to eq("company1.com")
      expect(merged_prospect[:contact_emails]).to contain_exactly(
        "contact1@company1.com", "info@company1.com"
      )
      expect(merged_prospect[:phone_numbers]).to contain_exactly("555-0001", "555-0002")
      expect(merged_prospect[:confidence_score]).to eq(170) # Sum
      expect(merged_prospect[:overall_score]).to eq(80.0) # Average of 75 and 85
      expect(merged_prospect[:last_updated_at]).to eq("2024-02-01") # Latest
      expect(merged_prospect[:enrichment_data]).to include(
        source: "agent2",
        verified: true
      )
    end
  end

  describe ".merge_enrichment_data" do
    let(:enrichment_result1) do
      {
        success: true,
        data: [
          {
            website_domain: "techco.com",
            technologies: ["React", "Node.js"],
            employee_count: 100,
            tech_confidence: 80,
            contact_info: { email: "contact@techco.com" }
          }
        ]
      }
    end

    let(:enrichment_result2) do
      {
        success: true,
        data: [
          {
            website_domain: "techco.com",
            technologies: ["Python", "PostgreSQL"],
            employee_count: 120,
            tech_confidence: 85,
            contact_info: { phone: "555-TECH" }
          }
        ]
      }
    end

    it "merges enrichment data using predefined strategy" do
      result = described_class.merge_enrichment_data(enrichment_result1, enrichment_result2)

      expect(result[:success]).to be true
      merged_company = result[:data].first

      expect(merged_company[:website_domain]).to eq("techco.com")
      expect(merged_company[:technologies]).to contain_exactly(
        "React", "Node.js", "Python", "PostgreSQL"
      )
      expect(merged_company[:employee_count]).to eq(120) # Latest
      expect(merged_company[:tech_confidence]).to eq(85) # Max
      expect(merged_company[:contact_info]).to include(
        email: "contact@techco.com",
        phone: "555-TECH"
      )
    end
  end

  describe ".merge_stakeholder_data" do
    let(:stakeholder_result1) do
      {
        success: true,
        data: [
          {
            linkedin_url: "linkedin.com/in/john-doe",
            email_addresses: ["john@company.com"],
            current_title: "Senior Developer",
            influence_score: 75,
            contact_attempts: { emails_sent: 2 }
          }
        ]
      }
    end

    let(:stakeholder_result2) do
      {
        success: true,
        data: [
          {
            linkedin_url: "linkedin.com/in/john-doe",
            email_addresses: ["j.doe@company.com"],
            current_title: "Lead Developer",
            influence_score: 85,
            contact_attempts: { calls_made: 1 }
          }
        ]
      }
    end

    it "merges stakeholder data using predefined strategy" do
      result = described_class.merge_stakeholder_data(stakeholder_result1, stakeholder_result2)

      expect(result[:success]).to be true
      merged_stakeholder = result[:data].first

      expect(merged_stakeholder[:linkedin_url]).to eq("linkedin.com/in/john-doe")
      expect(merged_stakeholder[:email_addresses]).to contain_exactly(
        "john@company.com", "j.doe@company.com"
      )
      expect(merged_stakeholder[:current_title]).to eq("Lead Developer") # Latest
      expect(merged_stakeholder[:influence_score]).to eq(85) # Max
      expect(merged_stakeholder[:contact_attempts]).to include(
        emails_sent: 2,
        calls_made: 1
      )
    end
  end
end

# Integration tests
RSpec.describe "DataMerger Integration" do
  describe "complex multi-agent merge scenarios" do
    let(:merger) { RAAF::DSL::DataMerger.new }

    before do
      merger.merge_strategy(:companies) do
        key_field :domain
        merge_arrays :technologies, :funding_rounds, :contact_emails
        prefer_latest :employee_count, :revenue_range, :last_updated
        sum_fields :total_funding, :confidence_score
        combine_objects :social_data, :financial_data, :technology_stack

        custom_merge(:average_rating) do |base_value, new_value|
          return new_value unless base_value
          return base_value unless new_value
          ((base_value + new_value) / 2.0).round(1)
        end
      end
    end

    it "handles complex company data merge from multiple agents" do
      search_agent_result = {
        success: true,
        data: [
          {
            name: "TechStartup Inc",
            domain: "techstartup.com",
            technologies: ["React", "Node.js", "MongoDB"],
            employee_count: 50,
            contact_emails: ["info@techstartup.com"],
            total_funding: 1000000,
            confidence_score: 75,
            average_rating: 4.2,
            last_updated: "2024-01-15",
            social_data: { twitter: "@techstartup", followers: 5000 },
            technology_stack: { frontend: "React", backend: "Node.js" }
          }
        ]
      }

      enrichment_agent_result = {
        success: true,
        data: [
          {
            name: "TechStartup Inc (Verified)",
            domain: "techstartup.com",
            technologies: ["TypeScript", "PostgreSQL", "AWS"],
            employee_count: 65,
            contact_emails: ["contact@techstartup.com", "support@techstartup.com"],
            funding_rounds: ["Seed", "Series A"],
            total_funding: 500000,
            confidence_score: 90,
            average_rating: 4.5,
            last_updated: "2024-02-01",
            social_data: { linkedin: "techstartup-inc", employees: 65 },
            financial_data: { revenue_range: "$1M-$10M", growth_rate: "150%" },
            technology_stack: { database: "PostgreSQL", cloud: "AWS" }
          }
        ]
      }

      scoring_agent_result = {
        success: true,
        data: [
          {
            domain: "techstartup.com",
            employee_count: 70,
            revenue_range: "$5M-$15M",
            confidence_score: 85,
            average_rating: 4.3,
            last_updated: "2024-02-15",
            fit_score: 92,
            market_position: "Leader"
          }
        ]
      }

      result = merger.merge(
        search_agent_result,
        enrichment_agent_result,
        scoring_agent_result,
        data_type: :companies
      )

      expect(result[:success]).to be true
      expect(result[:data].size).to eq(1)

      merged_company = result[:data].first

      # Verify different merge strategies applied correctly
      expect(merged_company[:name]).to eq("TechStartup Inc (Verified)") # Latest
      expect(merged_company[:domain]).to eq("techstartup.com")

      # Array merging
      expect(merged_company[:technologies]).to contain_exactly(
        "React", "Node.js", "MongoDB", "TypeScript", "PostgreSQL", "AWS"
      )
      expect(merged_company[:contact_emails]).to contain_exactly(
        "info@techstartup.com", "contact@techstartup.com", "support@techstartup.com"
      )
      expect(merged_company[:funding_rounds]).to eq(["Seed", "Series A"])

      # Latest value preference
      expect(merged_company[:employee_count]).to eq(70) # From scoring agent (latest)
      expect(merged_company[:revenue_range]).to eq("$5M-$15M") # From scoring agent (latest)
      expect(merged_company[:last_updated]).to eq("2024-02-15") # Latest timestamp

      # Sum fields
      expect(merged_company[:total_funding]).to eq(1500000) # 1000000 + 500000
      expect(merged_company[:confidence_score]).to eq(250) # 75 + 90 + 85

      # Custom merge (average)
      expect(merged_company[:average_rating]).to eq(4.3) # Average of 4.2, 4.5, 4.3

      # Object merging
      expect(merged_company[:social_data]).to include(
        twitter: "@techstartup",
        followers: 5000,
        linkedin: "techstartup-inc",
        employees: 65
      )

      expect(merged_company[:technology_stack]).to include(
        frontend: "React",
        backend: "Node.js",
        database: "PostgreSQL",
        cloud: "AWS"
      )

      expect(merged_company[:financial_data]).to include(
        revenue_range: "$1M-$10M", # Note: this is from enrichment, then overridden by scoring agent
        growth_rate: "150%"
      )

      # Fields from scoring agent only
      expect(merged_company[:fit_score]).to eq(92)
      expect(merged_company[:market_position]).to eq("Leader")
    end

    it "handles missing data and nil values gracefully" do
      partial_result1 = {
        success: true,
        data: [
          {
            domain: "partial.com",
            name: "Partial Company",
            technologies: ["React"],
            employee_count: nil,
            confidence_score: 50
          }
        ]
      }

      partial_result2 = {
        success: true,
        data: [
          {
            domain: "partial.com",
            technologies: ["Vue.js"],
            employee_count: 25,
            total_funding: 100000,
            social_data: { twitter: "@partial" }
          }
        ]
      }

      result = merger.merge(partial_result1, partial_result2, data_type: :companies)

      merged_company = result[:data].first
      expect(merged_company[:name]).to eq("Partial Company") # Only in first result
      expect(merged_company[:technologies]).to contain_exactly("React", "Vue.js")
      expect(merged_company[:employee_count]).to eq(25) # nil overridden by actual value
      expect(merged_company[:total_funding]).to eq(100000) # Only in second result
      expect(merged_company[:confidence_score]).to eq(50) # Only in first result
      expect(merged_company[:social_data][:twitter]).to eq("@partial")
    end
  end
end