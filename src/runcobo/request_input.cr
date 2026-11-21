require "http/request"
require "http/params"
require "json"
require "request_validation"

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

    def initialize(@request : HTTP::Request)
    end

    # Rewind the request body for consumers such as multipart parsers. Contracts
    # use the cached string rather than reading the replacement stream again.
    def body(limit : Int64 = @max_body_size) : String
      raise ArgumentError.new("max_request_body_size must be positive") unless limit > 0
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
        body(limit) if @raw_body
        return cached
      end
      params = query.dup
      unless %w(GET HEAD).includes?(@request.method) || media_type.starts_with?("multipart/")
        if json_media_type?
          unless fields = json(limit, empty_object: true).as_h?
            raise Validation::RequestError.new("json", :expected_object, 422)
          end
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
