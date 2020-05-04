struct Int64
  def self.from_http_param(value : String)
    value.to_i64
  end

  def self.from_http_param(value : Nil)
    nil
  end
end
