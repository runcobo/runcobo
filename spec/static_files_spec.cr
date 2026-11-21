require "./spec_helper"
require "file_utils"

class StaticFilesFallback
  include HTTP::Handler

  def call(context)
    context.response.status_code = 404
    context.response.headers["X-Fallback"] = "yes"
    context.response.print("missing")
  end
end

private def with_static_directory(cache_control = nil, &)
  directory = File.tempname("runcobo-static")
  FileUtils.mkdir_p(File.join(directory, "nested"))
  File.write(File.join(directory, "nested/hello.txt"), "hello static")
  handler = HTTP::Server.build_middleware([
    Runcobo::StaticFiles.new("/assets", directory: directory, cache_control: cache_control), StaticFilesFallback.new,
  ] of HTTP::Handler)
  yield directory, handler
ensure
  FileUtils.rm_rf(directory) if directory
end

private def static_files_request(handler, method = "GET", path = "/assets/nested/hello.txt", headers = HTTP::Headers.new)
  output = IO::Memory.new
  context = HTTP::Server::Context.new(HTTP::Request.new(method, path, headers), HTTP::Server::Response.new(output))
  handler.call(context)
  context.response.close
  output.rewind
  response = HTTP::Client::Response.from_io(output, ignore_body: method == "HEAD")
  output.gets_to_end.should be_empty
  response
end

describe Runcobo::StaticFiles do
  it "maps a prefix to nested files and leaves other paths to the next handler" do
    with_static_directory do |directory, handler|
      response = static_files_request(handler)
      response.status_code.should eq(200)
      response.body.should eq("hello static")
      response.content_type.should eq("text/plain")
      response.headers["Content-Length"].should eq("12")
      static_files_request(handler, path: "/assets-other/nested/hello.txt").headers["X-Fallback"].should eq("yes")
    end
  end

  it "disables directory listing and returns missing files through the fallback" do
    with_static_directory do |directory, handler|
      %w(/assets /assets/ /assets/nested/ /assets/missing.txt).each do |path|
        response = static_files_request(handler, path: path)
        response.status_code.should eq(404)
        response.body.should eq("missing")
      end
    end
  end

  it "rejects unsupported methods with the allowed methods" do
    with_static_directory do |directory, handler|
      response = static_files_request(handler, method: "POST")
      response.status_code.should eq(405)
      response.headers["Allow"].should eq("GET, HEAD")
    end
  end

  it "serves metadata for HEAD without writing body bytes, including missing files" do
    with_static_directory do |directory, handler|
      response = static_files_request(handler, method: "HEAD")
      response.status_code.should eq(200)
      response.headers["Content-Length"].should eq("12")
      response.body.should be_empty
      static_files_request(handler, method: "HEAD", path: "/assets/missing.txt").status_code.should eq(404)
      static_files_request(handler, method: "HEAD", path: "/assets/").status_code.should eq(404)
    end
  end

  it "uses standard conditional caching and range reads" do
    with_static_directory do |directory, handler|
      first = static_files_request(handler)
      cached = static_files_request(handler, headers: HTTP::Headers{"If-None-Match" => first.headers["ETag"]})
      cached.status_code.should eq(304)
      cached.body.should be_empty
      partial = static_files_request(handler, headers: HTTP::Headers{"Range" => "bytes=0-4"})
      partial.status_code.should eq(206)
      partial.body.should eq("hello")
      partial.headers["Content-Range"].should eq("bytes 0-4/12")
      head = static_files_request(handler, method: "HEAD", headers: HTTP::Headers{"Range" => "bytes=0-4"})
      head.status_code.should eq(200)
      head.headers["Content-Length"].should eq("12")
    end
  end

  it "applies configured cache policy to files and conditional replies, not failures or fallthrough" do
    with_static_directory(cache_control: "public, max-age=300") do |directory, handler|
      first = static_files_request(handler)
      first.headers["Cache-Control"].should eq("public, max-age=300")
      head = static_files_request(handler, method: "HEAD")
      head.headers["Cache-Control"].should eq("public, max-age=300")
      cached = static_files_request(handler, headers: HTTP::Headers{"If-None-Match" => first.headers["ETag"]})
      cached.status_code.should eq(304)
      cached.headers["Cache-Control"].should eq("public, max-age=300")
      ["/assets/missing", "/elsewhere"].each do |path|
        static_files_request(handler, path: path).headers.has_key?("Cache-Control").should be_false
      end
      static_files_request(handler, method: "POST").headers.has_key?("Cache-Control").should be_false
    end
    with_static_directory do |directory, handler|
      static_files_request(handler).headers.has_key?("Cache-Control").should be_false
    end
  end

  it "rejects traversal, encoded traversal and symlinks outside the directory" do
    with_static_directory do |directory, handler|
      outside = File.tempfile("runcobo-static-outside")
      begin
        outside.print("secret")
        outside.flush
        File.symlink(outside.path, File.join(directory, "outside.txt"))
        ["/assets/../secret", "/assets/%2e%2e/secret", "/assets/nested%2f..%2fsecret", "/assets/%00", "/assets/nested%5csecret", "/assets/outside.txt"].each do |path|
          response = static_files_request(handler, path: path)
          response.status_code.should eq(404)
          response.body.should_not contain("secret")
        end
      ensure
        outside.close
        outside.delete
      end
    end
  end

  it "checks precompressed file symlinks before sending" do
    with_static_directory(cache_control: "public, max-age=300") do |directory, handler|
      outside = File.tempfile("runcobo-compressed-outside")
      begin
        outside.print("secret")
        outside.flush
        File.symlink(outside.path, File.join(directory, "nested/hello.txt.gz"))
        response = static_files_request(handler, headers: HTTP::Headers{"Accept-Encoding" => "gzip"})
        response.status_code.should eq(404)
        response.headers.has_key?("Content-Encoding").should be_false
        response.headers.has_key?("Cache-Control").should be_false
      ensure
        outside.close
        outside.delete
      end
    end
  end

  it "retains the mount prefix when normalizing a file path" do
    with_static_directory do |directory, handler|
      response = static_files_request(handler, path: "/assets/nested/./hello.txt?version=1")
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/assets/nested/hello.txt?version=1")
    end
  end

  it "allows a directory to be created after mounting and validates configuration" do
    with_static_directory do |directory, handler|
      pending = File.join(directory, "pending")
      mounted = HTTP::Server.build_middleware([Runcobo::StaticFiles.new("/new", directory: pending), StaticFilesFallback.new] of HTTP::Handler)
      static_files_request(mounted, path: "/new/file.txt").status_code.should eq(404)
      Dir.mkdir(pending)
      File.write(File.join(pending, "file.txt"), "created")
      static_files_request(mounted, path: "/new/file.txt").body.should eq("created")
      expect_raises(ArgumentError) { Runcobo::StaticFiles.new("assets", directory: directory) }
      expect_raises(ArgumentError) { Runcobo::StaticFiles.new("/assets", directory: "") }
    end
  end

  it "keeps a real connection usable after HEAD and conditional responses" do
    with_static_directory do |directory, handler|
      server = HTTP::Server.new(handler)
      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }
      begin
        HTTP::Client.new(address.address, address.port) do |client|
          client.head("/assets/nested/hello.txt").body.should be_empty
          first = client.get("/assets/nested/hello.txt")
          first.body.should eq("hello static")
          client.get("/assets/nested/hello.txt", headers: HTTP::Headers{"If-None-Match" => first.headers["ETag"]}).status_code.should eq(304)
          client.get("/assets/nested/hello.txt").body.should eq("hello static")
        end
      ensure
        server.close
      end
    end
  end
end
