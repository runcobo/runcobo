module Runcobo
  module Extensions
    module Int64
      def from_http_param(value : String)
        value.to_i64
      end

      def from_http_param(value : Nil)
        nil
      end
    end
  end
end
