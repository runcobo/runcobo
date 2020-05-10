class Users::SignIn < BaseAction
  post "/users/sign_in"
  json NamedTuple(
    email: String?,
    password: String?,
  )
  property user : User
  call do
    user = User.new(email: params[:email], password: params[:password])
    render_jbuilder "users/sign_in"
  end
end
