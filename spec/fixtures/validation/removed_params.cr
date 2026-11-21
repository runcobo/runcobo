require "./contracts"

class FixtureAction < BaseAction
  query CompileContract
  call do
    render_plain params[:id].to_s
  end
end

context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/?id=1"), HTTP::Server::Response.new(IO::Memory.new))
FixtureAction.new(context).call
