class Actions::Params::Url < BaseAction
  get "/params/url/:id/:category"
  url NamedTuple(id: Int32, category: String)

  call do
    puts params[:id]
    puts params[:category]
    render_plain "Hello World!"
  end
end
