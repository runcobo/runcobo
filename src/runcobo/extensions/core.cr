require "./*"
require "http/request"

module HTTP
  class Request
    include Runcobo::Extensions::HTTP::Request
  end
end

struct Bool
  extend Runcobo::Extensions::Bool
end

class String
  extend Runcobo::Extensions::StringDSL
end

struct Int32
  extend Runcobo::Extensions::Int32
end

struct Int64
  extend Runcobo::Extensions::Int64
end

struct Float32
  extend Runcobo::Extensions::Float32
end

struct Float64
  extend Runcobo::Extensions::Float64
end

class Array(T)
  extend Runcobo::Extensions::Array(T)
end
