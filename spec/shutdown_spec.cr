require "./spec_helper"
require "log/spec"

class SlowShutdownHandler
  include HTTP::Handler
  getter started = Channel(Nil).new(1)
  getter release = Channel(Nil).new(1)

  def call(context)
    started.send(nil)
    release.receive?
    context.response.print("finished")
  end
end

private def shutdown_server(timeout : Time::Span, &)
  handler = SlowShutdownHandler.new
  server = Runcobo::Server.new([handler] of HTTP::Handler)
  server.host = "127.0.0.1"
  server.port = 0
  server.shutdown_timeout = timeout
  done = Channel(Nil).new(1)
  spawn do
    server.listen
    done.send(nil)
  end
  until server.instance.listening?
    Fiber.yield
  end
  address = server.instance.addresses.first
  response = Channel(HTTP::Client::Response).new(1)
  spawn { response.send(HTTP::Client.get("http://#{address}/slow")) }
  handler.started.receive
  yield server, handler, done, response
ensure
  handler.try { |value| value.release.close unless value.release.closed? }
  server.try(&.close)
end

describe "graceful shutdown" do
  it "keeps listen blocked until in-flight requests finish and allows repeated close" do
    shutdown_server(1.second) do |server, handler, done, response|
      server.close
      server.close
      select
      when done.receive
        fail "Server returned while its request still used dependencies"
      when timeout(20.milliseconds)
      end
      handler.release.close
      response.receive.body.should eq("finished")
      done.receive
    end
  end

  it "bounds shutdown waiting and reports requests exceeding the grace period" do
    Log.capture("runcobo", level: :warn) do |logs|
      shutdown_server(30.milliseconds) do |server, handler, done, response|
        server.close
        done.receive
        logs.next(:warn, "shutdown_timed_out active_requests=1")
        logs.empty
        handler.release.close
        response.receive.status_code.should eq(200)
      end
    end
  end

  it "rejects a non-positive grace period before binding" do
    server = Runcobo::Server.new([Runcobo::RouteNotFoundHandler.new] of HTTP::Handler)
    server.shutdown_timeout = Time::Span.zero
    expect_raises(ArgumentError, "shutdown_timeout must be positive") { server.listen }
    server.instance.addresses.should be_empty
  end

  it "does not admit newly dispatched requests after stopping" do
    tracker = Runcobo::RequestTracker.new
    tracker.stop
    context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/"), HTTP::Server::Response.new(IO::Memory.new))
    tracker.call(context)
    context.response.status_code.should eq(503)
    context.response.headers["Connection"].should eq("close")
  end
end
