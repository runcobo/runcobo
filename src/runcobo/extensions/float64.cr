module Runcobo
  module Extensions
    module Float64
      def from_http_param(value : String)
        value.to_f
      end

      def from_http_param(value : Nil)
        nil
      end
    end
  end
end
