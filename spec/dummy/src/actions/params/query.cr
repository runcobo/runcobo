class Actions::Params::Query < BaseAction
  get "/params/query/:id"
  query NamedTuple(
    id: Bool,
    page: Int32,
    limit: Int32,
    foo: Array(Int32),
    "q[name_eq]": String?,
  )

  call do
    puts query[:id]
    puts query[:page] + 1
    puts query[:foo]
    puts query["foo"]
    puts query["q[name_eq]"]
    render_plain "Hello World!"
  end
end
