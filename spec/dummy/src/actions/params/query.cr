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
    puts params[:id]
    puts params[:page] + 1
    puts params[:foo]
    puts params["foo"]
    puts params["q[name_eq]"]
    render_plain "Hello World!"
  end
end
