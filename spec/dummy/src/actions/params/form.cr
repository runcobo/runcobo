class Actions::Params::Form < BaseAction
  post "/params/form"
  form NamedTuple(id: Bool?)

  call do
    puts form[:id].class
    render_plain "Hello World!"
  end
end
