module Runcobo
  # Defines json params.
  #
  # ```
  # class JsonParamsExample < BaseAction
  #   get "/params"
  #   json NamedTuple(
  #     id: Int64,
  #     category: String,
  #     user: NamedTuple(
  #       email: String,
  #       gender: Int32,
  #     ),
  #   )
  #
  #   call do
  #     sum = json[:user][:gender] + 6
  #     render_plain "#{sum}: #{category}"
  #   end
  # end
  # ```
  module Params::Json
    macro json(code)
      def json
        {{code}}.not_nil!.from_json(@raw_body.not_nil!)
      end
    end
  end
end
