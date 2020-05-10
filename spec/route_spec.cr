require "./spec_helper"

class EightKindsRouterSpec < BaseAction
  get "/get/example"
  post "/post/example"
  put "/put/example"
  delete "/delete/example"
  options "/options/example"
  patch "/patch/example"
  route "LINK", "/link/example"
  head "/head/example"

  call do
    render_plain request.path
  end
end

describe "Route" do
  client = run_server

  it "eight_kinds_route" do
    client.get("/get/example").body.should eq "/get/example"
    client.post("/post/example").body.should eq "/post/example"
    client.put("/put/example").body.should eq "/put/example"
    client.delete("/delete/example").body.should eq "/delete/example"
    client.patch("/patch/example").body.should eq "/patch/example"
    client.options("/options/example").body.should eq "/options/example"
    client.patch("/patch/example").body.should eq "/patch/example"
    client.exec("LINK", "/link/example").body.should eq "/link/example"
    client.head("/head/example").body.should eq "" # HEAD request always returns blank response
  end
end
