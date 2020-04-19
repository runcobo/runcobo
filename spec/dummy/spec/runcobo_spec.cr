require "./spec_helper"

describe Runcobo do
  client = run_server

  it "works with query" do
    response = client.get("/params/url/1/hot")
    response.body.should eq("Hello World!")
  end
end
