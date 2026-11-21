require "request_validation"
require "./request_input"

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

    class Failure < Exception
      getter issues : Array(Issue)
      getter status_code : Int32

      def initialize(@issues : Array(Issue), @status_code : Int32 = 422)
        super("Request validation failed")
      end
    end

    class RequestError < Failure
      getter issue : Issue

      def initialize(source : String, code : Symbol, status_code : Int32)
        @issue = Issue.new(source, RequestValidation::Error.new([] of RequestValidation::PathSegment, code))
        super([@issue], status_code)
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
            begin
              contract.from_json(request.runcobo_input.json(max_request_body_size))
            rescue error : Runcobo::Validation::RequestError
              if error.issue.code == :invalid_json
                RequestValidation::Result({{type}}::Output).failure([
                  RequestValidation::Error.new(error.issue.path, error.issue.code, error.issue.params),
                ])
              else
                raise Runcobo::Validation::RequestError.new("json", error.issue.code, error.status_code)
              end
            end
          {% elsif source == :form %}
            begin
              contract.from_params(request.runcobo_input.form(max_request_body_size))
            rescue error : Runcobo::Validation::RequestError
              raise Runcobo::Validation::RequestError.new("form", error.issue.code, error.status_code)
            end
          {% elsif source == :query %}
            contract.from_params(request.runcobo_input.query)
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
          end
        end
      {% end %}
    end

    # Opt in with before_request read_input to check bodies even without a contract.
    protected def read_input
      request.runcobo_input.merged(max_request_body_size)
      continue
    end

    protected def upload(name : String) : UploadFile
      request.runcobo_input.upload(name, max_request_body_size)
    end

    protected def uploads(name : String) : Array(UploadFile)
      request.runcobo_input.uploads(name, max_request_body_size)
    end

    # A request-level contract, preserving the library's native Output.
    protected def validate(type : T.class, *, strict = false) forall T
      contract = T.new(unknown_keys: strict ? RequestValidation::UnknownKeys::Reject : RequestValidation::UnknownKeys::Strip)
      input = request.runcobo_input.merged(max_request_body_size)
      result = if input.is_a?(HTTP::Params)
                 contract.from_params(input)
               else
                 contract.from_json(input)
               end
      unless result.errors.empty?
        issues = result.errors.map { |error| Issue.new("request", error) }
        raise Failure.new(issues)
      end
      result.value!
    end

    # Override per action when a larger or smaller request body is required.
    def max_request_body_size : Int64
      request.runcobo_input.max_body_size
    end

    protected def render_validation_errors(issues : Array(Validation::Issue), *, status_code : Int32) : HTTP::Server::Context
      render_json({errors: issues}, status_code: status_code)
    end
  end
end
