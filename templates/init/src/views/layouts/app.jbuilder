Jbuilder.new do |json|
  json.code 200
  json.msg  "ok"
  json.data do |json|
    yield_content
  end
end
