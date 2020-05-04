struct Bool
  def self.from_http_param(value : String)
    case value
    when "true", "on", "1"   then true
    when "false", "off", "0" then false
    else                          raise TypeCastError.new
    end
  end

  def self.from_http_param(value : Nil)
    nil
  end
end
