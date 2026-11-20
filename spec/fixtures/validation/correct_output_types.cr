require "./contracts"

def consume_id(id : Int64)
end

class FixtureAction < BaseAction
  query CompileContract
  call do
    consume_id(input.id)
    nickname : String? = input.nickname
    render_json({id: input.id, nickname: nickname})
  end
end

context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/?id=1"), HTTP::Server::Response.new(IO::Memory.new))
FixtureAction.new(context).call
