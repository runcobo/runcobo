json.array! "users", @users do |json, user|
  json.code user.code # Code
  json.name user.name # Name
end
