require "./spec_helper"

class InjectedActionSpec < BaseAction
  get "/injected_action"
  property injected_value : String?

  call do
    render_plain injected_value || "missing"
  end
end

class InjectingRouteHandlerSpec < Runcobo::RouteHandler
  def initialize(@value : String)
  end

  protected def build_action(action_class : Runcobo::Action.class, context : HTTP::Server::Context) : Runcobo::Action
    action = super
    action.injected_value = @value if action.is_a?(InjectedActionSpec)
    action
  end
end

private def request_injected_server(server : Runcobo::Server)
  address = server.instance.bind_unused_port
  spawn { server.instance.listen }
  HTTP::Client.get("http://127.0.0.1:#{address.port}/injected_action")
ensure
  server.close
end

describe "application dependency injection" do
  it "uses a custom route handler provided at construction" do
    handlers = [InjectingRouteHandlerSpec.new("constructor")] of HTTP::Handler
    response = request_injected_server(Runcobo::Server.new(handlers: handlers))
    response.status_code.should eq(200)
    response.body.should eq("constructor")
  end

  it "applies handler changes made before binding" do
    server = Runcobo::Server.new
    server.handlers = [InjectingRouteHandlerSpec.new("setter")] of HTTP::Handler
    request_injected_server(server).body.should eq("setter")
  end

  it "keeps dependencies specific to each handler" do
    first = Runcobo::Server.new(handlers: [InjectingRouteHandlerSpec.new("first")] of HTTP::Handler)
    second = Runcobo::Server.new(handlers: [InjectingRouteHandlerSpec.new("second")] of HTTP::Handler)
    request_injected_server(first).body.should eq("first")
    request_injected_server(second).body.should eq("second")
  end

  it "rejects replacing handlers after binding sockets" do
    server = Runcobo::Server.new
    server.instance.bind_unused_port
    expect_raises(ArgumentError, "Cannot change handlers after binding the server") do
      server.handlers = [] of HTTP::Handler
    end
  ensure
    server.try(&.close)
  end
end
