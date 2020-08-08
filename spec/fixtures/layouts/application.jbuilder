Jbuilder.new do |json|
  json.data do |json|
    yield_content
  end
end
