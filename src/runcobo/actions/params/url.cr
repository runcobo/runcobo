module Runcobo
  # Declares a request contract for the path.
  module Params::Url
    macro url(type, *, unknown_keys = :reject)
      contract_params :url, {{type}}, unknown_keys: {{unknown_keys}}
    end
  end
end
