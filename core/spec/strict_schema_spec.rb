# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenAIAgents::StrictSchema do
  describe ".ensure_strict_json_schema" do
    context "with object schema" do
      it "makes all properties required" do
        schema = {
          type: "object",
          properties: {
            name: { type: "string" },
            age: { type: "integer" },
            city: { type: "string" }
          },
          required: ["name"]
        }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["required"]).to contain_exactly("name", "age", "city")
      end

      it "sets additionalProperties to false" do
        schema = {
          type: "object",
          properties: {
            name: { type: "string" }
          }
        }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["additionalProperties"]).to be false
      end

      it "preserves existing additionalProperties: false" do
        schema = {
          type: "object",
          properties: {
            name: { type: "string" }
          },
          additionalProperties: false
        }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["additionalProperties"]).to be false
      end

      it "handles nested objects recursively" do
        schema = {
          type: "object",
          properties: {
            user: {
              type: "object",
              properties: {
                name: { type: "string" },
                email: { type: "string" }
              },
              required: ["name"]
            },
            settings: {
              type: "object",
              properties: {
                theme: { type: "string" },
                notifications: { type: "boolean" }
              }
            }
          }
        }

        result = described_class.ensure_strict_json_schema(schema)

        # Root level properties should be required
        expect(result["required"]).to contain_exactly("user", "settings")

        # Nested object properties should be required
        user_props = result["properties"]["user"]
        expect(user_props["required"]).to contain_exactly("name", "email")
        expect(user_props["additionalProperties"]).to be false

        settings_props = result["properties"]["settings"]
        expect(settings_props["required"]).to contain_exactly("theme", "notifications")
        expect(settings_props["additionalProperties"]).to be false
      end

      it "handles arrays with object items" do
        schema = {
          type: "object",
          properties: {
            items: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  id: { type: "string" },
                  value: { type: "number" }
                },
                required: ["id"]
              }
            }
          }
        }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["required"]).to contain_exactly("items")
        
        array_items = result["properties"]["items"]["items"]
        expect(array_items["required"]).to contain_exactly("id", "value")
        expect(array_items["additionalProperties"]).to be false
      end
    end

    context "with anyOf schemas" do
      it "processes all alternatives" do
        schema = {
          anyOf: [
            {
              type: "object",
              properties: {
                name: { type: "string" },
                age: { type: "integer" }
              }
            },
            {
              type: "object",
              properties: {
                title: { type: "string" },
                duration: { type: "number" }
              }
            }
          ]
        }

        result = described_class.ensure_strict_json_schema(schema)

        first_option = result["anyOf"][0]
        expect(first_option["required"]).to contain_exactly("name", "age")
        expect(first_option["additionalProperties"]).to be false

        second_option = result["anyOf"][1]
        expect(second_option["required"]).to contain_exactly("title", "duration")
        expect(second_option["additionalProperties"]).to be false
      end
    end

    context "with allOf schemas" do
      it "processes all schemas in allOf" do
        schema = {
          allOf: [
            {
              type: "object",
              properties: {
                name: { type: "string" }
              }
            },
            {
              type: "object",
              properties: {
                age: { type: "integer" }
              }
            }
          ]
        }

        result = described_class.ensure_strict_json_schema(schema)

        first_schema = result["allOf"][0]
        expect(first_schema["required"]).to contain_exactly("name")
        expect(first_schema["additionalProperties"]).to be false

        second_schema = result["allOf"][1]
        expect(second_schema["required"]).to contain_exactly("age")
        expect(second_schema["additionalProperties"]).to be false
      end
    end

    context "with non-object schemas" do
      it "returns array schemas unchanged" do
        schema = {
          type: "array",
          items: { type: "string" }
        }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["type"]).to eq("array")
        expect(result["items"]["type"]).to eq("string")
      end

      it "returns string schemas unchanged" do
        schema = {
          type: "string",
          pattern: "^[A-Za-z]+$"
        }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["type"]).to eq("string")
        expect(result["pattern"]).to eq("^[A-Za-z]+$")
      end

      it "returns primitive schemas unchanged" do
        schema = { type: "integer", minimum: 0 }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["type"]).to eq("integer")
        expect(result["minimum"]).to eq(0)
      end
    end

    context "with complex nested structures" do
      it "handles deeply nested objects" do
        schema = {
          type: "object",
          properties: {
            user: {
              type: "object",
              properties: {
                profile: {
                  type: "object",
                  properties: {
                    personal: {
                      type: "object",
                      properties: {
                        name: { type: "string" },
                        age: { type: "integer" }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        result = described_class.ensure_strict_json_schema(schema)

        # Check all levels are properly processed
        expect(result["required"]).to contain_exactly("user")
        expect(result["additionalProperties"]).to be false

        user_props = result["properties"]["user"]
        expect(user_props["required"]).to contain_exactly("profile")
        expect(user_props["additionalProperties"]).to be false

        profile_props = user_props["properties"]["profile"]
        expect(profile_props["required"]).to contain_exactly("personal")
        expect(profile_props["additionalProperties"]).to be false

        personal_props = profile_props["properties"]["personal"]
        expect(personal_props["required"]).to contain_exactly("name", "age")
        expect(personal_props["additionalProperties"]).to be false
      end

      it "handles arrays of objects with nested objects" do
        schema = {
          type: "object",
          properties: {
            orders: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  id: { type: "string" },
                  customer: {
                    type: "object",
                    properties: {
                      name: { type: "string" },
                      email: { type: "string" }
                    }
                  },
                  items: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        product: { type: "string" },
                        quantity: { type: "integer" }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        result = described_class.ensure_strict_json_schema(schema)

        # Root level
        expect(result["required"]).to contain_exactly("orders")

        # Order item level
        order_item = result["properties"]["orders"]["items"]
        expect(order_item["required"]).to contain_exactly("id", "customer", "items")
        expect(order_item["additionalProperties"]).to be false

        # Customer level
        customer_props = order_item["properties"]["customer"]
        expect(customer_props["required"]).to contain_exactly("name", "email")
        expect(customer_props["additionalProperties"]).to be false

        # Order item products level
        product_item = order_item["properties"]["items"]["items"]
        expect(product_item["required"]).to contain_exactly("product", "quantity")
        expect(product_item["additionalProperties"]).to be false
      end
    end

    context "with edge cases" do
      it "handles schemas without properties" do
        schema = {
          type: "object"
        }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["additionalProperties"]).to be false
        expect(result.key?("required")).to be false
      end

      it "handles empty properties" do
        schema = {
          type: "object",
          properties: {}
        }

        result = described_class.ensure_strict_json_schema(schema)

        expect(result["additionalProperties"]).to be false
        expect(result["required"]).to eq([])
      end

      it "preserves existing required array" do
        schema = {
          type: "object",
          properties: {
            name: { type: "string" },
            age: { type: "integer" },
            email: { type: "string" }
          },
          required: %w[name age]
        }

        result = described_class.ensure_strict_json_schema(schema)

        # All properties should be required in strict mode
        expect(result["required"]).to contain_exactly("name", "age", "email")
      end

      it "handles nil schema gracefully" do
        result = described_class.ensure_strict_json_schema(nil)
        expect(result["type"]).to eq("object")
        expect(result["additionalProperties"]).to be false
        expect(result["properties"]).to eq({})
        expect(result["required"]).to eq([])
      end

      it "handles non-hash schema gracefully" do
        expect do
          described_class.ensure_strict_json_schema("not a hash")
        end.to raise_error(TypeError, /Expected.*to be a hash/)
      end
    end
  end
end