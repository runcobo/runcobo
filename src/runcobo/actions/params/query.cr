module Runcobo
  # Declares a request contract for the query string.
  module Params::Query
    macro query(type, *, unknown_keys = :reject)
      contract_params :query, {{type}}, unknown_keys: {{unknown_keys}}
    end
  end
end
