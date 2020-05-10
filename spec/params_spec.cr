require "./spec_helper"

class FormParamsSpec < BaseAction
  post "/form_params"
  form NamedTuple(a: Int32, b: Int32)
  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end

class JsonParamsSpec < BaseAction
  post "/json_params"
  json NamedTuple(a: Int32, b: Int32)
  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end

class QueryParamsSpec < BaseAction
  get "/query_params"
  query NamedTuple(a: Int32, b: Int32)
  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end

class UrlParamsSpec < BaseAction
  get "/url_params/:a/:b"
  url NamedTuple(a: Int32, b: Int32)
  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end

describe "ParamSpec" do
  client = run_server

  it "form_params" do
    response = client.post("/form_params", form: {a: "1", b: "2"})
    response.body.should eq "3"
  end

  it "json_params" do
    response = client.post("/json_params", body: {a: 1, b: 2}.to_json)
    response.body.should eq "3"
  end

  it "query_params" do
    response = client.get("/query_params?a=1&b=2")
    response.body.should eq "3"
  end

  it "url_params" do
    response = client.get("/url_params/1/2")
    response.body.should eq "3"
  end
end
