struct Int32
  def self.from_http_param(value : String)
    value.to_i
  end

  def self.from_http_param(value : Nil)
    nil
  end
end
