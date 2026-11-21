require "./contracts"

class FixtureAction < BaseAction
  url NamedTuple(id: Int64)
  call do
    render_plain "unreachable"
  end
end
