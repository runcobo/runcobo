require "./spec_helper"

class ExplicitEmptyResponseSpec < BaseAction
  get "/explicit_empty"
  head "/explicit_empty"

  call do
    context.response.headers["ETag"] = %("example")
    if request.method == "HEAD"
      context.response.content_length = 7
      render_empty content_type: "text/plain"
    elsif request.headers["If-None-Match"]? == %("example")
      render_empty status_code: 304
    else
      render_plain "example"
    end
  end
end

describe "explicit empty responses" do
  it "lets an action select HEAD and conditional responses on a reusable connection" do
    server = HTTP::Server.new([Runcobo::RouteHandler.new, Runcobo::RouteNotFoundHandler.new])
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      HTTP::Client.new(address.address, address.port) do |client|
        response = client.head("/explicit_empty")
        response.status_code.should eq(200)
        response.headers["Content-Length"].should eq("7")
        response.content_type.should eq("text/plain")
        response.body.should be_empty
        client.get("/explicit_empty").body.should eq("example")
        response = client.get("/explicit_empty", headers: HTTP::Headers{"If-None-Match" => %("example")})
        response.status_code.should eq(304)
        response.headers["ETag"].should eq(%("example"))
        response.body.should be_empty
        client.get("/explicit_empty").body.should eq("example")
      end
    ensure
      server.close
    end
  end

  it "keeps normal renderers independent of method and status" do
    ["HEAD", "GET"].each do |method|
      output = IO::Memory.new
      context = HTTP::Server::Context.new(HTTP::Request.new(method, "/"), HTTP::Server::Response.new(output))
      body = IO::Memory.new
      context.response.output = body
      ExplicitEmptyResponseSpec.new(context).render_body("chosen by action", status_code: 304)
      body.to_s.should eq("chosen by action")
    end
  end
end

describe Runcobo::RouteNotFoundHandler do
  it "preserves the default missing response" do
    output = IO::Memory.new
    context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/missing"), HTTP::Server::Response.new(output))
    body = IO::Memory.new
    context.response.output = body
    Runcobo::RouteNotFoundHandler.new.call(context).should be(context)
    context.response.status_code.should eq(404)
    body.to_s.should eq("404")
  end

  it "delegates a missing response to an application callback without replacing it" do
    %w(GET HEAD).each do |method|
      output = IO::Memory.new
      context = HTTP::Server::Context.new(HTTP::Request.new(method, "/missing"), HTTP::Server::Response.new(output))
      body = IO::Memory.new
      context.response.output = body
      handler = Runcobo::RouteNotFoundHandler.new do |ctx|
        ctx.response.status_code = 404
        ctx.response.headers["X-Missing"] = "custom"
        ctx.response.print("application missing") unless ctx.request.method == "HEAD"
      end
      handler.call(context).should be(context)
      context.response.headers["X-Missing"].should eq("custom")
      context.response.status_code.should eq(404)
      body.to_s.should eq(method == "HEAD" ? "" : "application missing")
    end
  end
end
