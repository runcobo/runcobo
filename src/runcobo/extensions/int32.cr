module Runcobo
  module Extensions
    module Int32
      def from_http_param(value : String)
        value.to_i
      end

      def from_http_param(value : Nil)
        nil
      end
    end
  end
end
