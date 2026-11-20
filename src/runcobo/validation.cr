require "request_validation"

module Runcobo
  module Validation
    struct Issue
      include JSON::Serializable

      getter source : String
      getter path : Array(RequestValidation::PathSegment)
      getter code : Symbol
      getter params : Hash(String, RequestValidation::ErrorParam)

      def initialize(@source : String, error : RequestValidation::Error)
        @path = error.path.dup
        @code = error.code
        @params = error.params.dup
      end
    end

    class RequestError < Exception
      getter issue : Issue
      getter status_code : Int32

      def initialize(source : String, code : Symbol, @status_code : Int32)
        super(code.to_s)
        @issue = Issue.new(source, RequestValidation::Error.new([] of RequestValidation::PathSegment, code))
      end
    end

    macro contract_params(source, type, *, unknown_keys = :reject)
      {% if type.is_a?(Generic) && ["NamedTuple", "::NamedTuple"].includes?(type.name.stringify) %}
        {% raise "NamedTuple parameter declarations were removed in Runcobo 3.0; declare a RequestValidation::Contract instead" %}
      {% end %}
      {% unless type.is_a?(Path) && type.resolve < RequestValidation::Contract %}
        {% raise "Expected a RequestValidation::Contract type" %}
      {% end %}
      {% unless [:reject, :strip].includes?(unknown_keys) %}
        {% raise "unknown_keys must be :reject or :strip" %}
      {% end %}

      @[Runcobo::Parameter(source: {{source}})]
      private def {{"__runcobo_#{source.id}_declaration_#{type.line_number}_#{type.column_number}".id}}
      end

      @{{source.id}}_validation_result : RequestValidation::Result({{type}}::Output)?

      protected def build_{{source.id}}_contract
        {{type}}.new(unknown_keys: {{unknown_keys}})
      end

      private def {{source.id}}_validation_result : RequestValidation::Result({{type}}::Output)
        @{{source.id}}_validation_result ||= begin
          contract = build_{{source.id}}_contract
          {% if source == :json %}
            contract.from_json(read_validation_body("json"))
          {% elsif source == :form %}
            contract.from_params(HTTP::Params.parse(read_validation_body("form")))
          {% elsif source == :query %}
            contract.from_params(HTTP::Params.parse(request.query || ""))
          {% else %}
            contract.from_params(request.route_params)
          {% end %}
        end
      end

      def {{source.id}}_input : {{type}}::Output
        {{source.id}}_validation_result.value!
      end

      {% verbatim do %}
        macro finished
          {% declarations = [] of Def %}
          {% for owner in [@type] + @type.ancestors %}
            {% for method in owner.methods %}
              {% if method.annotation(Runcobo::Parameter) %}
                {% declarations << method %}
              {% end %}
            {% end %}
          {% end %}
          {% sources = declarations.map { |method| method.annotation(Runcobo::Parameter)[:source] } %}
          {% if sources.uniq.size != sources.size %}
            {% raise "A request source can only have one contract (including inherited declarations)" %}
          {% end %}
          {% if sources.includes?(:json) && sources.includes?(:form) %}
            {% raise "An action cannot declare both json and form contracts" %}
          {% end %}

          {% if sources.size == 1 %}
            def input
              {{sources.first.id}}_input
            end
          {% else %}
            macro input
              \{% raise "Multiple request contracts: use url_input, query_input, form_input or json_input" %}
            end
          {% end %}

          def validation_response : HTTP::Server::Context?
            issues = [] of Runcobo::Validation::Issue
            {% for source in sources %}
              {{source.id}}_validation_result.errors.each do |error|
                issues << Runcobo::Validation::Issue.new({{source.id.stringify}}, error)
              end
            {% end %}
            return nil if issues.empty?
            status = issues.any? { |issue| issue.code == :invalid_json } ? 400 : 422
            render_validation_errors(issues, status_code: status)
          rescue error : Runcobo::Validation::RequestError
            render_validation_errors([error.issue], status_code: error.status_code)
          end
        end
      {% end %}
    end

    @validation_body_loaded = false

    # Override per action when a larger or smaller request body is required.
    def max_request_body_size : Int64
      1_048_576_i64
    end

    protected def render_validation_errors(issues : Array(Validation::Issue), *, status_code : Int32) : HTTP::Server::Context
      render_json({errors: issues}, status_code: status_code)
    end

    private def read_validation_body(source : String) : String
      return @raw_body || "" if @validation_body_loaded
      media_type = request.headers["Content-Type"]?.try(&.split(';', 2).first.strip.downcase)
      supported = if source == "json"
                    media_type == "application/json" || !!(media_type && media_type.starts_with?("application/") && media_type.ends_with?("+json"))
                  else
                    media_type == "application/x-www-form-urlencoded"
                  end
      raise Validation::RequestError.new(source, :unsupported_media_type, 415) unless supported

      limit = max_request_body_size
      raise ArgumentError.new("max_request_body_size must be positive") unless limit > 0
      buffer = IO::Memory.new
      if body = request.body
        IO.copy(body, buffer, limit + 1)
        raise Validation::RequestError.new(source, :body_too_large, 413) if buffer.size > limit
      end
      @raw_body = buffer.to_s
      @validation_body_loaded = true
      @raw_body.not_nil!
    end
  end
end
