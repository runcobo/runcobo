require "../../../src/runcobo"
Runcobo.views "spec/fixtures/views", engine: :water

class ViewNotes::Show < BaseAction
  get "/water"
  call do
    message = "default water"
    render
  end
end

output = IO::Memory.new
context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/water"), HTTP::Server::Response.new(output))
ViewNotes::Show.new(context).call
context.response.close
output.rewind
response = HTTP::Client::Response.from_io(output)
puts response.content_type
puts response.body
