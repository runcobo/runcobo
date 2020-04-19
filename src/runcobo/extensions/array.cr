module Runcobo
  module Extensions
    module Array(T)
      def from_http_param(values)
        values.map { |x| T.from_http_param(x) }
      end
    end
  end
end
