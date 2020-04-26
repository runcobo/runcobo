require "../../models/user"

class Actions::Params::Json < BaseAction
  post "/params/json"
  json NamedTuple(
    user: NamedTuple(
      code: Int32,
      name: String,
      avatar: String,
      ary: Array(Int32)?,
    ),
  )

  property users : Array(User) = [] of User
  call do
    users << User.new(
      code: params[:user][:code],
      name: params[:user][:name]
    )
    render_jbuilder "users/index", layout: "runcobo"
  end
end
