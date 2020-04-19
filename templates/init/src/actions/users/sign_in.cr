class Users::SignIn < BaseAction
  post "/users/sign_in"
  json NamedTuple(
    email: String?,
    password: String?,
  )
  property user : User
  call do
    user = User.new(email: json[:email], password: json[:password])
    render_jbuilder "users/sign_in"
  end
end
