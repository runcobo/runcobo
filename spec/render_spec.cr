require "./spec_helper"

class RenderPlainSpec < BaseAction
  get "/render_plain"
  call do
    render_plain "RENDER_PLAIN", status_code: 201
  end
end

class RenderJbuilderSpec < BaseAction
  get "/render_jbuilder"
  call do
    render_jbuilder "spec/fixtures/example", status_code: 201, dir: ""
  end
end

class RenderJbuilderWithLayoutSpec < BaseAction
  get "/render_jbuilder_with_layout"
  call do
    render_jbuilder "spec/fixtures/example", layout: "spec/fixtures/layouts/application", dir: "", layout_dir: ""
  end
end

class RenderWaterSpec < BaseAction
  get "/render_water"
  call do
    render_water "spec/fixtures/example", status_code: 201, dir: ""
  end
end

class RenderWaterWithLayoutSpec < BaseAction
  get "/render_water_with_layout"
  call do
    render_water "spec/fixtures/example", layout: "spec/fixtures/layouts/application", dir: "", layout_dir: ""
  end
end

class RenderBodySpec < BaseAction
  get "/render_body"
  call do
    render_body "RENDER_BODY", status_code: 201
  end
end

describe "Render" do
  client = run_server

  it "render_plain" do
    response = client.get("/render_plain")
    response.content_type.should eq "text/plain"
    response.status_code.should eq 201
    response.body.should eq "RENDER_PLAIN"
  end

  it "render_jbuilder" do
    response = client.get("/render_jbuilder")
    response.content_type.should eq "application/json"
    response.status_code.should eq 201
    response.body.should eq "{\"code\":200}"
  end

  it "render_jbuilder_with_layout" do
    response = client.get("/render_jbuilder_with_layout")
    response.content_type.should eq "application/json"
    response.status_code.should eq 200
    response.body.should eq "{\"data\":{\"code\":200}}"
  end

  it "render_water" do
    response = client.get("/render_water")
    response.content_type.should eq "text/html"
    response.status_code.should eq 201
    response.body.should eq "<span>RENDER_WATER</span>"
  end

  it "render_water_with_layout" do
    response = client.get("/render_water_with_layout")
    response.content_type.should eq "text/html"
    response.status_code.should eq 200
    response.body.should eq "<div>\n  <span>RENDER_WATER</span>\n</div>"
  end

  it "render_body" do
    response = client.get("/render_body")
    response.content_type.should eq nil
    response.status_code.should eq 201
    response.body.should eq "RENDER_BODY"
  end
end
