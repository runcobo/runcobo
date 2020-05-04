module HTTP
  class Request
    property route_params : Hash(String, String) = {} of String => String
  end
end
