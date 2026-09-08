# frozen_string_literal: true

RSpec.describe "Structural Matchers" do
  let(:json_output) { '{"name": "Ruby", "type": "programming language", "version": 3.3}' }
  let(:invalid_json_output) { '{"name": "Ruby", "type":' }
  let(:xml_output) { "<language><name>Ruby</name></language>" }
  let(:invalid_xml_output) { "<language><name>Ruby</name>" }
  let(:html_output) { "<html><body><h1>Ruby</h1></body></html>" }
  let(:markdown_output) { "# Ruby\n\n## Overview\n\nRuby is a programming language." }
  let(:short_output) { "Short text" }
  let(:long_output) { "A" * 1000 }

  let(:baseline_span) do
    {
      id: "structural_test",
      output: json_output,
      metadata: { output: json_output }
    }
  end

  let(:json_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
                                test: { success: true, output: json_output }
                              })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  let(:invalid_json_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
                                test: { success: true, output: invalid_json_output }
                              })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  let(:xml_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
                                test: { success: true, output: xml_output }
                              })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  let(:invalid_xml_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
                                test: { success: true, output: invalid_xml_output }
                              })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  let(:html_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
                                test: { success: true, output: html_output }
                              })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  describe "have_valid_format matcher" do
    it "validates JSON format" do
      expect(json_result).to have_valid_format.as(:json)
    end

    it "detects invalid JSON" do
      expect do
        expect(invalid_json_result).to have_valid_format.as(:json)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear error message for invalid JSON" do
      expect(invalid_json_result).to have_valid_format.as(:json)
    rescue RSpec::Expectations::ExpectationNotMetError => e
      expect(e.message).to include("json")
      expect(e.message).to include("validation failed")
    end

    it "validates XML format" do
      expect(xml_result).to have_valid_format.as(:xml)
    end

    it "detects invalid XML" do
      expect do
        expect(invalid_xml_result).to have_valid_format.as(:xml)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "validates HTML format" do
      expect(html_result).to have_valid_format.as(:html)
    end

    it "validates markdown format" do
      markdown_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      markdown_result.instance_variable_set(:@results, {
                                              test: { success: true, output: markdown_output }
                                            })
      markdown_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: markdown_result, baseline: baseline_span)

      expect(result).to have_valid_format.as(:markdown)
    end

    it "defaults to text format (always valid)" do
      any_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      any_result.instance_variable_set(:@results, {
                                         test: { success: true, output: "any text" }
                                       })
      any_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: any_result, baseline: baseline_span)

      expect(result).to have_valid_format
    end

    context "when negated" do
      it "fails when format is valid" do
        expect do
          expect(json_result).not_to have_valid_format.as(:json)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
      end

      it "provides clear negated failure message" do
        expect(json_result).not_to have_valid_format.as(:json)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("invalid")
        expect(e.message).to include("valid")
      end
    end
  end

  describe "match_schema matcher" do
    let(:schema) { { name: String, type: String, version: Float } }

    it "validates output against schema" do
      expect(json_result).to match_schema(schema)
    end

    it "detects missing fields" do
      incomplete_schema = { name: String, missing_field: String }

      expect do
        expect(json_result).to match_schema(incomplete_schema)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "detects wrong field types" do
      wrong_type_schema = { name: Integer, type: String, version: Float }

      expect do
        expect(json_result).to match_schema(wrong_type_schema)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear error message for missing fields" do
      incomplete_schema = { name: String, missing_field: String }

      begin
        expect(json_result).to match_schema(incomplete_schema)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("Missing required field")
        expect(e.message).to include("missing_field")
      end
    end

    it "provides clear error message for wrong types" do
      wrong_type_schema = { name: Integer }

      begin
        expect(json_result).to match_schema(wrong_type_schema)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("wrong type")
        expect(e.message).to include("Expected Integer")
        expect(e.message).to include("got String")
      end
    end

    it "handles invalid JSON" do
      expect do
        expect(invalid_json_result).to match_schema(schema)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    context "when negated" do
      it "fails when schema matches" do
        expect do
          expect(json_result).not_to match_schema(schema)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
      end

      it "provides clear negated failure message" do
        expect(json_result).not_to match_schema(schema)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("not match schema")
        expect(e.message).to include("it did")
      end
    end
  end

  describe "have_length matcher" do
    let(:short_result) do
      run = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      run.instance_variable_set(:@results, {
                                  test: { success: true, output: short_output }
                                })
      run.instance_variable_set(:@executed, true)
      RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
    end

    let(:long_result) do
      run = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      run.instance_variable_set(:@results, {
                                  test: { success: true, output: long_output }
                                })
      run.instance_variable_set(:@executed, true)
      RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
    end

    it "checks length within range" do
      expect(short_result).to have_length.between(5, 20)
    end

    it "fails when length outside range" do
      expect do
        expect(long_result).to have_length.between(5, 20)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "checks length less than maximum" do
      expect(short_result).to have_length.less_than(100)
    end

    it "fails when length exceeds maximum" do
      expect do
        expect(long_result).to have_length.less_than(100)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "checks length greater than minimum" do
      expect(long_result).to have_length.greater_than(500)
    end

    it "fails when length below minimum" do
      expect do
        expect(short_result).to have_length.greater_than(500)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "checks exact length" do
      exact_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      exact_result.instance_variable_set(:@results, {
                                           test: { success: true, output: ("exactly_50_characters" * 2) + "12345678" }
                                         })
      exact_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: exact_result, baseline: baseline_span)

      expect(result).to have_length.of(50)
    end

    it "provides clear failure message with actual length" do
      expect(long_result).to have_length.between(5, 20)
    rescue RSpec::Expectations::ExpectationNotMetError => e
      expect(e.message).to include("Expected length between")
      expect(e.message).to include("1000")
    end

    it "defaults to non-zero length check" do
      expect(short_result).to have_length
    end

    it "handles empty output" do
      empty_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      empty_result.instance_variable_set(:@results, {
                                           test: { success: true, output: "" }
                                         })
      empty_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: empty_result, baseline: baseline_span)

      expect do
        expect(result).to have_length.greater_than(0)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    context "when negated" do
      it "provides clear negated failure message" do
        expect(short_result).not_to have_length.between(5, 20)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("not match criteria")
      end
    end
  end

  describe "edge cases and integration" do
    it "handles failed evaluations" do
      failed_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      failed_result.instance_variable_set(:@results, {
                                            test: { success: false, error: "Test error" }
                                          })
      failed_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: failed_result, baseline: baseline_span)

      # Should handle gracefully with empty output
      expect(result).to have_length.of(0)
    end

    it "can chain structural matchers" do
      expect(json_result).to have_valid_format.as(:json).and match_schema({ name: String })
    end
  end
end
