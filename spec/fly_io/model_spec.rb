# frozen_string_literal: true

RSpec.describe FlyIO::Model do
  it "coerces referenced nested values while preserving unknown fields and exact wire keys" do
    model = FlyIO::Models::App.new(
      "id" => "app-id",
      "organization" => {"slug" => "personal"},
      "future_field" => {"CamelCase" => true}
    )

    expect(model.id).to eq("app-id")
    expect(model.organization).to be_a(FlyIO::Models::AppOrganizationInfo)
    expect(model.organization.slug).to eq("personal")
    expect(model["future_field"]).to eq("CamelCase" => true)
    expect(model.to_h).to include("future_field" => {"CamelCase" => true})
    expect(model).to respond_to(:id)
    expect(model).not_to respond_to(:not_present)
    expect(model).to be_frozen
  end

  it "supports schema names that are not valid Ruby constants through deterministic generated classes" do
    name = "fly.ContainerConfig"
    ruby_name = FlyIO::SchemaRegistry.schemas.fetch(name).fetch("x-ruby-class")
    model = FlyIO::SchemaRegistry.build(name, "image" => "registry.example/image")

    expect(model).to be_a(FlyIO::Models.const_get(ruby_name))
    expect(model.schema_name).to eq(name)
  end

  it "compares models by schema and values and rejects non-hash attributes" do
    expect(FlyIO::Models::App.new("id" => "a")).to eq(FlyIO::Models::App.new("id" => "a"))
    expect(FlyIO::Models::App.new("id" => "a")).not_to eq(FlyIO::Models::App.new("id" => "b"))
    expect { FlyIO::Models::App.new("invalid") }.to raise_error(FlyIO::ArgumentError)
  end

  it "validates documented required fields, types, enums, and arrays" do
    schema = {"type" => "object", "required" => ["kind"], "properties" => {
      "kind" => {"type" => "string", "enum" => ["one"]},
      "items" => {"type" => "array", "items" => {"type" => "integer"}}
    }}

    expect { FlyIO::SchemaValidator.validate!(schema, {}) }.to raise_error(FlyIO::ArgumentError, /kind is required/)
    expect { FlyIO::SchemaValidator.validate!(schema, {kind: "two"}) }.to raise_error(FlyIO::ArgumentError, /one of/)
    expect do
      FlyIO::SchemaValidator.validate!(schema, {kind: "one", items: ["bad"]})
    end.to raise_error(FlyIO::ArgumentError, /integer/)
    expect(FlyIO::SchemaValidator.validate!(schema, {kind: "one", items: [1]})).to be(true)
  end
end
