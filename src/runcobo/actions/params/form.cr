module Runcobo
  # Declares a request contract for the form body.
  module Params::Form
    macro form(type, *, unknown_keys = :reject)
      contract_params :form, {{type}}, unknown_keys: {{unknown_keys}}
    end
  end
end
