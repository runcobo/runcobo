require "./spec_helper"

class NativeInputContract < RequestValidation::Contract
  schema do
    required :id, Int64
    optional :active, Bool
    optional :label, String, nullable: true
    optional :tags, Array(String)
  end
end

INPUT_EVENTS = [] of Symbol

class NativeInputAction < BaseAction
  get "/native_input"
  post "/native_input"
  post "/native_input/:id"
  before record_before
  after record_after

  def record_before
    INPUT_EVENTS << :before
  end

  def record_after
    INPUT_EVENTS << :after
  end

  call do
    input = validate(NativeInputContract)
    INPUT_EVENTS << :body
    render_json({native: input.is_a?(NativeInputContract::Output), id: input.id,
                 active: input.active, label: input.label, label_present: input.label_present?, tags: input.tags})
  end
end

class StrictNativeInputAction < BaseAction
  post "/native_input/strict"
  call do
    input = validate(NativeInputContract, strict: true)
    render_json({id: input.id})
  end
end

abstract class CheckedInputAction < BaseAction
  before_request authenticate_input
  before_request read_input

  def authenticate_input
    INPUT_EVENTS << :authenticate
    if request.headers["Deny"]?
      render_plain "denied", status_code: 401
      byebye
    else
      continue
    end
  end
end

class ParameterlessInputAction < CheckedInputAction
  post "/native_input/parameterless"
  get "/native_input/parameterless"
  call do
    INPUT_EVENTS << :body
    render_plain "ok"
  end
end

class SkippedInputAction < CheckedInputAction
  skip authenticate_input
  skip read_input
  post "/native_input/retired"
  call do
    render_plain "retired", status_code: 410
  end
end

class DeclaredAndNativeInputAction < CheckedInputAction
  post "/native_input/shared"
  json NativeInputContract
  call do
    combined = validate(NativeInputContract)
    render_json({declared_id: input.id, combined_id: combined.id, raw: raw_body})
  end
end

class MultipleInputErrorsAction < BaseAction
  post "/native_input/multiple_errors"
  query NativeInputContract
  json NativeInputContract
  call do
    render_plain "unreachable"
  end
end

class CustomNativeInputErrorsAction < BaseAction
  post "/native_input/custom_errors"

  protected def render_validation_errors(issues : Array(Runcobo::Validation::Issue), *, status_code : Int32) : HTTP::Server::Context
    render_json({codes: issues.map(&.code)}, status_code: status_code)
  end

  call do
    validate(NativeInputContract)
    render_plain "unreachable"
  end
end

class ExplodingNativeInputContract < RequestValidation::Contract
  schema do
    required :id, Int64
  end

  rule :id do |id, errors|
    raise "native contract programming error"
  end
end

class ExplodingNativeInputAction < BaseAction
  post "/native_input/exploding"
  call do
    validate(ExplodingNativeInputContract)
    render_plain "unreachable"
  end
end

class SinglePassInputBody < IO::Memory
  getter eof_reads = 0

  def read(slice : Bytes) : Int32
    raise "Request body was read again" if @eof_reads > 0
    super.tap { |count| @eof_reads += 1 if count == 0 }
  end
end

class ForbiddenInputBody < IO
  def read(slice : Bytes) : Int32
    raise "Request body must not be read"
  end

  def write(slice : Bytes) : Nil
    raise "Not writable"
  end
end

private def native_input_request(method : String, path : String, body : String | IO | Nil = nil,
                                 headers = HTTP::Headers{"Content-Type" => "application/json"})
  request = HTTP::Request.new(method, path, headers, body)
  output = IO::Memory.new
  context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(output))
  Runcobo::RouteHandler.new.call(context)
  context.response.close
  output.rewind
  HTTP::Client::Response.from_io(output)
end

describe "request-level contracts" do
  before_each { INPUT_EVENTS.clear }

  it "returns native output and preserves false, arrays and explicit null" do
    response = native_input_request("POST", "/native_input", %({"id":12,"active":false,"label":null,"tags":["one"]}))
    response.status_code.should eq(200)
    body = JSON.parse(response.body)
    body["native"].as_bool.should be_true
    body["id"].as_i.should eq(12)
    body["active"].as_bool.should be_false
    body["label"].raw.should be_nil
    body["label_present"].as_bool.should be_true
    body["tags"].as_a.map(&.as_s).should eq(["one"])
    INPUT_EVENTS.should eq([:before, :body, :after])
  end

  it "uses native query and form conversions, including repeated arrays" do
    response = native_input_request("GET", "/native_input?id=12&active=false")
    JSON.parse(response.body)["active"].as_bool.should be_false
    response = native_input_request("POST", "/native_input", "id=12&tags=one&tags=two",
      HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"})
    JSON.parse(response.body)["tags"].as_a.map(&.as_s).should eq(%w(one two))
  end

  it "strips unknown fields by default and rejects them explicitly" do
    native_input_request("POST", "/native_input", %({"id":12,"extra":true})).status_code.should eq(200)
    response = native_input_request("POST", "/native_input/strict", %({"id":12,"extra":true}))
    response.status_code.should eq(422)
    error = JSON.parse(response.body)["errors"][0]
    error["source"].as_s.should eq("request")
    error["path"][0].as_s.should eq("extra")
    error["code"].as_s.should eq("unexpected_key")
  end

  it "rejects wrong structured types and duplicate scalar parameters" do
    response = native_input_request("POST", "/native_input", %({"id":"12","active":"false"}))
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"].as_a.map { |error| error["code"].as_s }.should eq(%w(invalid_type invalid_type))
    response = native_input_request("GET", "/native_input?id=1&id=2")
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("multiple_values")
  end

  it "stops business code and after filters on a contract failure" do
    response = native_input_request("POST", "/native_input", "{}")
    response.status_code.should eq(422)
    INPUT_EVENTS.should eq([:before])
  end

  it "checks malformed, non-object and unsupported bodies without empty contracts" do
    {"{" => {400, "invalid_json"}, "[]" => {422, "expected_object"}}.each do |raw, expected|
      response = native_input_request("POST", "/native_input/parameterless", raw)
      response.status_code.should eq(expected[0])
      JSON.parse(response.body)["errors"][0]["code"].as_s.should eq(expected[1])
    end
    response = native_input_request("POST", "/native_input/parameterless", "text", HTTP::Headers{"Content-Type" => "text/plain"})
    response.status_code.should eq(415)
    INPUT_EVENTS.should_not contain(:body)
  end

  it "allows empty bodies and ignores read-only bodies" do
    native_input_request("POST", "/native_input/parameterless").status_code.should eq(200)
    native_input_request("GET", "/native_input/parameterless", ForbiddenInputBody.new).status_code.should eq(200)
    response = native_input_request("POST", "/native_input")
    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"][0]["code"].as_s.should eq("missing")
  end

  it "authenticates before reading and supports skipping inherited input checks" do
    response = native_input_request("POST", "/native_input/parameterless", ForbiddenInputBody.new,
      HTTP::Headers{"Deny" => "yes", "Content-Type" => "application/json"})
    response.status_code.should eq(401)
    INPUT_EVENTS.should eq([:authenticate])
    native_input_request("POST", "/native_input/retired", ForbiddenInputBody.new).status_code.should eq(410)
  end

  it "shares the body across preparation, declared contracts and direct validation" do
    stream = SinglePassInputBody.new(%({"id":12}))
    response = native_input_request("POST", "/native_input/shared", stream)
    response.status_code.should eq(200)
    body = JSON.parse(response.body)
    body["declared_id"].as_i.should eq(12)
    body["combined_id"].as_i.should eq(12)
    body["raw"].as_s.should eq(%({"id":12}))
    stream.eof_reads.should eq(1)
  end

  it "collects source errors alongside malformed structured input" do
    response = native_input_request("POST", "/native_input/multiple_errors?id=bad", "{")
    response.status_code.should eq(400)
    errors = JSON.parse(response.body)["errors"].as_a
    errors.map { |error| error["source"].as_s }.sort.should eq(%w(json query))
  end

  it "uses the same customizable error hook and lets programming errors propagate" do
    response = native_input_request("POST", "/native_input/custom_errors", "{}")
    response.status_code.should eq(422)
    JSON.parse(response.body)["codes"][0].as_s.should eq("missing")
    expect_raises(Exception, "native contract programming error") do
      native_input_request("POST", "/native_input/exploding", %({"id":12}))
    end
  end
end

describe Runcobo::RequestInput do
  it "keeps combined precedence explicit and source caches isolated" do
    request = HTTP::Request.new("POST", "/?id=1", HTTP::Headers{"Content-Type" => "application/json"}, %({"id":2}))
    request.route_params = {"id" => "3"}
    reader = request.runcobo_input
    reader.merged.as(JSON::Any)["id"].as_s.should eq("3")
    reader.query["id"].should eq("1")
    reader.json["id"].as_i.should eq(2)
    reader.json.as_h.same?(reader.json.as_h).should be_true
  end

  it "preserves form duplicates without changing the cached query" do
    request = HTTP::Request.new("POST", "/?id=1", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "id=2")
    reader = request.runcobo_input
    reader.merged.as(HTTP::Params).fetch_all("id").should eq(%w(1 2))
    reader.query.fetch_all("id").should eq(["1"])
    reader.form.fetch_all("id").should eq(["2"])
  end

  it "shares middleware buffering, parser caches and replayable body access" do
    stream = SinglePassInputBody.new(%({"id":12}))
    request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, stream)
    reader = request.runcobo_input
    reader.body.should eq(%({"id":12}))
    reader.merged.as(JSON::Any)["id"].as_i.should eq(12)
    reader.json.as_h.same?(reader.json.as_h).should be_true
    reader.body.should eq(%({"id":12}))
    request.body.not_nil!.gets_to_end.should eq(%({"id":12}))
    stream.eof_reads.should eq(1)
  end

  it "reuses parse failures and keeps media type checks after caching" do
    request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, "{")
    first = expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.json }
    again = expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.json }
    first.same?(again).should be_true
    wrong_type = expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.form }
    wrong_type.status_code.should eq(415)
  end

  it "limits unknown-length bodies and never returns truncated data after failure" do
    stream = IO::Memory.new("0123456789")
    request = HTTP::Request.new("POST", "/", body: stream)
    reader = request.runcobo_input
    first = expect_raises(Runcobo::Validation::RequestError) { reader.body(4_i64) }
    first.status_code.should eq(413)
    stream.pos.should eq(5)
    again = expect_raises(Runcobo::Validation::RequestError) { reader.body(100_i64) }
    first.same?(again).should be_true
    stream.pos.should eq(5)
  end

  it "enforces stricter limits on cached bodies and rejects invalid limits" do
    request = HTTP::Request.new("POST", "/", body: "12345")
    reader = request.runcobo_input
    reader.body(5_i64).should eq("12345")
    expect_raises(Runcobo::Validation::RequestError) { reader.body(4_i64) }.status_code.should eq(413)
    expect_raises(ArgumentError) { reader.body(0_i64) }
  end
end
