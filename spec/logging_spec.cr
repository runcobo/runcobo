require "./spec_helper"
require "log/spec"

class LoggingFixtureHandler
  include HTTP::Handler
  property fail_request = false

  def call(context)
    raise IO::Error.new("fixture failure") if fail_request
    context.response.print("ok")
  end
end

describe "shared framework logging" do
  it "obeys the global builder and retains exception details" do
    output = IO::Memory.new
    begin
      Log.setup(:none)
      Runcobo::Log.info { "hidden" }
      Runcobo.logger(output, level: :error)
      Runcobo::Log.info { "also hidden" }
      Runcobo::Log.error(exception: IO::Error.new("original cause")) { "failure" }
      Log.error { "application failure" }
      Fiber.yield
      output.to_s.should_not contain("hidden")
      output.to_s.should contain("original cause")
      output.to_s.should contain("application failure")
    ensure
      Log.setup_from_env
    end
  end

  it "correlates native request IDs and logs paths without query values" do
    request = HTTP::Request.new("GET", "/sample?secret=private", HTTP::Headers{"X-Request-Id" => "opaque-trace"})
    context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
    fixture = LoggingFixtureHandler.new
    chain = HTTP::Server.build_middleware([Runcobo::LogHandler.new, fixture] of HTTP::Handler)
    previous = Log.context.metadata
    Log.capture("runcobo") do |logs|
      chain.call(context)
      context.request.request_id.should eq("opaque-trace")
      context.response.headers["X-Request-Id"].should eq("opaque-trace")
      logs.next(:info, /request_completed request_id=opaque-trace method=GET path=\/sample status=200 elapsed_ms=/)
      logs.entry.message.should_not contain("private")
      logs.entry.context[:request_id].to_s.should eq("opaque-trace")
      logs.empty
    end
    Log.context.metadata.should eq(previous)
  end
end

describe "native request failure logs" do
  it "retains the exception and does not log successful completion for an unhandled error" do
    fixture = LoggingFixtureHandler.new
    fixture.fail_request = true
    request = HTTP::Request.new("GET", "/failed?secret=private")
    context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
    chain = HTTP::Server.build_middleware([Runcobo::LogHandler.new, fixture] of HTTP::Handler)
    Log.capture("runcobo") do |logs|
      expect_raises(IO::Error, "fixture failure") { chain.call(context) }
      logs.next(:error, /request_failed .*path=\/failed status=500 elapsed_ms=/)
      logs.entry.exception.should be_a(IO::Error)
      logs.entry.message.should_not contain("private")
      logs.empty
    end
  end
end
