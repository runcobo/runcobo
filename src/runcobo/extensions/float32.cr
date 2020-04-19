module Runcobo
  module Extensions
    module Float32
      def from_http_param(value : String)
        value.to_f32
      end

      def from_http_param(value : Nil)
        nil
      end
    end
  end
end
