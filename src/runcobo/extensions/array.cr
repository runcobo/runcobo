class Array(T)
  def self.from_http_param(values)
    values.map { |x| T.from_http_param(x) }
  end
end
