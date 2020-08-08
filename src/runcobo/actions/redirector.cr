module Runcobo
  module Redirector
    def redirect(url : String, *, status_code : Int32 = 302)
      @context.response.headers["Location"] = url
      @context.response.status_code = status_code
      @context
    end
  end
end
