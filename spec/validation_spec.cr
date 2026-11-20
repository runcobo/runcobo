require "./spec_helper"

class IdContract < RequestValidation::Contract
  schema do
    required :id, Int64
  end
end

class ContractQuerySpec < BaseAction
  get "/contracts/query"
  query IdContract

  call do
    render_json({id: input.id})
  end
end

class ContractFormSpec < BaseAction
  post "/contracts/form"
  form IdContract

  call do
    render_json({id: input.id})
  end
end

class ContractUrlSpec < BaseAction
  get "/contracts/url/:id"
  url IdContract

  call do
    render_json({id: input.id})
  end
end

class ProfileContract < RequestValidation::Contract
  schema do
    required :name, String
    required :active, Bool
    optional :age, Int32
    optional :bio, String, nullable: true
  end

  rule :name do |name, errors|
    if name.empty?
      errors.add(:name, :too_short, {"min" => 1_i64} of String => RequestValidation::ErrorParam)
    end
  end
end

class ContractJsonSpec < BaseAction
  post "/contracts/json"
  json ProfileContract

  call do
    render_json({name: input.name, active: input.active, age: input.age,
                 bio: input.bio, bio_present: input.bio_present?})
  end
end

class ContractMultipleSpec < BaseAction
  post "/contracts/multiple/:id"
  url IdContract
  query IdContract
  json ProfileContract

  call do
    render_json({url_id: url_input.id, query_id: query_input.id, name: json_input.name})
  end
end

class ContractStripSpec < BaseAction
  get "/contracts/strip"
  query IdContract, unknown_keys: :strip

  call do
    render_json({id: input.id})
  end
end

abstract class ContractInheritedBaseSpec < BaseAction
  query IdContract
end

class ContractInheritedSpec < ContractInheritedBaseSpec
  get "/contracts/inherited"

  call do
    render_json({id: input.id})
  end
end

class ContractInheritedMultipleSpec < ContractInheritedBaseSpec
  post "/contracts/inherited-multiple"
  json ProfileContract

  call do
    render_json({id: query_input.id, name: json_input.name})
  end
end

class ContractLimitedSpec < BaseAction
  post "/contracts/limited"
  json IdContract

  def max_request_body_size : Int64
    8_i64
  end

  call do
    render_json({id: input.id})
  end
end

CONTRACT_EVENTS = [] of String

class EventContract < RequestValidation::Contract
  schema do
    required :id, Int64
  end

  rule :id do |id, errors|
    CONTRACT_EVENTS << "validation"
  end
end

class ContractLifecycleSpec < BaseAction
  post "/contracts/lifecycle"
  json EventContract
  before_request early_check
  before record_before
  after record_after

  def early_check
    CONTRACT_EVENTS << "early"
    if request.headers["Deny"]?
      render_plain "denied", status_code: 401
      byebye
    end
  end

  def record_before
    CONTRACT_EVENTS << "before"
  end

  def record_after
    CONTRACT_EVENTS << "after"
  end

  call do
    CONTRACT_EVENTS << "body"
    render_json({id: input.id, again: input.id})
  end
end

class ContractSkipSpec < ContractLifecycleSpec
  post "/contracts/skip"
  skip early_check
end

class UnreadableContractBody < IO
  def read(slice : Bytes) : Int32
    raise "Request body must not be read"
  end

  def write(slice : Bytes) : Nil
    raise "Not writable"
  end
end

class ExplodingContract < RequestValidation::Contract
  schema do
    required :id, Int64
  end

  rule :id do |id, errors|
    raise "contract programming error"
  end
end

class ContractExceptionSpec < BaseAction
  get "/contracts/exception"
  query ExplodingContract

  call do
    render_plain "unreachable"
  end
end

class ContractCustomErrorsSpec < BaseAction
  get "/contracts/custom-errors"
  query IdContract

  protected def render_validation_errors(issues : Array(Runcobo::Validation::Issue), *, status_code : Int32) : HTTP::Server::Context
    render_json({codes: issues.map(&.code)}, status_code: status_code)
  end

  call do
    render_plain "valid"
  end
end

class MinimumIdContract < RequestValidation::Contract
  def initialize(@minimum : Int64, unknown_keys : RequestValidation::UnknownKeys = :reject)
    super(unknown_keys: unknown_keys)
  end

  schema do
    required :id, Int64
  end

  rule :id do |id, errors|
    errors.add(:id, :too_small) if id < @minimum
  end
end

class ContractFactorySpec < BaseAction
  get "/contracts/factory"
  query MinimumIdContract

  protected def build_query_contract
    MinimumIdContract.new(10_i64)
  end

  call do
    render_json({id: input.id})
  end
end

class ConfirmationContract < RequestValidation::Contract
  schema do
    required :password, String
    required :confirmation, String
  end

  rule :password, :confirmation do |password, confirmation, errors|
    errors.add(:confirmation, :does_not_match) unless password == confirmation
  end
end

class ContractConfirmationSpec < BaseAction
  post "/contracts/confirmation"
  form ConfirmationContract

  call do
    render_plain "confirmed"
  end
end

class BooleanQueryContract < RequestValidation::Contract
  schema do
    required :active, Bool
    optional :amount, Float64
  end
end

class ContractBooleanSpec < BaseAction
  get "/contracts/boolean"
  query BooleanQueryContract

  call do
    render_json({active: input.active, amount: input.amount})
  end
end

private def validation_request(method : String, path : String, body : String | IO | Nil = nil,
                               headers = HTTP::Headers.new)
  request = HTTP::Request.new(method, path, headers, body)
  output = IO::Memory.new
  response = HTTP::Server::Response.new(output)
  context = HTTP::Server::Context.new(request, response)
  Runcobo::RouteHandler.new.call(context)
  response.close
  output.rewind
  HTTP::Client::Response.from_io(output)
end

describe "request contracts" do
  before_each { CONTRACT_EVENTS.clear }

  it "converts query input to a concrete output" do
    response = validation_request("GET", "/contracts/query?id=42")
    response.status_code.should eq(200)
    JSON.parse(response.body)["id"].as_i64.should eq(42_i64)
  end

  it "returns structured validation errors" do
    response = validation_request("GET", "/contracts/query?id=bad")
    response.status_code.should eq(422)
    error = JSON.parse(response.body)["errors"][0]
    error["source"].as_s.should eq("query")
    error["path"].as_a.map(&.as_s).should eq(["id"])
    error["code"].as_s.should eq("invalid_type")
    error["params"]["expected"].as_s.should eq("Int64")
    response.body.should_not contain("bad")
  end

  it "reports missing and unexpected fields together" do
    response = validation_request("GET", "/contracts/query?extra=secret")
    response.status_code.should eq(422)
    codes = JSON.parse(response.body)["errors"].as_a.map { |error| error["code"].as_s }
    codes.should contain("missing")
    codes.should contain("unexpected_key")
    response.body.should_not contain("secret")
  end

  it "rejects repeated scalar query parameters rather than silently choosing one" do
    response = validation_request("GET", "/contracts/query?id=1&id=2")
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("multiple_values")
  end

  it "rejects integer overflow" do
    response = validation_request("GET", "/contracts/query?id=9223372036854775808")
    response.status_code.should eq(422)
  end

  it "allows explicitly stripping unknown query fields" do
    response = validation_request("GET", "/contracts/strip?id=42&extra=value")
    response.status_code.should eq(200)
    JSON.parse(response.body)["id"].as_i.should eq(42)
  end

  it "converts path parameters" do
    response = validation_request("GET", "/contracts/url/42")
    response.status_code.should eq(200)
    JSON.parse(response.body)["id"].as_i.should eq(42)
  end

  it "reports the path source for invalid path parameters" do
    response = validation_request("GET", "/contracts/url/nope")
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"][0]["source"].as_s.should eq("url")
  end

  it "converts form values and accepts media type parameters" do
    response = validation_request("POST", "/contracts/form", "id=42",
      HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded; charset=utf-8"})
    response.status_code.should eq(200)
    JSON.parse(response.body)["id"].as_i.should eq(42)
  end

  it "rejects repeated form fields" do
    response = validation_request("POST", "/contracts/form", "id=1&id=2",
      HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"})
    response.status_code.should eq(422)
    error = JSON.parse(response.body)["errors"][0]
    error["source"].as_s.should eq("form")
    error["code"].as_s.should eq("multiple_values")
  end

  it "keeps native body types and distinguishes missing from null" do
    headers = HTTP::Headers{"Content-Type" => "application/json"}
    response = validation_request("POST", "/contracts/json", %({"name":"Ada","active":false}), headers)
    response.status_code.should eq(200)
    value = JSON.parse(response.body)
    value["active"].as_bool.should be_false
    value["age"].raw.should be_nil
    value["bio_present"].as_bool.should be_false

    response = validation_request("POST", "/contracts/json", %({"name":"Ada","active":false,"bio":null}), headers)
    response.status_code.should eq(200)
    JSON.parse(response.body)["bio_present"].as_bool.should be_true
  end

  it "does not coerce body strings into integers or booleans" do
    response = validation_request("POST", "/contracts/json", %({"name":"Ada","active":"false","age":"20"}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"].as_a.size.should eq(2)
  end

  it "rejects null for optional non-nullable fields" do
    response = validation_request("POST", "/contracts/json", %({"name":"Ada","active":true,"age":null}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("null_not_allowed")
  end

  it "preserves custom rule codes and parameters" do
    response = validation_request("POST", "/contracts/json", %({"name":"","active":true}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(422)
    error = JSON.parse(response.body)["errors"][0]
    error["code"].as_s.should eq("too_short")
    error["params"]["min"].as_i.should eq(1)
  end

  it "returns 400 for malformed bodies and 422 for non-object bodies" do
    headers = HTTP::Headers{"Content-Type" => "application/json"}
    response = validation_request("POST", "/contracts/json", "{", headers)
    response.status_code.should eq(400)
    error = JSON.parse(response.body)["errors"][0]
    error["path"].as_a.should be_empty
    error["code"].as_s.should eq("invalid_json")

    response = validation_request("POST", "/contracts/json", "[]", headers)
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("expected_object")
  end

  it "accepts vendor media types and case-insensitive media types" do
    response = validation_request("POST", "/contracts/json", %({"name":"Ada","active":true}),
      HTTP::Headers{"Content-Type" => "Application/vnd.example+json; charset=utf-8"})
    response.status_code.should eq(200)
  end

  it "rejects unsupported and missing body media types before reading" do
    [HTTP::Headers.new, HTTP::Headers{"Content-Type" => "text/plain"}].each do |headers|
      response = validation_request("POST", "/contracts/json", UnreadableContractBody.new, headers)
      response.status_code.should eq(415)
      JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("unsupported_media_type")
    end
  end

  it "limits bytes read even without a content length" do
    body = IO::Memory.new(%({"id":123456789}))
    response = validation_request("POST", "/contracts/limited", body,
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(413)
    JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("body_too_large")
    body.pos.should eq(9)
  end

  it "accepts a body exactly at the configured byte limit" do
    response = validation_request("POST", "/contracts/limited", %({"id":1}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(200)
  end

  it "keeps sources separate even when fields have the same name" do
    response = validation_request("POST", "/contracts/multiple/1?id=2", %({"name":"Ada","active":true}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(200)
    value = JSON.parse(response.body)
    value["url_id"].as_i.should eq(1)
    value["query_id"].as_i.should eq(2)
    value["name"].as_s.should eq("Ada")
  end

  it "collects errors from all declared sources" do
    response = validation_request("POST", "/contracts/multiple/bad?id=nope", "{}",
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(422)
    sources = JSON.parse(response.body)["errors"].as_a.map { |error| error["source"].as_s }.uniq.sort
    sources.should eq(["json", "query", "url"])
  end

  it "inherits a contract and its typed accessor" do
    response = validation_request("GET", "/contracts/inherited?id=42")
    response.status_code.should eq(200)
    JSON.parse(response.body)["id"].as_i.should eq(42)
  end

  it "can add a new input source to an inherited contract" do
    response = validation_request("POST", "/contracts/inherited-multiple?id=42", %({"name":"Ada","active":true}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(200)
    value = JSON.parse(response.body)
    value["id"].as_i.should eq(42)
    value["name"].as_s.should eq("Ada")
  end

  it "validates once before the existing filters and body" do
    response = validation_request("POST", "/contracts/lifecycle", %({"id":1}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(200)
    CONTRACT_EVENTS.should eq(["early", "validation", "before", "body", "after"])
  end

  it "does not run the existing filters or body on validation failure" do
    response = validation_request("POST", "/contracts/lifecycle", "{}",
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(422)
    CONTRACT_EVENTS.should eq(["early"])
  end

  it "can halt before reading or validating a request body" do
    response = validation_request("POST", "/contracts/lifecycle", UnreadableContractBody.new,
      HTTP::Headers{"Deny" => "yes", "Content-Type" => "application/json"})
    response.status_code.should eq(401)
    response.body.should eq("denied")
    CONTRACT_EVENTS.should eq(["early"])
  end

  it "supports skipping inherited pre-validation filters" do
    response = validation_request("POST", "/contracts/skip", %({"id":1}),
      HTTP::Headers{"Deny" => "yes", "Content-Type" => "application/json"})
    response.status_code.should eq(200)
    CONTRACT_EVENTS.should eq(["validation", "before", "body", "after"])
  end

  it "does not turn programming errors into validation responses" do
    expect_raises(Exception, "contract programming error") do
      validation_request("GET", "/contracts/exception?id=1")
    end
  end

  it "allows applications to customize validation responses" do
    response = validation_request("GET", "/contracts/custom-errors")
    response.status_code.should eq(422)
    JSON.parse(response.body)["codes"][0].as_s.should eq("missing")
  end

  it "can construct contracts with application-provided dependencies" do
    validation_request("GET", "/contracts/factory?id=10").status_code.should eq(200)
    response = validation_request("GET", "/contracts/factory?id=9")
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("too_small")
  end

  it "runs cross-field rules without echoing sensitive values" do
    headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    response = validation_request("POST", "/contracts/confirmation", "password=secret&confirmation=other", headers)
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("does_not_match")
    response.body.should_not contain("secret")
    response.body.should_not contain("other")
    validation_request("POST", "/contracts/confirmation", "password=secret&confirmation=secret", headers).status_code.should eq(200)
  end

  it "uses strict boolean conversion while preserving false and decimal values" do
    response = validation_request("GET", "/contracts/boolean?active=false&amount=1.5")
    response.status_code.should eq(200)
    value = JSON.parse(response.body)
    value["active"].as_bool.should be_false
    value["amount"].as_f.should eq(1.5)
    validation_request("GET", "/contracts/boolean?active=1").status_code.should eq(422)
  end

  it "does not parse structured bodies as form fields" do
    response = validation_request("POST", "/contracts/form", "{}",
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(415)
  end
end

class StructuredDetailsContract < RequestValidation::Contract
  schema do
    required :enabled, Bool
  end
end

class StructuredBodyContract < RequestValidation::Contract
  schema do
    required :tags, Array(String)
    required :details, StructuredDetailsContract
  end
end

class StructuredBodyAction < BaseAction
  post "/contracts/structured"
  json StructuredBodyContract

  call do
    render_json({tags: input.tags, enabled: input.details.enabled})
  end
end

describe "structured request contracts" do
  it "passes typed arrays and nested objects through the request boundary" do
    response = validation_request("POST", "/contracts/structured", %({"tags":["one","two"],"details":{"enabled":false}}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(200)
    body = JSON.parse(response.body)
    body["tags"].as_a.map(&.as_s).should eq(["one", "two"])
    body["enabled"].as_bool.should be_false
  end

  it "preserves nested error paths and array indexes in framework responses" do
    response = validation_request("POST", "/contracts/structured", %({"tags":[7],"details":{"enabled":"false"}}),
      HTTP::Headers{"Content-Type" => "application/json"})
    response.status_code.should eq(422)
    errors = JSON.parse(response.body)["errors"].as_a
    errors.map { |error| error["source"].as_s }.uniq.should eq(["json"])
    errors.map { |error| error["path"].to_json }.should eq([%(["tags",0]), %(["details","enabled"])])
  end
end
