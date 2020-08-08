require "./spec_helper"

class RedirectSpec < BaseAction
  get "/redirect"
  call do
    redirect "http://google.com"
  end
end

describe "Redirector" do
  client = run_server

  it "redirect" do
    response = client.get("/redirect")
    response.status_code.should eq 302
  end
end
