module Runcobo
  # Count actual bytes, including multipart headers and epilogues. Read at most
  # one byte past the limit and latch failure so parser cleanup cannot read more.
  class RequestBodyLimit < IO
    getter bytes_read : Int64 = 0
    @failure : Validation::RequestError?

    def initialize(@source : IO, @limit : Int64)
    end

    def read(slice : Bytes) : Int32
      return 0 if slice.empty?
      if error = @failure
        raise error
      end
      size = Math.min(slice.size.to_i64, @limit - @bytes_read)
      size += 1 if size < slice.size
      count = @source.read(slice[0, size.to_i])
      @bytes_read += count
      if @bytes_read > @limit
        raise @failure = Validation::RequestError.new("body", :body_too_large, 413)
      end
      count
    end

    def write(slice : Bytes) : NoReturn
      raise IO::Error.new("Request body is read-only")
    end
  end
end
