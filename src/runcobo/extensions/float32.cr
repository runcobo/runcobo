struct Float32
  def self.from_http_param(value : String)
    value.to_f32
  end

  def self.from_http_param(value : Nil)
    nil
  end
end
