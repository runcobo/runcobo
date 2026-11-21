require "./spec_helper"
require "file_utils"

private def metadata_request(headers = HTTP::Headers{"Host" => "app.test"}, *, peer : String? = "127.0.0.1",
                             local : Socket::IPAddress? = nil, config = Runcobo::ProxyConfig.new)
  request = HTTP::Request.new("GET", "/", headers)
  context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new),
    remote_address: peer.try { |value| Socket::IPAddress.new(value, 1234) }, local_address: local)
  Runcobo::RequestInfoHandler.new(config).call(context)
  request
end

describe Runcobo::ProxyConfig do
  it "trusts no addresses unless configured" do
    config = Runcobo::ProxyConfig.new
    config.trusted_proxy?(Socket::IPAddress.new("127.0.0.1", 0)).should be_false
    config.trusted_proxy?(nil).should be_false
  end

  it "matches exact addresses and address ranges for both address families" do
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1", "10.20.30.0/24", "2001:db8::/48", "::1"])
    %w(127.0.0.1 10.20.30.255 2001:db8:0:ffff::1 ::1).each do |value|
      config.trusted_proxy?(Socket::IPAddress.new(value, 0)).should be_true
    end
    %w(127.0.0.2 10.20.31.0 2001:db8:1::1 2001:db9::1).each do |value|
      config.trusted_proxy?(Socket::IPAddress.new(value, 0)).should be_false
    end
    Runcobo::ProxyConfig.new(trusted_proxies: ["0.0.0.0/0"]).trusted_proxy?(Socket::IPAddress.new("203.0.113.1", 0)).should be_true
    Runcobo::ProxyConfig.new(trusted_proxies: ["::/0"]).trusted_proxy?(Socket::IPAddress.new("2001:db8::1", 0)).should be_true
  end

  it "rejects invalid proxy ranges and header names at configuration time" do
    %w(localhost 10.0.0.1/33 ::1/129 10.0.0.1/-1 10.0.0.1/+1 10.0.0.1/ 10.0.0.1/24/1).each do |value|
      expect_raises(ArgumentError) { Runcobo::ProxyConfig.new(trusted_proxies: [value]) }
    end
    ["", "CF Connecting IP", "CF-Connecting-IP\nOther"].each do |header|
      expect_raises(ArgumentError) { Runcobo::ProxyConfig.new(client_ip_header: header) }
    end
  end

  it "copies proxy configuration instead of keeping the caller's mutable list" do
    proxies = ["127.0.0.1"]
    config = Runcobo::ProxyConfig.new(trusted_proxies: proxies)
    proxies.clear
    config.trusted_proxy?(Socket::IPAddress.new("127.0.0.1", 0)).should be_true
  end
end

describe "effective request metadata" do
  it "exposes a base address without requiring forwarding middleware on standalone requests" do
    request = HTTP::Request.new("GET", "/path?query=1", HTTP::Headers{"Host" => "app.test:8080", "X-Forwarded-Proto" => "https"})
    request.base_url.should eq("http://app.test:8080")
    request.protocol.should eq("http://")
    request.host.should eq("app.test")
    request.port.should eq(8080)
    request.ssl?.should be_false
    request.remote_ip.should be_nil
  end

  it "ignores all forwarding headers from untrusted connections" do
    headers = HTTP::Headers{"Host" => "app.test:8080", "X-Forwarded-Proto" => "https", "X-Forwarded-Host" => "outside.test",
                            "X-Forwarded-Port" => "443", "X-Forwarded-For" => "8.8.8.8", "CF-Connecting-IP" => "1.1.1.1"}
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["10.0.0.0/8"], client_ip_header: "CF-Connecting-IP")
    request = metadata_request(headers, config: config)
    request.base_url.should eq("http://app.test:8080")
    request.remote_ip.should eq("127.0.0.1")
  end

  it "uses the nearest trusted proxy's scheme, authority and external port" do
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1"])
    headers = HTTP::Headers{"Host" => "internal.test:3000", "X-Forwarded-Proto" => "http, https",
                            "X-Forwarded-Host" => "outside.test, public.test:8443", "X-Forwarded-Port" => "80, 9443"}
    request = metadata_request(headers, config: config)
    request.base_url.should eq("https://public.test:9443")
    request.scheme.should eq("https")
    request.protocol.should eq("https://")
    request.host.should eq("public.test")
    request.port.should eq(9443)
    request.ssl?.should be_true
  end

  it "normalizes default ports and brackets literal hosts" do
    metadata_request(HTTP::Headers{"Host" => "app.test:80"}).base_url.should eq("http://app.test")
    metadata_request(HTTP::Headers{"Host" => "[2001:db8::1]:8080"}).base_url.should eq("http://[2001:db8::1]:8080")
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1"])
    headers = HTTP::Headers{"Host" => "app.test:443", "X-Forwarded-Proto" => "https"}
    metadata_request(headers, config: config).base_url.should eq("https://app.test")
  end

  it "falls back to transport addresses when headers are missing or malformed" do
    local = Socket::IPAddress.new("::1", 3000)
    metadata_request(HTTP::Headers.new, peer: nil, local: local).base_url.should eq("http://[::1]:3000")
    metadata_request(HTTP::Headers.new, peer: nil).base_url.should eq("http://localhost")
    metadata_request(HTTP::Headers.new, peer: nil).remote_ip.should be_nil
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1"])
    ["bad.test/path", "user@bad.test", "bad.test:99999", "[invalid]", "bad.test?query=1"].each do |host|
      headers = HTTP::Headers{"Host" => "app.test", "X-Forwarded-Host" => host, "X-Forwarded-Proto" => "file", "X-Forwarded-Port" => "invalid"}
      metadata_request(headers, config: config).base_url.should eq("http://app.test")
      metadata_request(HTTP::Headers{"Host" => host}).base_url.should eq("http://localhost")
    end
  end

  it "walks the address chain from the peer and stops at the first untrusted address" do
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1", "10.0.0.0/8"])
    headers = HTTP::Headers{"Host" => "app.test", "X-Forwarded-For" => "spoofed, 8.8.8.8, 10.0.0.1"}
    metadata_request(headers, config: config).remote_ip.should eq("8.8.8.8")
    headers["X-Forwarded-For"] = "1.1.1.1, 8.8.8.8"
    metadata_request(headers, config: config).remote_ip.should eq("8.8.8.8")
  end

  it "accepts literal addresses and ignores invalid trusted chain suffixes" do
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["::1", "2001:db8::/48"])
    headers = HTTP::Headers{"Host" => "app.test", "X-Forwarded-For" => "2001:4860:4860::8888, 2001:db8::1"}
    metadata_request(headers, peer: "::1", config: config).remote_ip.should eq("2001:4860:4860::8888")
    ["8.8.8.8, invalid", "8.8.8.8,", "unknown", "8.8.8.8/24"].each do |value|
      headers["X-Forwarded-For"] = value
      metadata_request(headers, peer: "::1", config: config).remote_ip.should eq("::1")
    end
  end

  it "reads provider-specific single-address headers only when explicitly configured" do
    headers = HTTP::Headers{"Host" => "app.test", "CF-Connecting-IP" => "1.1.1.1", "X-Real-IP" => "9.9.9.9", "X-Forwarded-For" => "8.8.8.8"}
    defaults = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1"])
    metadata_request(headers, config: defaults).remote_ip.should eq("8.8.8.8")
    cloudflare = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1"], client_ip_header: "CF-Connecting-IP")
    metadata_request(headers, config: cloudflare).remote_ip.should eq("1.1.1.1")
    headers["CF-Connecting-IP"] = "invalid"
    metadata_request(headers, config: cloudflare).remote_ip.should eq("127.0.0.1")
    headers["CF-Connecting-IP"] = "1.1.1.1, 9.9.9.9"
    metadata_request(headers, config: cloudflare).remote_ip.should eq("127.0.0.1")
    headers.delete("CF-Connecting-IP")
    metadata_request(headers, config: cloudflare).remote_ip.should eq("8.8.8.8")
  end

  it "does not mix the separate Forwarded and X-Forwarded header families" do
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1"])
    headers = HTTP::Headers{"Host" => "app.test", "Forwarded" => "for=1.1.1.1;proto=https;host=other.test", "X-Forwarded-For" => "8.8.8.8"}
    request = metadata_request(headers, config: config)
    request.base_url.should eq("http://app.test")
    request.remote_ip.should eq("8.8.8.8")
  end
end

class RequestMetadataFixture
  include HTTP::Handler

  def call(context)
    request = context.request
    context.response.content_type = "application/json"
    {base_url: request.base_url, remote_ip: request.remote_ip}.to_json(context.response)
  end
end

describe "request metadata server integration" do
  it "applies server proxy settings with custom handlers and after handler replacement" do
    config = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1"])
    server = Runcobo::Server.new(handlers: [] of HTTP::Handler, proxy_config: config)
    server.handlers = [RequestMetadataFixture.new] of HTTP::Handler
    address = server.instance.bind_tcp("127.0.0.1", 0)
    spawn { server.instance.listen }
    response = HTTP::Client.get("http://#{address}/", headers: HTTP::Headers{"X-Forwarded-Proto" => "https", "X-Forwarded-For" => "8.8.8.8"})
    body = JSON.parse(response.body)
    body["base_url"].as_s.should eq("https://#{address}")
    body["remote_ip"].as_s.should eq("8.8.8.8")
  ensure
    server.try(&.close)
  end

  it "keeps an explicitly installed handler's configuration scoped to that server" do
    explicit = Runcobo::ProxyConfig.new(trusted_proxies: ["127.0.0.1"], client_ip_header: "CF-Connecting-IP")
    server = Runcobo::Server.new([Runcobo::RequestInfoHandler.new(explicit), RequestMetadataFixture.new] of HTTP::Handler)
    address = server.instance.bind_tcp("127.0.0.1", 0)
    spawn { server.instance.listen }
    response = HTTP::Client.get("http://#{address}/", headers: HTTP::Headers{"CF-Connecting-IP" => "1.1.1.1"})
    JSON.parse(response.body)["remote_ip"].as_s.should eq("1.1.1.1")
  ensure
    server.try(&.close)
  end

  it "detects encrypted transport per connection even when one server has both listeners" do
    directory = File.tempname("runcobo-request-info")
    Dir.mkdir(directory)
    certificate = File.join(directory, "certificate.pem")
    key = File.join(directory, "key.pem")
    status = Process.run("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key,
                                     "-out", certificate, "-days", "1", "-subj", "/CN=localhost"])
    status.success?.should be_true
    tls = OpenSSL::SSL::Context::Server.new
    tls.certificate_chain = certificate
    tls.private_key = key
    server = Runcobo::Server.new([RequestMetadataFixture.new] of HTTP::Handler)
    plain = server.instance.bind_tcp("127.0.0.1", 0)
    encrypted = server.instance.bind_tls("127.0.0.1", 0, tls)
    spawn { server.instance.listen }
    headers = HTTP::Headers{"Host" => "app.test"}
    HTTP::Client.new("127.0.0.1", encrypted.port, tls: OpenSSL::SSL::Context::Client.insecure) do |client|
      response = client.get("/", headers: headers)
      JSON.parse(response.body)["base_url"].as_s.should eq("https://app.test")
    end
    HTTP::Client.new("127.0.0.1", plain.port) do |client|
      response = client.get("/", headers: headers)
      JSON.parse(response.body)["base_url"].as_s.should eq("http://app.test")
    end
  ensure
    server.try(&.close)
    FileUtils.rm_rf(directory) if directory
  end
end
