Jbuilder.new do |json|
  json.layout_name "alternative"
  json.data do |json|
    yield_content
  end
end
