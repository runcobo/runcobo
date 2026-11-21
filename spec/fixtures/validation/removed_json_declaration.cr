require "./contracts"

class FixtureAction < BaseAction
  json NamedTuple(id: Int64)
  call do
    render_plain "unreachable"
  end
end
