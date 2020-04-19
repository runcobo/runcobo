module Runcobo
  # Route
  struct Route
    # `method`: HTTP method
    property method : String
    # `url`: URL, must starts with "/"
    property url : String
    # `action`: String for class inheriated from BaseAction
    property action : String

    def initialize(@method, @url, @action)
    end
  end
end
