require "./spec_helper"

Runcobo.views "spec/fixtures/views", engine: :jbuilder, layout_dir: "spec/fixtures/layouts"

abstract class ViewFixture < BaseAction
  layout "wrapped"
end

class ViewNotes::Show < ViewFixture
  get "/views/show"
  call do
    message = "show"
    labels = ["one", "two"]
    render status_code: 201
  end
end

class ViewNotes::SymbolChoice < ViewFixture
  get "/views/symbol"
  call do
    message = "symbol"
    labels = ["one", "two"]
    render :create
  end
end

class ViewNotes::StringChoice < ViewFixture
  get "/views/string"
  call do
    message = "string"
    labels = ["one", "two"]
    render "create"
  end
end

class ViewNotes::RootChoice < ViewFixture
  get "/views/root"
  call do
    message = "root"
    labels = ["one", "two"]
    render "common/payload"
  end
end

class ViewNotes::DirectoryChoice < ViewFixture
  get "/views/directory"
  call do
    message = "directory"
    labels = ["one", "two"]
    render "payload", dir: "spec/fixtures/views/common"
  end
end

class ViewNotes::Alternative < ViewFixture
  get "/views/alternative"
  call do
    message = "alternative"
    labels = ["one", "two"]
    render :create, layout: "alternative"
  end
end

class ViewNotes::Disabled < ViewFixture
  get "/views/disabled"
  call do
    message = "disabled"
    labels = ["one", "two"]
    render :create, layout: nil
  end
end

class ViewNotes::NoDefault < ViewFixture
  layout nil
  get "/views/no_default"
  call do
    message = "no_default"
    labels = ["one", "two"]
    render :create
  end
end

class ViewNotes::LegacyEmpty < ViewFixture
  layout ""
  get "/views/legacy_empty"
  call do
    message = "legacy_empty"
    labels = ["one", "two"]
    render :create
  end
end

class ViewNotes::WaterChoice < ViewFixture
  get "/views/water"
  call do
    message = "water"
    labels = ["one", "two"]
    render :show, engine: :water, layout: nil
  end
end

class ViewNotes::Nested < ViewFixture
  get "/views/nested"
  call do
    message = "nested"
    labels = ["one", "two"]
    render layout: nil
  end
end

class ViewNotes::StringOutput < ViewFixture
  get "/views/string_output"
  call do
    message = "from string"
    context.response.status_code = 202
    context.response.content_type = "text/plain"
    context.response.headers["X-Retained"] = "yes"
    context.response.print("prefix:")
    body = render_to_string
    render_json({body: JSON.parse(body), status: context.response.status_code,
                 type: context.response.content_type, header: context.response.headers["X-Retained"]}, status_code: 202)
  end
end

module ViewHelper
  def self.payload(message : String) : String
    Runcobo.render_to_string "common/payload"
  end
end

describe "native rendering conventions" do
  client = run_server

  it "infers the namespace and action name and inherits its layout" do
    response = client.get("/views/show")
    response.status_code.should eq(201)
    response.content_type.should eq("application/json")
    body = JSON.parse(response.body)
    body["layout_name"].as_s.should eq("wrapped")
    body["data"]["message"].as_s.should eq("show")
    body["data"]["kind"].as_s.should eq("show")
  end

  it "resolves string and symbol names in the action directory" do
    %w(symbol string).each do |name|
      body = JSON.parse(client.get("/views/#{name}").body)
      body["data"]["kind"].as_s.should eq("create")
      body["data"]["message"].as_s.should eq(name)
    end
  end

  it "resolves root-relative paths and explicit directories without adding the action namespace" do
    %w(root directory).each do |name|
      body = JSON.parse(client.get("/views/#{name}").body)
      body["data"]["active"].as_bool.should be_false
      body["data"]["missing"].raw.should be_nil
    end
  end

  it "overrides layouts and disables them per request or per class" do
    JSON.parse(client.get("/views/alternative").body)["layout_name"].as_s.should eq("alternative")
    %w(disabled no_default legacy_empty).each do |name|
      body = JSON.parse(client.get("/views/#{name}").body)
      body.as_h.keys.sort.should eq(%w(kind message))
    end
  end

  it "renders strings without changing response metadata or appending to its body" do
    response = client.get("/views/string_output")
    response.status_code.should eq(202)
    response.body.should start_with("prefix:")
    body = JSON.parse(response.body.sub("prefix:", ""))
    body["status"].as_i.should eq(202)
    body["type"].as_s.should eq("text/plain")
    body["header"].as_s.should eq("yes")
    body["body"]["layout_name"].as_s.should eq("wrapped")
    body["body"]["data"]["kind"].as_s.should eq("string_output")
  end

  it "renders in helper scopes without an action or a response" do
    JSON.parse(ViewHelper.payload("helper"))["message"].as_s.should eq("helper")
    JSON.parse(ViewHelper.payload("again"))["message"].as_s.should eq("again")
  end

  it "registers jbuilder partials through the view configuration" do
    body = JSON.parse(client.get("/views/nested").body)
    body["items"].as_a.map { |item| item["label"].as_s }.should eq(%w(one two))
  end

  it "selects Water explicitly using the same directory conventions" do
    response = client.get("/views/water")
    response.content_type.should eq("text/html")
    response.body.should eq("<span>water</span>")
  end
end
