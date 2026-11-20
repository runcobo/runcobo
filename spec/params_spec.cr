require "./spec_helper"

class SumContract < RequestValidation::Contract
  schema do
    required :a, Int32
    required :b, Int32
  end
end

class FormParamsSpec < BaseAction
  post "/form_params"
  form SumContract

  call do
    render_plain (input.a + input.b).to_s
  end
end

class JsonParamsSpec < BaseAction
  post "/json_params"
  json SumContract

  call do
    render_plain (input.a + input.b).to_s
  end
end

class QueryParamsSpec < BaseAction
  get "/query_params"
  query SumContract

  call do
    render_plain (input.a + input.b).to_s
  end
end

class UrlParamsSpec < BaseAction
  get "/url_params/:a/:b"
  url SumContract

  call do
    render_plain (input.a + input.b).to_s
  end
end

describe "parameter sources" do
  client = run_server

  it "converts form parameters" do
    response = client.post("/form_params", form: {a: "1", b: "2"})
    response.status_code.should eq(200)
    response.body.should eq("3")
  end

  it "validates structured body parameters" do
    response = client.post("/json_params", headers: HTTP::Headers{"Content-Type" => "application/json"}, body: {a: 1, b: 2}.to_json)
    response.status_code.should eq(200)
    response.body.should eq("3")
  end

  it "converts query parameters" do
    response = client.get("/query_params?a=1&b=2")
    response.status_code.should eq(200)
    response.body.should eq("3")
  end

  it "converts path parameters" do
    response = client.get("/url_params/1/2")
    response.status_code.should eq(200)
    response.body.should eq("3")
  end
end
