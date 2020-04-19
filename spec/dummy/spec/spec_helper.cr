require "spec"
require "../src/runcobo"

def run_server
  server = Runcobo::Server.new
  server.port = 3222
  server.logger = Runcobo::Logger.new(File.new(File::NULL))
  client = server.client

  around_all do |example|
    spawn { server.listen }
    sleep 0.5
    example.run
  ensure
    server.close
  end

  before_each { client.close }

  client
end
