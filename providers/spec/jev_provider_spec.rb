# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::JevProvider do
  subject(:provider) { described_class.new(api_key: "test-key") }

  let(:endpoint) { "https://api.typesafe.ai/v1/systemone" }
  let(:ticket) { "I've been trying to connect my Stripe account for 3 days and it keeps failing." }
  let(:urgency) do
    RAAF::Models::Decision::Noul.new(instructions: "The message conveys urgency or time-sensitivity")
  end

  def stub_systemone(body, status: 200, headers: {})
    stub_request(:post, endpoint).to_return(
      status: status,
      body: body.is_a?(String) ? body : body.to_json,
      headers: { "Content-Type" => "application/json" }.merge(headers)
    )
  end

  def answers(body)
    { "model" => "jev-1", "usage" => { "input_tokens" => 42, "output_tokens" => 3 }, "answers" => body }
  end

  describe "#initialize" do
    it "reads the API key from TYPESAFE_API_KEY" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("TYPESAFE_API_KEY", nil).and_return("from-env")

      expect(described_class.new.instance_variable_get(:@api_key)).to eq("from-env")
    end

    it "raises without an API key" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("TYPESAFE_API_KEY", nil).and_return(nil)

      expect { described_class.new }.to raise_error(RAAF::Models::AuthenticationError, /API key is required/)
    end

    it "defaults to the jev-latest model" do
      expect(provider.model).to eq("jev-latest")
    end

    it "does not restrict model ids" do
      expect(provider.supported_models).to eq([])
    end
  end

  describe "#decide" do
    it "sends the state and the questions" do
      stub_systemone(answers("is_urgent" => { "type" => "noul", "noul" => 0.999 }))

      provider.decide(state: ticket, questions: { is_urgent: urgency })

      expect(a_request(:post, endpoint).with do |request|
        body = JSON.parse(request.body)
        body["model"] == "jev-latest" &&
          body["state"] == ticket &&
          body["questions"] == {
            "is_urgent" => {
              "type" => "noul",
              "instructions" => "The message conveys urgency or time-sensitivity"
            }
          }
      end).to have_been_made
    end

    it "sends a choice's options as criteria" do
      stub_systemone(answers("team" => {
                               "type" => "choice",
                               "choice" => "billing",
                               "confidence" => 0.8,
                               "probabilities" => { "billing" => 0.8, "engineering" => 0.2 }
                             }))

      provider.decide(
        state: ticket,
        questions: {
          team: RAAF::Models::Decision::Choice.new(
            instructions: "Which team should handle this?",
            criteria: { billing: "Payment or subscription issues", engineering: "Bugs" }
          )
        }
      )

      expect(a_request(:post, endpoint).with do |request|
        JSON.parse(request.body)["questions"]["team"]["criteria"] ==
          { "billing" => "Payment or subscription issues", "engineering" => "Bugs" }
      end).to have_been_made
    end

    it "authenticates with a bearer token" do
      stub_systemone(answers("is_urgent" => { "type" => "noul", "noul" => 0.9 }))

      provider.decide(state: ticket, questions: { is_urgent: urgency })

      expect(a_request(:post, endpoint)
        .with(headers: { "Authorization" => "Bearer test-key", "Content-Type" => "application/json" }))
        .to have_been_made
    end

    it "reads the answers, the model, the usage and the request id" do
      stub_systemone(
        answers("is_urgent" => { "type" => "noul", "noul" => 0.999 }),
        headers: { "x-typesafe-request-id" => "req_123" }
      )

      result = provider.decide(state: ticket, questions: { is_urgent: urgency })

      expect(result[:is_urgent].probability).to eq(0.999)
      expect(result.model).to eq("jev-1")
      expect(result.usage).to eq("input_tokens" => 42, "output_tokens" => 3)
      expect(result.request_id).to eq("req_123")
      expect(result.provider).to eq("Jev")
    end

    it "reads a score's probabilities and legend by level index" do
      stub_systemone(answers("frustration" => {
                               "type" => "score",
                               "score" => 1.6,
                               "confidence" => 0.7,
                               "legend" => { "0" => "Calm", "1" => "Civil", "2" => "Angry" },
                               "probabilities" => { "0" => 0.05, "1" => 0.3, "2" => 0.65 }
                             }))

      result = provider.decide(
        state: ticket,
        questions: {
          frustration: RAAF::Models::Decision::Score.new(
            instructions: "How frustrated is the customer?",
            criteria: %w[Calm Civil Angry]
          )
        }
      )

      expect(result[:frustration].score).to eq(1.6)
      expect(result[:frustration].level).to eq("Angry")
      expect(result[:frustration].probabilities).to eq(0 => 0.05, 1 => 0.3, 2 => 0.65)
    end

    it "answers several questions from one request" do
      stub_systemone(answers(
                       "is_urgent" => { "type" => "noul", "noul" => 0.95 },
                       "team" => {
                         "type" => "choice",
                         "choice" => "billing",
                         "confidence" => 0.8,
                         "probabilities" => { "billing" => 0.8, "engineering" => 0.2 }
                       }
                     ))

      result = provider.decide(
        state: ticket,
        questions: {
          is_urgent: urgency,
          team: RAAF::Models::Decision::Choice.new(
            instructions: "Which team should handle this?",
            criteria: %w[billing engineering]
          )
        }
      )

      expect(result[:is_urgent].probability).to eq(0.95)
      expect(result[:team].option).to eq("billing")
      expect(a_request(:post, endpoint)).to have_been_made.once
    end

    it "still reads answers sent without an envelope" do
      stub_systemone({ "model" => "jev-1", "is_urgent" => { "type" => "noul", "noul" => 0.7 } })

      result = provider.decide(state: ticket, questions: { is_urgent: urgency })

      expect(result[:is_urgent].probability).to eq(0.7)
    end

    it "raises when a question goes unanswered" do
      stub_systemone(answers("something_else" => { "type" => "noul", "noul" => 0.5 }))

      expect { provider.decide(state: ticket, questions: { is_urgent: urgency }) }
        .to raise_error(RAAF::Models::Decision::MalformedAnswerError, /did not answer question "is_urgent"/)
    end
  end

  describe "#noul" do
    it "returns the answer for a one-question request" do
      stub_systemone(answers("answer" => { "type" => "noul", "noul" => 0.999 }))

      answer = provider.noul(state: ticket, instructions: "The message conveys urgency")

      expect(answer.probability).to eq(0.999)
      expect(answer).to be_true
    end
  end

  describe "error handling" do
    it "raises AuthenticationError on 401" do
      stub_systemone({ "error" => { "message" => "bad key" } }, status: 401)

      expect { provider.noul(state: ticket, instructions: "x") }
        .to raise_error(RAAF::Models::AuthenticationError, /Invalid Jev API key/)
    end

    it "raises AuthenticationError on 403" do
      stub_systemone({ "error" => { "message" => "forbidden" } }, status: 403)

      expect { provider.noul(state: ticket, instructions: "x") }
        .to raise_error(RAAF::Models::AuthenticationError)
    end

    it "raises RateLimitError on 429, preferring the millisecond header" do
      stub_request(:post, endpoint).to_return(
        status: 429,
        body: "{}",
        headers: { "Content-Type" => "application/json", "Retry-After-Ms" => "250", "Retry-After" => "12" }
      )

      expect { provider.noul(state: ticket, instructions: "x") }
        .to raise_error(RAAF::Models::RateLimitError, /Retry after: 250/)
    end

    it "surfaces the API's message on a 400" do
      stub_systemone({ "error" => { "message" => "unknown question type" } }, status: 400)

      expect { provider.noul(state: ticket, instructions: "x") }
        .to raise_error(RAAF::Models::APIError, /unknown question type/)
    end

    # The API is FastAPI-shaped, so a validation failure arrives as a detail
    # array that reads as nothing useful unless it is walked.
    it "walks a validation detail array" do
      stub_systemone(
        { "detail" => [{ "loc" => %w[body questions team criteria], "msg" => "field required" }] },
        status: 422
      )

      expect { provider.noul(state: ticket, instructions: "x") }
        .to raise_error(RAAF::Models::APIError, /questions\.team\.criteria: field required/)
    end

    it "tolerates a non-JSON error body" do
      stub_systemone("<html>nope</html>", status: 400)

      expect { provider.noul(state: ticket, instructions: "x") }
        .to raise_error(RAAF::Models::APIError, /nope/)
    end
  end
end
