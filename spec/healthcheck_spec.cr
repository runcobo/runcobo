require "./spec_helper"

describe "Healthcheck" do
  client = run_server

  it "healthcheck" do
    response = client.get("/healthcheck")
    response.content_type.should eq "text/plain"
    response.status_code.should eq 200
    Time.parse_utc(response.body, "%Y-%m-%d %H:%M:%S %z").to_s.should eq Time.utc.to_s
  end
end
