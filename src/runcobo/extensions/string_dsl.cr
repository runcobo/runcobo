module Runcobo
  module Extensions
    module StringDSL
      def from_http_param(value : String)
        value
      end

      def from_http_param(value : Nil)
        nil
      end
    end
  end
end
