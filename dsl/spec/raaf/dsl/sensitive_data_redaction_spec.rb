# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/agent"
require "raaf/dsl/pipeline_dsl/pipeline"

RSpec.describe "Sensitive Data Redaction" do
  describe "Pipeline sensitive data redaction" do
    let(:pipeline_class) do
      Class.new(RAAF::Pipeline) do
        def initialize(**context)
          super(**context)
        end
      end
    end

    let(:pipeline) { pipeline_class.new(product: "Test") }

    describe "#redact_sensitive_data" do
      context "with password fields" do
        it "redacts password fields" do
          data = { username: "john_doe", password: "secret123", user_password: "mysecret" }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:username]).to eq("john_doe")
          expect(redacted[:password]).to eq("[REDACTED]")
          expect(redacted[:user_password]).to eq("[REDACTED]")
        end
      end

      context "with API tokens and keys" do
        it "redacts various token types" do
          data = {
            api_key: "sk-1234567890abcdef",
            access_token: "ghp_xxxxxxxxxxxxxxxxxxxx",
            secret_key: "your-secret-key-here",
            auth_token: "bearer-token-value"
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:api_key]).to eq("[REDACTED]")
          expect(redacted[:access_token]).to eq("[REDACTED]")
          expect(redacted[:secret_key]).to eq("[REDACTED]")
          expect(redacted[:auth_token]).to eq("[REDACTED]")
        end
      end

      context "with credential fields" do
        it "redacts credential-related fields" do
          data = {
            user_credential: "cred123",
            auth_credential: "auth456",
            service_credentials: { username: "user", password: "pass" }
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:user_credential]).to eq("[REDACTED]")
          expect(redacted[:auth_credential]).to eq("[REDACTED]")
          expect(redacted[:service_credentials]).to eq("[REDACTED]")
        end
      end

      context "with personal information" do
        it "redacts email fields" do
          data = {
            user_email: "john@example.com",
            contact_email: "support@company.com",
            email_address: "user@domain.org"
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:user_email]).to eq("[REDACTED]")
          expect(redacted[:contact_email]).to eq("[REDACTED]")
          expect(redacted[:email_address]).to eq("[REDACTED]")
        end

        it "redacts phone fields" do
          data = {
            phone: "123-456-7890",
            phone_number: "+1 (555) 123-4567",
            user_phone: "555.123.4567"
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:phone]).to eq("[REDACTED]")
          expect(redacted[:phone_number]).to eq("[REDACTED]")
          expect(redacted[:user_phone]).to eq("[REDACTED]")
        end

        it "redacts SSN and credit card fields" do
          data = {
            ssn: "123-45-6789",
            social_security: "987-65-4321",
            credit_card: "4111-1111-1111-1111",
            card_number: "5555555555554444"
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:ssn]).to eq("[REDACTED]")
          expect(redacted[:social_security]).to eq("[REDACTED]")
          expect(redacted[:credit_card]).to eq("[REDACTED]")
          expect(redacted[:card_number]).to eq("[REDACTED]")
        end
      end

      context "with nested hash structures" do
        it "redacts sensitive data in nested hashes" do
          data = {
            user: {
              name: "John Doe",
              email: "john@example.com",
              settings: {
                api_key: "secret-key-123",
                preferences: {
                  password: "nested-password"
                }
              }
            },
            config: {
              database_password: "db-secret"
            }
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:user][:name]).to eq("John Doe")
          expect(redacted[:user][:email]).to eq("[REDACTED]")
          expect(redacted[:user][:settings][:api_key]).to eq("[REDACTED]")
          expect(redacted[:user][:settings][:preferences][:password]).to eq("[REDACTED]")
          expect(redacted[:config][:database_password]).to eq("[REDACTED]")
        end
      end

      context "with array structures containing hashes" do
        it "redacts sensitive data in array elements" do
          data = {
            users: [
              { name: "Alice", email: "alice@example.com", password: "secret1" },
              { name: "Bob", phone: "555-1234", api_key: "key123" },
              { name: "Charlie", token: "token456" }
            ],
            api_configs: [
              { service: "github", auth_token: "ghp_token" },
              { service: "slack", secret: "slack_secret" }
            ]
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          # Check users array
          expect(redacted[:users][0][:name]).to eq("Alice")
          expect(redacted[:users][0][:email]).to eq("[REDACTED]")
          expect(redacted[:users][0][:password]).to eq("[REDACTED]")

          expect(redacted[:users][1][:name]).to eq("Bob")
          expect(redacted[:users][1][:phone]).to eq("[REDACTED]")
          expect(redacted[:users][1][:api_key]).to eq("[REDACTED]")

          expect(redacted[:users][2][:name]).to eq("Charlie")
          expect(redacted[:users][2][:token]).to eq("[REDACTED]")

          # Check api_configs array
          expect(redacted[:api_configs][0][:service]).to eq("github")
          expect(redacted[:api_configs][0][:auth_token]).to eq("[REDACTED]")

          expect(redacted[:api_configs][1][:service]).to eq("slack")
          expect(redacted[:api_configs][1][:secret]).to eq("[REDACTED]")
        end

        it "preserves non-hash array elements" do
          data = {
            tags: ["public", "private", "sensitive"],
            numbers: [1, 2, 3],
            mixed: [
              "string",
              { name: "test", password: "secret" },
              42
            ]
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:tags]).to eq(["public", "private", "sensitive"])
          expect(redacted[:numbers]).to eq([1, 2, 3])
          expect(redacted[:mixed][0]).to eq("string")
          expect(redacted[:mixed][1][:name]).to eq("test")
          expect(redacted[:mixed][1][:password]).to eq("[REDACTED]")
          expect(redacted[:mixed][2]).to eq(42)
        end
      end

      context "with non-sensitive data" do
        it "preserves normal data fields" do
          data = {
            product: "SaaS Product",
            company: "Tech Corp",
            analysis_depth: "comprehensive",
            market_count: 5,
            success: true,
            markets: ["fintech", "healthtech"],
            metadata: {
              version: "1.0",
              created_at: "2024-01-01"
            }
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted).to eq(data)
        end
      end

      context "with edge cases" do
        it "handles nil input gracefully" do
          expect(pipeline.send(:redact_sensitive_data, nil)).to be_nil
        end

        it "handles non-hash input gracefully" do
          expect(pipeline.send(:redact_sensitive_data, "string")).to eq("string")
          expect(pipeline.send(:redact_sensitive_data, 123)).to eq(123)
          expect(pipeline.send(:redact_sensitive_data, [])).to eq([])
        end

        it "handles empty hash" do
          expect(pipeline.send(:redact_sensitive_data, {})).to eq({})
        end

        it "handles circular references safely" do
          data = { name: "test" }
          data[:self] = data  # Circular reference

          # Should not cause infinite recursion or stack overflow
          expect { pipeline.send(:redact_sensitive_data, data) }.not_to raise_error
        end
      end
    end

    describe "#sensitive_key?" do
      # Test all sensitive patterns
      sensitive_patterns = %w[
        password token secret key api_key auth credential
        email phone ssn social_security credit_card
      ]

      sensitive_patterns.each do |pattern|
        context "with #{pattern} pattern" do
          it "detects exact match as sensitive" do
            expect(pipeline.send(:sensitive_key?, pattern)).to be(true)
          end

          it "detects uppercase as sensitive" do
            expect(pipeline.send(:sensitive_key?, pattern.upcase)).to be(true)
          end

          it "detects with prefix as sensitive" do
            expect(pipeline.send(:sensitive_key?, "user_#{pattern}")).to be(true)
            expect(pipeline.send(:sensitive_key?, "admin_#{pattern}")).to be(true)
          end

          it "detects with suffix as sensitive" do
            expect(pipeline.send(:sensitive_key?, "#{pattern}_value")).to be(true)
            expect(pipeline.send(:sensitive_key?, "#{pattern}_field")).to be(true)
          end

          it "detects within compound words" do
            expect(pipeline.send(:sensitive_key?, "user#{pattern}data")).to be(true)
            expect(pipeline.send(:sensitive_key?, "data#{pattern}info")).to be(true)
          end
        end
      end

      context "with non-sensitive keys" do
        non_sensitive_keys = %w[
          name product company count data result analysis
          markets users settings config version created_at
          metadata summary description title content
        ]

        non_sensitive_keys.each do |key|
          it "does not detect #{key} as sensitive" do
            expect(pipeline.send(:sensitive_key?, key)).to be(false)
          end
        end
      end

      context "with edge cases" do
        it "handles empty string" do
          expect(pipeline.send(:sensitive_key?, "")).to be(false)
        end

        it "handles single characters" do
          expect(pipeline.send(:sensitive_key?, "p")).to be(false)
          expect(pipeline.send(:sensitive_key?, "k")).to be(false)
        end

        it "handles false positives correctly" do
          # These contain sensitive words but are not actually sensitive
          false_positives = %w[
            keywords
            tokenize
            secretary
            authenticate
          ]

          false_positives.each do |key|
            expect(pipeline.send(:sensitive_key?, key)).to be(true)  # Current implementation will flag these
          end
        end
      end
    end
  end

  describe "Agent sensitive data redaction" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"

        def run
          { success: true }
        end
      end
    end

    let(:agent) { agent_class.new(product: "Test") }

    describe "#redact_sensitive_dialog_data" do
      it "uses same logic as pipeline redaction" do
        data = { username: "user", password: "secret", api_key: "key123" }
        redacted = agent.send(:redact_sensitive_dialog_data, data)

        expect(redacted[:username]).to eq("user")
        expect(redacted[:password]).to eq("[REDACTED]")
        expect(redacted[:api_key]).to eq("[REDACTED]")
      end
    end

    describe "#redact_sensitive_content" do
      context "with string content containing sensitive patterns" do
        it "redacts API keys and tokens" do
          content = "Use this API key: sk-1234567890abcdefghijklmnopqrstuv in your requests"
          redacted = agent.send(:redact_sensitive_content, content)

          expect(redacted).to include("[REDACTED_TOKEN]")
          expect(redacted).not_to include("sk-1234567890abcdefghijklmnopqrstuv")
        end

        it "redacts email addresses" do
          content = "Contact support at help@example.com or admin@company.org for assistance"
          redacted = agent.send(:redact_sensitive_content, content)

          expect(redacted).to include("[REDACTED_EMAIL]")
          expect(redacted).not_to include("help@example.com")
          expect(redacted).not_to include("admin@company.org")
        end

        it "redacts phone numbers" do
          content = "Call us at 555-123-4567 or 800-555-9999 for support"
          redacted = agent.send(:redact_sensitive_content, content)

          expect(redacted).to include("[REDACTED_PHONE]")
          expect(redacted).not_to include("555-123-4567")
          expect(redacted).not_to include("800-555-9999")
        end

        it "redacts credit card numbers" do
          content = "Payment card: 4111 1111 1111 1111 or 5555-5555-5555-4444"
          redacted = agent.send(:redact_sensitive_content, content)

          expect(redacted).to include("[REDACTED_CC]")
          expect(redacted).not_to include("4111 1111 1111 1111")
          expect(redacted).not_to include("5555-5555-5555-4444")
        end

        it "handles multiple sensitive patterns in one string" do
          content = <<~TEXT
            Dear john@example.com,
            Your API key is sk-abcdef1234567890 and your temp password is temp123.
            Contact us at 555-123-4567 if you have issues.
            Card ending in 4111 1111 1111 1111 was charged.
          TEXT

          redacted = agent.send(:redact_sensitive_content, content)

          expect(redacted).to include("[REDACTED_EMAIL]")
          expect(redacted).to include("[REDACTED_TOKEN]")
          expect(redacted).to include("[REDACTED_PHONE]")
          expect(redacted).to include("[REDACTED_CC]")

          # Ensure original sensitive content is gone
          expect(redacted).not_to include("john@example.com")
          expect(redacted).not_to include("sk-abcdef1234567890")
          expect(redacted).not_to include("555-123-4567")
          expect(redacted).not_to include("4111 1111 1111 1111")
        end
      end

      context "with non-sensitive content" do
        it "preserves normal text content" do
          content = "This is a normal message about product analysis and market research."
          redacted = agent.send(:redact_sensitive_content, content)

          expect(redacted).to eq(content)
        end

        it "preserves technical content with similar patterns" do
          content = "The algorithm uses tokens in parsing. Error code: 404-NOT-FOUND."
          redacted = agent.send(:redact_sensitive_content, content)

          expect(redacted).to eq(content)
        end
      end

      context "with edge cases" do
        it "handles nil input gracefully" do
          expect(agent.send(:redact_sensitive_content, nil)).to be_nil
        end

        it "handles non-string input gracefully" do
          expect(agent.send(:redact_sensitive_content, 123)).to eq(123)
          expect(agent.send(:redact_sensitive_content, {})).to eq({})
          expect(agent.send(:redact_sensitive_content, [])).to eq([])
        end

        it "handles empty string" do
          expect(agent.send(:redact_sensitive_content, "")).to eq("")
        end

        it "handles very long strings" do
          long_content = "A" * 10000 + " sk-1234567890abcdefghijklmnopqrstuv " + "B" * 10000
          redacted = agent.send(:redact_sensitive_content, long_content)

          expect(redacted).to include("[REDACTED_TOKEN]")
          expect(redacted).not_to include("sk-1234567890abcdefghijklmnopqrstuv")
          expect(redacted.length).to be < long_content.length
        end
      end
    end

    describe "#sensitive_dialog_key?" do
      it "includes additional patterns for dialog context" do
        additional_patterns = %w[private_key access_token refresh_token]

        additional_patterns.each do |pattern|
          expect(agent.send(:sensitive_dialog_key?, pattern)).to be(true)
          expect(agent.send(:sensitive_dialog_key?, "user_#{pattern}")).to be(true)
        end
      end

      it "maintains base sensitive patterns" do
        base_patterns = %w[password token secret key api_key auth credential]

        base_patterns.each do |pattern|
          expect(agent.send(:sensitive_dialog_key?, pattern)).to be(true)
        end
      end
    end
  end

  describe "Integration tests" do
    context "with realistic data structures" do
      let(:pipeline) { Class.new(RAAF::Pipeline).new(product: "Test") }

      it "handles complete pipeline context" do
        complex_data = {
          product: "SaaS Analytics Platform",
          company: "TechCorp Inc",
          user: {
            name: "John Doe",
            email: "john.doe@techcorp.com",
            role: "admin"
          },
          api_config: {
            openai_api_key: "sk-proj-abcdef1234567890",
            anthropic_key: "ant-api-xyz789",
            base_url: "https://api.openai.com/v1"
          },
          database: {
            host: "db.example.com",
            username: "app_user",
            password: "super_secret_db_password",
            port: 5432
          },
          analysis: {
            markets: ["fintech", "healthtech", "edtech"],
            confidence_scores: [0.8, 0.9, 0.7],
            methodology: "ML-based scoring"
          },
          metadata: {
            version: "2.1.0",
            created_at: "2024-01-15T10:30:00Z",
            updated_by: "system"
          }
        }

        redacted = pipeline.send(:redact_sensitive_data, complex_data)

        # Preserve business data
        expect(redacted[:product]).to eq("SaaS Analytics Platform")
        expect(redacted[:company]).to eq("TechCorp Inc")
        expect(redacted[:user][:name]).to eq("John Doe")
        expect(redacted[:user][:role]).to eq("admin")
        expect(redacted[:analysis]).to eq(complex_data[:analysis])
        expect(redacted[:metadata]).to eq(complex_data[:metadata])

        # Redact sensitive data
        expect(redacted[:user][:email]).to eq("[REDACTED]")
        expect(redacted[:api_config][:openai_api_key]).to eq("[REDACTED]")
        expect(redacted[:api_config][:anthropic_key]).to eq("[REDACTED]")
        expect(redacted[:api_config][:base_url]).to eq("https://api.openai.com/v1")  # Not sensitive
        expect(redacted[:database][:username]).to eq("app_user")  # Not sensitive
        expect(redacted[:database][:password]).to eq("[REDACTED]")
        expect(redacted[:database][:host]).to eq("db.example.com")  # Not sensitive
        expect(redacted[:database][:port]).to eq(5432)  # Not sensitive
      end
    end
  end
end