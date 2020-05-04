class String
  def self.from_http_param(value : String)
    value
  end

  def self.from_http_param(value : Nil)
    nil
  end
end
