module Runcobo
  # Declares a request contract for the structured body.
  module Params::Json
    macro json(type, *, unknown_keys = :reject)
      contract_params :json, {{type}}, unknown_keys: {{unknown_keys}}
    end
  end
end
