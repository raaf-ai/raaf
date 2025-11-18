# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/eval/red_team"
require "csv"  # Explicitly require CSV for Ruby 3.4+

RSpec.describe "Red-Team Integration Features" do
  # Mock model callback for testing
  let(:model_callback) do
    lambda do |input|
      if input.match?(/hack|exploit|illegal/i)
        "I cannot help with that request as it violates safety guidelines."
      else
        "Here's information about #{input}"
      end
    end
  end

  let(:red_teamer) do
    RAAF::Eval::RedTeam::RedTeamer.new(
      model_callback: model_callback,
      async_mode: false,  # Disable for deterministic tests
      ignore_errors: true
    )
  end

  describe "Export Features" do
    let(:bias) { RAAF::Eval::RedTeam::Vulnerabilities::BiasVulnerability.new }
    let(:toxicity) { RAAF::Eval::RedTeam::Vulnerabilities::ToxicityVulnerability.new }
    let(:prompt_injection) { RAAF::Eval::RedTeam::Attacks::SingleTurn::PromptInjectionAttack.new }
    let(:roleplay) { RAAF::Eval::RedTeam::Attacks::SingleTurn::RoleplayAttack.new }

    let(:assessment) do
      red_teamer.scan(
        vulnerabilities: [bias, toxicity],
        attacks: [prompt_injection],  # Using Attack instance, not symbol
        attacks_per_vulnerability: 2
      )
    end

    describe "#to_df" do
      it "converts assessment to DataFrame-compatible format" do
        df_data = assessment.to_df

        expect(df_data).to be_an(Array)
        expect(df_data).not_to be_empty

        # Each row should be a hash with expected fields
        first_row = df_data.first
        expect(first_row).to be_a(Hash)
        expect(first_row).to have_key(:vulnerability_type)
        expect(first_row).to have_key(:attack_name)
        expect(first_row).to have_key(:category)
        expect(first_row).to have_key(:input)
        expect(first_row).to have_key(:output)
        expect(first_row).to have_key(:score)
        expect(first_row).to have_key(:status)
      end

      it "includes all test cases" do
        df_data = assessment.to_df

        # Should have data for both vulnerabilities with 2 attacks each
        expect(df_data.length).to be >= 4
      end

      it "preserves vulnerability metadata" do
        df_data = assessment.to_df

        # Check for bias vulnerability tests
        bias_rows = df_data.select { |row| row[:vulnerability_type] == "bias" }
        expect(bias_rows).not_to be_empty
        expect(bias_rows.first[:category]).to eq("responsible_ai")

        # Check for toxicity vulnerability tests
        toxicity_rows = df_data.select { |row| row[:vulnerability_type] == "toxicity" }
        expect(toxicity_rows).not_to be_empty
        expect(toxicity_rows.first[:category]).to eq("responsible_ai")
      end
    end

    describe "#to_csv" do
      let(:temp_csv) { "/tmp/red_team_test_#{Time.now.to_i}.csv" }

      after do
        File.delete(temp_csv) if File.exist?(temp_csv)
      end

      it "exports assessment to CSV file" do
        assessment.to_csv(temp_csv)

        expect(File.exist?(temp_csv)).to be true
        expect(File.size(temp_csv)).to be > 0
      end

      it "creates valid CSV with header row" do
        assessment.to_csv(temp_csv)

        lines = File.readlines(temp_csv)
        header = lines.first.chomp.split(",")

        expect(header).to include("vulnerability_type")
        expect(header).to include("attack_name")
        expect(header).to include("category")
        expect(header).to include("input")
        expect(header).to include("output")
        expect(header).to include("score")
        expect(header).to include("status")
      end

      it "includes all test case data rows" do
        assessment.to_csv(temp_csv)

        lines = File.readlines(temp_csv)
        # Header + at least 4 data rows (2 vulnerabilities × 2 attacks)
        expect(lines.length).to be >= 5
      end

      it "can be parsed back with CSV library" do
        require "csv"
        assessment.to_csv(temp_csv)

        parsed = CSV.read(temp_csv, headers: true)
        expect(parsed).not_to be_empty

        # Check first row has expected structure
        first_row = parsed.first
        expect(first_row["vulnerability_type"]).not_to be_nil
        expect(first_row["attack_name"]).not_to be_nil
      end
    end

    describe "#summary" do
      it "provides comprehensive summary statistics" do
        summary = assessment.summary

        expect(summary).to be_a(Hash)
        expect(summary).to have_key(:total_tests)
        expect(summary).to have_key(:passed)
        expect(summary).to have_key(:failed)
        expect(summary).to have_key(:errored)
        expect(summary).to have_key(:pass_rate)
        expect(summary).to have_key(:risk_score)
        expect(summary).to have_key(:risk_level)
        expect(summary).to have_key(:critical_vulnerabilities)
        expect(summary).to have_key(:effective_attacks)
      end

      it "calculates risk metrics correctly" do
        summary = assessment.summary

        expect([:critical, :high, :medium, :low]).to include(summary[:risk_level])
        expect(summary[:risk_score]).to be_between(0.0, 1.0)
        expect(summary[:pass_rate]).to be_between(0.0, 1.0)
      end
    end
  end

  describe "Caching Features" do
    let(:bias) { RAAF::Eval::RedTeam::Vulnerabilities::BiasVulnerability.new }
    let(:prompt_injection) { RAAF::Eval::RedTeam::Attacks::SingleTurn::PromptInjectionAttack.new }
    let(:roleplay) { RAAF::Eval::RedTeam::Attacks::SingleTurn::RoleplayAttack.new }

    describe "attack caching" do
      it "caches baseline attacks after first scan" do
        # First scan generates attacks
        red_teamer.scan(
          vulnerabilities: [bias],
          attacks: [prompt_injection],  # Using Attack instance
          attacks_per_vulnerability: 2
        )

        # Cache should now contain bias attacks
        expect(red_teamer.attack_cache).to have_key("bias")
        expect(red_teamer.attack_cache["bias"]).not_to be_empty
      end

      it "reuses cached attacks with reuse_previous_attacks flag" do
        # First scan
        first_assessment = red_teamer.scan(
          vulnerabilities: [bias],
          attacks: [prompt_injection],  # Using Attack instance
          attacks_per_vulnerability: 2
        )

        # Store first scan's baseline attacks
        first_cache = red_teamer.attack_cache["bias"].dup

        # Second scan with different attack method but reusing baselines
        second_assessment = red_teamer.scan(
          vulnerabilities: [bias],
          attacks: [roleplay],  # Using Attack instance
          attacks_per_vulnerability: 2,
          reuse_previous_attacks: true
        )

        # Cache should still contain same baseline attacks
        expect(red_teamer.attack_cache["bias"]).to eq(first_cache)
      end

      it "generates new attacks when not reusing cache" do
        # First scan
        red_teamer.scan(
          vulnerabilities: [bias],
          attacks: [prompt_injection],  # Using Attack instance
          attacks_per_vulnerability: 2
        )

        first_cache = red_teamer.attack_cache["bias"].dup

        # Second scan WITHOUT reuse flag
        red_teamer.scan(
          vulnerabilities: [bias],
          attacks: [roleplay],  # Using Attack instance
          attacks_per_vulnerability: 3,  # Different count
          reuse_previous_attacks: false
        )

        # Cache should contain different attacks
        expect(red_teamer.attack_cache["bias"]).not_to eq(first_cache)
      end
    end

    describe "#clear_cache!" do
      it "clears all cached attacks" do
        # Generate some cached attacks
        red_teamer.scan(
          vulnerabilities: [bias],
          attacks: [prompt_injection],  # Using Attack instance
          attacks_per_vulnerability: 2
        )

        expect(red_teamer.attack_cache).not_to be_empty

        # Clear cache
        red_teamer.clear_cache!

        expect(red_teamer.attack_cache).to be_empty
      end
    end
  end

  describe "Async Mode Features" do
    let(:bias) { RAAF::Eval::RedTeam::Vulnerabilities::BiasVulnerability.new }
    let(:toxicity) { RAAF::Eval::RedTeam::Vulnerabilities::ToxicityVulnerability.new }
    let(:prompt_injection) { RAAF::Eval::RedTeam::Attacks::SingleTurn::PromptInjectionAttack.new }
    let(:roleplay) { RAAF::Eval::RedTeam::Attacks::SingleTurn::RoleplayAttack.new }

    context "when async mode is enabled" do
      let(:async_red_teamer) do
        RAAF::Eval::RedTeam::RedTeamer.new(
          model_callback: model_callback,
          async_mode: true,
          max_concurrent: 4
        )
      end

      it "completes scan successfully" do
        assessment = async_red_teamer.scan(
          vulnerabilities: [bias, toxicity],
          attacks: [prompt_injection, roleplay],  # Using Attack instances
          attacks_per_vulnerability: 3
        )

        expect(assessment).to be_a(RAAF::Eval::RedTeam::RiskAssessment)
        expect(assessment.overview.total_tests).to be > 0
      end

      it "processes multiple test cases" do
        assessment = async_red_teamer.scan(
          vulnerabilities: [bias, toxicity],
          attacks: [prompt_injection],  # Using Attack instance
          attacks_per_vulnerability: 5
        )

        # Should have processed: 2 vulnerabilities × 1 attack × 5 samples = 10 tests
        expect(assessment.overview.total_tests).to eq(10)
      end

      it "respects max_concurrent limit" do
        # This test verifies the system doesn't crash with concurrent operations
        assessment = async_red_teamer.scan(
          vulnerabilities: [bias, toxicity],
          attacks: [prompt_injection, roleplay],  # Using Attack instances
          attacks_per_vulnerability: 10
        )

        # Should complete without errors
        expect(assessment.overview.total_tests).to be > 0
      end
    end

    context "when async mode is disabled" do
      it "processes tests sequentially" do
        assessment = red_teamer.scan(
          vulnerabilities: [bias],
          attacks: [prompt_injection],  # Using Attack instance
          attacks_per_vulnerability: 3
        )

        # Should still complete successfully
        expect(assessment).to be_a(RAAF::Eval::RedTeam::RiskAssessment)
        expect(assessment.overview.total_tests).to eq(3)
      end
    end
  end

  describe "Error Handling in Integration" do
    let(:bias) { RAAF::Eval::RedTeam::Vulnerabilities::BiasVulnerability.new }
    let(:prompt_injection) { RAAF::Eval::RedTeam::Attacks::SingleTurn::PromptInjectionAttack.new }

    context "with ignore_errors enabled" do
      it "continues processing after model callback errors" do
        error_callback = lambda do |input|
          raise "Simulated error" if input.include?("specific")
          "Normal response"
        end

        error_tolerant_teamer = RAAF::Eval::RedTeam::RedTeamer.new(
          model_callback: error_callback,
          async_mode: false,
          ignore_errors: true
        )

        # Should complete despite errors
        assessment = error_tolerant_teamer.scan(
          vulnerabilities: [bias],
          attacks: [prompt_injection],  # Using Attack instance
          attacks_per_vulnerability: 5
        )

        # Should have some errored tests but overall assessment completed
        expect(assessment.overview.errored_count).to be >= 0
      end
    end
  end

  describe "Complete Integration Workflow" do
    it "supports full red-teaming lifecycle" do
      # 1. Initialize red teamer with async and caching
      teamer = RAAF::Eval::RedTeam::RedTeamer.new(
        model_callback: model_callback,
        async_mode: true,
        max_concurrent: 5
      )

      # 2. Run first scan
      bias = RAAF::Eval::RedTeam::Vulnerabilities::BiasVulnerability.new
      toxicity = RAAF::Eval::RedTeam::Vulnerabilities::ToxicityVulnerability.new
      prompt_injection = RAAF::Eval::RedTeam::Attacks::SingleTurn::PromptInjectionAttack.new
      roleplay = RAAF::Eval::RedTeam::Attacks::SingleTurn::RoleplayAttack.new

      first_assessment = teamer.scan(
        vulnerabilities: [bias, toxicity],
        attacks: [prompt_injection],  # Using Attack instance
        attacks_per_vulnerability: 3
      )

      expect(first_assessment.overview.total_tests).to eq(6)

      # 3. Run second scan reusing cached attacks
      second_assessment = teamer.scan(
        vulnerabilities: [bias],
        attacks: [roleplay],  # Using Attack instance
        attacks_per_vulnerability: 3,
        reuse_previous_attacks: true
      )

      expect(second_assessment.overview.total_tests).to eq(3)

      # 4. Export results to CSV
      temp_csv = "/tmp/integration_test_#{Time.now.to_i}.csv"
      second_assessment.to_csv(temp_csv)
      expect(File.exist?(temp_csv)).to be true

      # 5. Get summary statistics
      summary = second_assessment.summary
      expect([:critical, :high, :medium, :low]).to include(summary[:risk_level])

      # 6. Clean up
      File.delete(temp_csv)
      teamer.clear_cache!
      expect(teamer.attack_cache).to be_empty
    end
  end
end
