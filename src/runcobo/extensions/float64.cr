struct Float64
  def self.from_http_param(value : String)
    value.to_f
  end

  def self.from_http_param(value : Nil)
    nil
  end
end
