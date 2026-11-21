require "./spec_helper"

describe "server environment configuration" do
  it "decodes reuse_port as a boolean rather than string presence" do
    Runcobo.reuse_port_from_env(nil).should be_false
    Runcobo.reuse_port_from_env("false").should be_false
    Runcobo.reuse_port_from_env("true").should be_true
    expect_raises(ArgumentError, "REUSE_PORT must be true or false") { Runcobo.reuse_port_from_env("no") }
  end
end

describe "server certificate configuration" do
  it "rejects either missing half before binding a socket" do
    [{"certificate.pem", nil}, {nil, "private-key.pem"}].each do |certificate, key|
      server = Runcobo::Server.new([Runcobo::RouteNotFoundHandler.new] of HTTP::Handler)
      server.host = "127.0.0.1"
      server.port = 0
      server.cert = certificate
      server.key = key
      expect_raises(ArgumentError, "Certificate and private key must be configured together") { server.listen }
      server.instance.addresses.should be_empty
    end
  end
end

describe "response state observation" do
  it "reports when response headers have actually been sent" do
    response = HTTP::Server::Response.new(IO::Memory.new)
    response.headers_sent?.should be_false
    response.print("buffered")
    response.headers_sent?.should be_false
    response.flush
    response.headers_sent?.should be_true
    response.close
    response.headers_sent?.should be_true
  end
end
