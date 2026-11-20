require "./contracts"

abstract class FixtureBase < BaseAction
  query CompileContract
end

class FixtureAction < FixtureBase
  url CompileContract
  call do
    render_plain input.id.to_s
  end
end

context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/?id=1"), HTTP::Server::Response.new(IO::Memory.new))
FixtureAction.new(context).call
