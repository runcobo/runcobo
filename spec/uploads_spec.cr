require "./spec_helper"

OBSERVED_UPLOADS = [] of Runcobo::UploadFile

class UploadedFieldsContract < RequestValidation::Contract
  schema do
    required :count, Int64
    optional :tags, Array(String)
  end
end

class UploadActionSpec < BaseAction
  post "/uploads_spec/one"
  before_request read_input

  call do
    file = upload("file")
    OBSERVED_UPLOADS << file
    render_json({filename: file.filename, type: file.content_type, size: file.size,
                 body: file.file.gets_to_end, raw_cached: !raw_body.nil?, same: file.same?(upload("file"))})
  end
end

class UploadFieldsActionSpec < BaseAction
  post "/uploads_spec/fields"
  form UploadedFieldsContract

  call do
    file = upload("file")
    OBSERVED_UPLOADS << file
    combined = validate(UploadedFieldsContract, strict: true)
    render_json({count: input.count, combined_count: combined.count, tags: input.tags})
  end
end

class UploadManyActionSpec < BaseAction
  post "/uploads_spec/many"

  call do
    files = uploads("files")
    OBSERVED_UPLOADS.concat(files)
    render_json(files.map { |file| {name: file.filename, size: file.size, body: file.file.gets_to_end} })
  end
end

class UploadFailureActionSpec < BaseAction
  post "/uploads_spec/failure"
  call do
    file = upload("file")
    OBSERVED_UPLOADS << file
    raise "business failure after upload"
  end
end

class UploadValidationFailureSpec < BaseAction
  post "/uploads_spec/validation_failure"
  call do
    file = upload("file")
    OBSERVED_UPLOADS << file
    validate(UploadedFieldsContract)
    render_plain "unreachable"
  end
end

class UploadAuthenticationSpec < BaseAction
  post "/uploads_spec/denied"
  before_request deny_upload
  before_request read_input

  def deny_upload
    render_plain "denied", status_code: 401
    byebye
  end

  call do
    upload("file")
    render_plain "unreachable"
  end
end

class UploadForbiddenBody < IO
  def read(slice : Bytes) : Int32
    raise "Upload must not be read before authentication"
  end

  def write(slice : Bytes) : Nil
    raise "Not writable"
  end
end

private def multipart_upload_request(path = "/uploads_spec/one", fields = HTTP::Params.new,
                                     files = [{"file", "sample.txt", "hello", "text/plain"}])
  output = IO::Memory.new
  form = HTTP::FormData::Builder.new(output)
  fields.each { |name, value| form.field(name, value) }
  files.each do |name, filename, body, type|
    headers = HTTP::Headers.new
    headers["Content-Type"] = type unless type.empty?
    form.file(name, IO::Memory.new(body), HTTP::FormData::FileMetadata.new(filename: filename), headers)
  end
  form.finish
  HTTP::Request.new("POST", path, HTTP::Headers{"Content-Type" => form.content_type}, IO::Memory.new(output.to_s))
end

private def dispatch_upload_request(request)
  output = IO::Memory.new
  context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(output))
  Runcobo::RouteHandler.new.call(context)
  context.response.close
  output.rewind
  HTTP::Client::Response.from_io(output)
end

private def temporary_upload_paths
  Dir.glob(File.join(Dir.tempdir, "runcobo-upload-*")).sort
end

describe "uploaded files in actions" do
  before_each { OBSERVED_UPLOADS.clear }

  it "returns metadata and a replayable file without caching the raw multipart body" do
    request = multipart_upload_request(files: [{"file", "../../sample.txt", "é🙂", "text/plain"}])
    response = dispatch_upload_request(request)
    response.status_code.should eq(200)
    body = JSON.parse(response.body)
    body["filename"].as_s.should eq("../../sample.txt")
    body["type"].as_s.should eq("text/plain")
    body["size"].as_i.should eq(6)
    body["body"].as_s.should eq("é🙂")
    body["raw_cached"].as_bool.should be_false
    body["same"].as_bool.should be_true
    received = OBSERVED_UPLOADS.first
    received.file.closed?.should be_true
    File.exists?(received.file.path).should be_false
  end

  it "validates ordinary fields through both contract styles with native conversions" do
    fields = HTTP::Params.parse("count=12&tags=one&tags=two")
    request = multipart_upload_request("/uploads_spec/fields", fields)
    response = dispatch_upload_request(request)
    response.status_code.should eq(200)
    body = JSON.parse(response.body)
    body["count"].as_i.should eq(12)
    body["combined_count"].as_i.should eq(12)
    body["tags"].as_a.map(&.as_s).should eq(%w(one two))
    File.exists?(OBSERVED_UPLOADS.first.file.path).should be_false
  end

  it "preserves all files in a repeated multi-file field" do
    request = multipart_upload_request("/uploads_spec/many", files: [
      {"files", "one.txt", "one", "text/plain"}, {"files", "two.txt", "two", "text/plain"},
    ])
    response = dispatch_upload_request(request)
    response.status_code.should eq(200)
    body = JSON.parse(response.body).as_a
    body.map { |file| file["body"].as_s }.should eq(%w(one two))
    OBSERVED_UPLOADS.each { |file| File.exists?(file.file.path).should be_false }
  end

  it "reports missing, duplicate and non-file single fields through validation errors" do
    requests = [
      multipart_upload_request(fields: HTTP::Params.parse("caption=text"), files: [] of Tuple(String, String, String, String)),
      multipart_upload_request(files: [{"file", "one", "one", ""}, {"file", "two", "two", ""}]),
      multipart_upload_request(fields: HTTP::Params.parse("file=text")),
    ]
    requests.zip(%w(missing multiple_values invalid_type)).each do |request, code|
      response = dispatch_upload_request(request)
      response.status_code.should eq(422)
      issue = JSON.parse(response.body)["errors"][0]
      issue["source"].as_s.should eq("file")
      issue["path"][0].as_s.should eq("file")
      issue["code"].as_s.should eq(code)
    end
  end

  it "cleans temporary files when business code or a contract fails" do
    expect_raises(Exception, "business failure after upload") do
      dispatch_upload_request(multipart_upload_request("/uploads_spec/failure"))
    end
    response = dispatch_upload_request(multipart_upload_request("/uploads_spec/validation_failure"))
    response.status_code.should eq(422)
    OBSERVED_UPLOADS.size.should eq(2)
    OBSERVED_UPLOADS.each do |file|
      file.file.closed?.should be_true
      File.exists?(file.file.path).should be_false
    end
  end

  it "authenticates before parsing multipart data" do
    request = HTTP::Request.new("POST", "/uploads_spec/denied",
      HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=blocked"}, UploadForbiddenBody.new)
    dispatch_upload_request(request).status_code.should eq(401)
  end

  it "parses a real upload and leaves the connection usable for the next request" do
    request = multipart_upload_request
    raw = request.body.not_nil!.gets_to_end
    server = HTTP::Server.new([Runcobo::RouteHandler.new, Runcobo::RouteNotFoundHandler.new] of HTTP::Handler)
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      HTTP::Client.new(address.address, address.port) do |client|
        response = client.post(request.path, headers: HTTP::Headers{"Content-Type" => request.headers["Content-Type"]}, body: raw)
        response.status_code.should eq(200)
        JSON.parse(response.body)["body"].as_s.should eq("hello")
        File.exists?(OBSERVED_UPLOADS.first.file.path).should be_false
        client.get("/healthcheck").status_code.should eq(200)
      end
    ensure
      server.close
    end
  end
end

describe Runcobo::UploadFile do
  it "saves complete content without changing the caller's read position" do
    request = multipart_upload_request
    destination = File.tempname("runcobo-saved-upload")
    begin
      file = request.runcobo_input.upload("file")
      file.file.read_string(2).should eq("he")
      file.save(destination)
      file.file.pos.should eq(2)
      File.read(destination).should eq("hello")
      request.runcobo_input.cleanup_uploads
      File.exists?(file.file.path).should be_false
      File.read(destination).should eq("hello")
      request.runcobo_input.cleanup_uploads
    ensure
      request.runcobo_input.cleanup_uploads
      File.delete?(destination)
    end
  end

  it "cleans the temporary file if saving fails" do
    request = multipart_upload_request
    file = request.runcobo_input.upload("file")
    begin
      expect_raises(File::Error) { file.save(File.join(file.file.path, "missing", "destination")) }
      file.file.pos.should eq(0)
    ensure
      request.runcobo_input.cleanup_uploads
    end
    File.exists?(file.file.path).should be_false
  end
end

describe "multipart request limits and failures" do
  it "also reuses multipart input when a caller explicitly buffered the body first" do
    request = multipart_upload_request(fields: HTTP::Params.parse("count=12"))
    reader = request.runcobo_input
    begin
      reader.body
      file = reader.upload("file")
      2.times { reader.merged.as(HTTP::Params)["count"].should eq("12") }
      file.file.gets_to_end.should eq("hello")
    ensure
      reader.cleanup_uploads
    end
  end

  it "uses temporary files for a large upload and computes the actual size" do
    payload = "x" * (2 * 1024 * 1024)
    request = multipart_upload_request(files: [{"file", "large.bin", payload, ""}])
    reader = request.runcobo_input
    reader.max_body_size = 3_i64 * 1024 * 1024
    begin
      file = reader.upload("file")
      file.size.should eq(payload.bytesize)
      File.size(file.file.path).should eq(payload.bytesize)
      file.content_type.should eq("application/octet-stream")
      reader.raw_body.should be_nil
      reader.form.should eq(HTTP::Params.new)
    ensure
      reader.cleanup_uploads
    end
  end

  it "enforces the byte limit even with a false or absent content length" do
    [nil, "1"].each do |length|
      request = multipart_upload_request
      request.headers["Content-Length"] = length if length
      reader = request.runcobo_input
      reader.max_body_size = 32_i64
      stream = request.body.as(IO::Memory)
      failure = expect_raises(Runcobo::Validation::RequestError) { reader.upload("file") }
      failure.status_code.should eq(413)
      stream.pos.should eq(33)
      again = expect_raises(Runcobo::Validation::RequestError) { reader.upload("file") }
      failure.same?(again).should be_true
      stream.pos.should eq(33)
    end
  end

  it "checks a stricter limit against cached multipart input" do
    request = multipart_upload_request
    reader = request.runcobo_input
    begin
      file = reader.upload("file")
      reader.merged
      expect_raises(Runcobo::Validation::RequestError) { reader.merged(1_i64) }.status_code.should eq(413)
      reader.upload("file").same?(file).should be_true
    ensure
      reader.cleanup_uploads
    end
  end

  it "counts epilogue bytes as part of the same request limit" do
    request = multipart_upload_request
    raw = request.body.not_nil!.gets_to_end
    request.body = IO::Memory.new(raw + "x" * 64)
    request.runcobo_input.max_body_size = raw.bytesize.to_i64 + 4
    before = temporary_upload_paths
    expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.upload("file") }.status_code.should eq(413)
    temporary_upload_paths.should eq(before)
  end

  it "rejects malformed boundaries and cleans partially received files" do
    request = multipart_upload_request
    raw = request.body.not_nil!.gets_to_end
    request.body = IO::Memory.new(raw[0, raw.size - 8])
    before = temporary_upload_paths
    error = expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.upload("file") }
    error.status_code.should eq(400)
    error.issue.code.should eq(:invalid_multipart)
    temporary_upload_paths.should eq(before)
    again = expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.upload("file") }
    error.same?(again).should be_true
    error.same?(expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.body }).should be_true
    missing = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data"}, "bad")
    expect_raises(Runcobo::Validation::RequestError) { missing.runcobo_input.upload("file") }.status_code.should eq(400)
  end

  it "caps file and field counts and cleans all partially received files" do
    files = (1..101).map { |index| {"files", "#{index}.txt", "", "text/plain"} }
    request = multipart_upload_request(files: files)
    before = temporary_upload_paths
    error = expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.uploads("files") }
    error.issue.code.should eq(:too_many_files)
    temporary_upload_paths.should eq(before)
    fields = HTTP::Params.new
    1001.times { fields.add("tag", "one") }
    request = multipart_upload_request(fields: fields)
    error = expect_raises(Runcobo::Validation::RequestError) { request.runcobo_input.form }
    error.issue.code.should eq(:too_many_fields)
  end
end
