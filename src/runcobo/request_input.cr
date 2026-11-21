require "http/request"
require "http/params"
require "json"
require "request_validation"
require "http/formdata"
require "./upload_file"
require "./request_body_limit"

module Runcobo
  # One cache per request, shared by body limits and both contract entry styles.
  class RequestInput
    property max_body_size : Int64 = 1_048_576_i64
    getter raw_body : String?
    @body_error : Validation::RequestError?
    @json_error : Validation::RequestError?
    @query : HTTP::Params?
    @form : HTTP::Params?
    @json : JSON::Any?
    @merged : HTTP::Params | JSON::Any | Nil
    @field_modes = {} of String => RequestValidation::Mode
    @multipart_form : HTTP::Params?
    @multipart_files = {} of String => Array(UploadFile)
    @multipart_error : Exception?
    @multipart_size : Int64?
    @uploads_cleaned = false

    # Bound the number of temporary files and field entries independently of bytes.
    private MAX_FILES  =  100
    private MAX_FIELDS = 1000

    def initialize(@request : HTTP::Request)
    end

    # Rewind the request body for consumers such as multipart parsers. Contracts
    # use the cached string rather than reading the replacement stream again.
    def body(limit : Int64 = @max_body_size) : String
      raise ArgumentError.new("max_request_body_size must be positive") unless limit > 0
      if error = @multipart_error
        raise error
      end
      raise IO::Error.new("Multipart body was already consumed") if @multipart_size
      if error = @body_error
        raise error
      end
      if cached = @raw_body
        raise Validation::RequestError.new("body", :body_too_large, 413) if cached.bytesize > limit
        return cached
      end
      if (@request.content_length || 0) > limit
        raise @body_error = Validation::RequestError.new("body", :body_too_large, 413)
      end
      buffer = IO::Memory.new
      if stream = @request.body
        IO.copy(stream, buffer, limit + 1)
        if buffer.size > limit
          raise @body_error = Validation::RequestError.new("body", :body_too_large, 413)
        end
      end
      @raw_body = buffer.to_s
      @request.body = IO::Memory.new(@raw_body.not_nil!)
      @raw_body.not_nil!
    end

    def query : HTTP::Params
      @query ||= HTTP::Params.parse(@request.query || "")
    end

    def form(limit : Int64 = @max_body_size) : HTTP::Params
      return multipart_form(limit) if multipart?
      require_media_type("form", media_type == "application/x-www-form-urlencoded")
      raw = body(limit)
      @form ||= HTTP::Params.parse(raw)
    end

    def json(limit : Int64 = @max_body_size, *, empty_object = false) : JSON::Any
      require_media_type("json", json_media_type?)
      raw = body(limit)
      if error = @json_error
        raise error
      end
      return JSON::Any.new({} of String => JSON::Any) if empty_object && raw.empty?
      @json ||= JSON.parse(raw)
    rescue JSON::ParseException
      raise @json_error = Validation::RequestError.new("json", :invalid_json, 400)
    end

    # Request-level contracts combine query, body and route fields explicitly.
    # Structured body fields replace query fields; route fields always win.
    # Ordinary form values append, preserving duplicate-scalar validation.
    def merged(limit : Int64 = @max_body_size) : HTTP::Params | JSON::Any
      if cached = @merged
        if multipart?
          multipart_form(limit)
        elsif @raw_body
          body(limit)
        end
        return cached
      end
      params = query.dup
      unless %w(GET HEAD).includes?(@request.method)
        if multipart?
          multipart_form(limit).each { |key, value| params.add(key, value) }
        elsif json_media_type?
          unless fields = json(limit, empty_object: true).as_h?
            raise Validation::RequestError.new("json", :expected_object, 422)
          end
          params.each { |key, _| @field_modes[key] = RequestValidation::Mode::Params }
          fields.each_key { |key| @field_modes[key] = RequestValidation::Mode::Json }
          @request.route_params.each_key { |key| @field_modes[key] = RequestValidation::Mode::Params }
          fields = RequestValidation::InputAdapter.params(params).merge(fields)
          @request.route_params.each { |key, value| fields[key] = JSON::Any.new(value) }
          return @merged = JSON::Any.new(fields)
        elsif media_type == "application/x-www-form-urlencoded"
          form(limit).each { |key, value| params.add(key, value) }
        elsif !body(limit).empty?
          raise Validation::RequestError.new("body", :unsupported_media_type, 415)
        end
      end
      @request.route_params.each { |key, value| params[key] = value }
      @merged = params
    end

    def contract_input(limit : Int64 = @max_body_size)
      values = merged(limit)
      values.is_a?(JSON::Any) ? RequestValidation::SourcedInput.new(values.as_h, @field_modes) : values
    end

    def multipart? : Bool
      media_type == "multipart/form-data"
    end

    def upload(name : String, limit : Int64 = @max_body_size) : UploadFile
      files = uploads(name, limit)
      file_error(name, :missing) if files.empty?
      file_error(name, :multiple_values) if files.size > 1
      files.first
    end

    def uploads(name : String, limit : Int64 = @max_body_size) : Array(UploadFile)
      unless multipart?
        merged(limit)
        return [] of UploadFile
      end
      fields = multipart_form(limit)
      file_error(name, :invalid_type) if fields.has_key?(name)
      @multipart_files[name]?.try(&.dup) || [] of UploadFile
    end

    def cleanup_uploads : Nil
      @uploads_cleaned = true
      @multipart_files.each_value { |files| files.each(&.cleanup) }
    end

    private def file_error(name : String, code : Symbol) : NoReturn
      error = RequestValidation::Error.new([name] of RequestValidation::PathSegment, code,
        {"expected" => "UploadFile"} of String => RequestValidation::ErrorParam)
      raise Validation::Failure.new([Validation::Issue.new("file", error)])
    end

    private def multipart_form(limit : Int64) : HTTP::Params
      raise ArgumentError.new("max_request_body_size must be positive") unless limit > 0
      if error = @multipart_error
        raise error
      end
      raise IO::Error.new("Upload files are no longer available") if @uploads_cleaned
      if size = @multipart_size
        raise Validation::RequestError.new("body", :body_too_large, 413) if size > limit
        return @multipart_form.not_nil!
      end
      if (@request.content_length || 0) > limit
        raise Validation::RequestError.new("body", :body_too_large, 413)
      end
      begin
        fields = HTTP::Params.new
        boundary = @request.headers["Content-Type"]?.try { |type| MIME::Multipart.parse_boundary(type) }
        raise HTTP::FormData::Error.new("Missing multipart boundary") unless boundary
        stream = RequestBodyLimit.new(@request.body || IO::Memory.new, limit)
        file_count = field_count = 0
        HTTP::FormData.parse(stream, boundary) do |part|
          if filename = part.filename
            file_count += 1
            raise Validation::RequestError.new("form", :too_many_files, 413) if file_count > MAX_FILES
            tempfile = File.tempfile("runcobo-upload")
            # Register ownership before copying so every failure cleans this file.
            received = UploadFile.new(filename, part.headers["Content-Type"]? || "application/octet-stream", 0_i64, tempfile)
            files = (@multipart_files[part.name] ||= [] of UploadFile)
            files << received
            size = IO.copy(part.body, tempfile)
            tempfile.flush
            tempfile.rewind
            files[-1] = UploadFile.new(filename, received.content_type, size, tempfile)
          else
            field_count += 1
            raise Validation::RequestError.new("form", :too_many_fields, 413) if field_count > MAX_FIELDS
            fields.add(part.name, part.body.gets_to_end)
          end
        end
        stream.skip_to_end
        @multipart_size = stream.bytes_read
        @multipart_form = fields
      rescue error : HTTP::FormData::Error | MIME::Multipart::Error | ArgumentError | IndexError
        cleanup_uploads
        raise @multipart_error = Validation::RequestError.new("form", :invalid_multipart, 400)
      rescue error
        cleanup_uploads
        raise @multipart_error = error
      end
    end

    private def media_type : String
      @request.headers["Content-Type"]?.try(&.split(';', 2).first.strip.downcase) || ""
    end

    private def json_media_type? : Bool
      type = media_type
      type == "application/json" || (type.starts_with?("application/") && type.ends_with?("+json"))
    end

    private def require_media_type(source : String, supported : Bool)
      raise Validation::RequestError.new(source, :unsupported_media_type, 415) unless supported
    end
  end
end

class HTTP::Request
  @runcobo_input : Runcobo::RequestInput?

  def runcobo_input : Runcobo::RequestInput
    @runcobo_input ||= Runcobo::RequestInput.new(self)
  end
end
