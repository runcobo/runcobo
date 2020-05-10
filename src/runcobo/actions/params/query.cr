module Runcobo
  # Defines query params.
  #
  # ```
  # class QueryParamsExample < BaseAction
  #   get "/params"
  #   query NamedTuple(id: Int64, category: String)
  #
  #   call do
  #     sum = params[:id] + 6
  #     render_plain "#{sum}: #{category}"
  #   end
  # end
  # ```
  module Params::Query
    macro query(code)
      def query_params
        _params = HTTP::Params.parse(request.query || "")
        NamedTuple.new(
          {% for key, value in code.named_args %}
            {% if value.stringify.starts_with?("Array") %}
              {{key.stringify}}: {{value}}.from_http_param(_params.fetch_all({{key.stringify}})),
            {% elsif value.stringify.includes?("Nil") %}
              {{key.stringify}}: {{value.types[0]}}.from_http_param(_params[{{key.stringify}}]?),
            {% else %}
              {{key.stringify}}: {{value}}.from_http_param(_params[{{key.stringify}}]),
            {% end %}
          {% end %}
        )
      end
    end
  end
end
