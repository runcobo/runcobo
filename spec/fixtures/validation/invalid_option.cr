require "./contracts"

class FixtureAction < BaseAction
  query CompileContract, unknown_keys: :ignore
end

class FixtureAction
  call do
    render_plain "ok"
  end
end

context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/?id=1"), HTTP::Server::Response.new(IO::Memory.new))
FixtureAction.new(context).call
