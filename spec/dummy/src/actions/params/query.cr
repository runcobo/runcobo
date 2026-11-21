class QueryContract < RequestValidation::Contract
  schema do
    required :page, Int32
    required :limit, Int32
    optional :name, String
  end
end

class Actions::Params::Query < BaseAction
  get "/params/query"
  query QueryContract

  call do
    render_json({page: input.page, limit: input.limit, name: input.name})
  end
end
