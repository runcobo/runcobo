require "./contracts"

def consume_id(id : String)
end

class FixtureAction < BaseAction
  query CompileContract
  call do
    consume_id(input.id)
    render_plain "ok"
  end
end

context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/?id=1"), HTTP::Server::Response.new(IO::Memory.new))
FixtureAction.new(context).call
