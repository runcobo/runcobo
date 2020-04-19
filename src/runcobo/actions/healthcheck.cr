module Runcobo
  # Adds Healthcheck Action to App.
  #
  # There should be at least two nodes(Action) in the `radix` tree.
  #
  # Keeps this action present to keep two nodes.
  class Healthcheck < ::BaseAction
    get "/healthcheck"

    call do
      render_plain Time.utc.to_s
    end
  end
end
