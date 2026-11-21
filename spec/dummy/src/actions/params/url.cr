class PathContract < RequestValidation::Contract
  schema do
    required :id, Int32
    required :category, String
  end
end

class Actions::Params::Url < BaseAction
  get "/params/url/:id/:category"
  url PathContract

  call do
    render_json({id: input.id, category: input.category})
  end
end
