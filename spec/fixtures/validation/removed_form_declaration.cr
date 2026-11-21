require "./contracts"

class FixtureAction < BaseAction
  form NamedTuple(id: Int64)
  call do
    render_plain "unreachable"
  end
end
