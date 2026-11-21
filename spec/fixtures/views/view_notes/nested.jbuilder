json.array!("items", labels) do |json, label|
  json.partial! "partials/item", label: label
end
