class FormContract < RequestValidation::Contract
  schema do
    optional :id, Bool
  end
end

class Actions::Params::Form < BaseAction
  post "/params/form"
  form FormContract

  call do
    render_json({id: input.id, present: input.id_present?})
  end
end
