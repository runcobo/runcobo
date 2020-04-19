module Runcobo
  module Extensions
    module Bool
      def from_http_param(value : String)
        case value
        when "true", "on", "1"   then true
        when "false", "off", "0" then false
        else                          raise TypeCastError.new
        end
      end

      def from_http_param(value : Nil)
        nil
      end
    end
  end
end
