require "../../models/user"

class UserContract < RequestValidation::Contract
  schema do
    required :code, Int32
    required :name, String
  end
end

class Actions::Params::Json < BaseAction
  post "/params/json"
  json UserContract

  property users : Array(User) = [] of User

  call do
    users << User.new(code: input.code, name: input.name)
    render_jbuilder "users/index", layout: "runcobo"
  end
end
