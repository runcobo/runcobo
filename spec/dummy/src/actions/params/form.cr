class Actions::Params::Form < BaseAction
  post "/params/form"
  form NamedTuple(id: Bool?)

  call do
    puts params[:id].class
    render_plain "Hello World!"
  end
end
