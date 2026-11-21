Jbuilder.new do |json|
  json.layout_name "wrapped"
  json.data do |json|
    yield_content
  end
end
