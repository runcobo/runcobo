require "file/tempfile"

module Runcobo
  # Request-owned temporary file. Persist with save before the action returns.
  class UploadFile
    getter filename : String
    getter content_type : String
    getter size : Int64
    getter file : File

    def initialize(@filename : String, @content_type : String, @size : Int64, @file : File)
    end

    def save(path : String) : Nil
      if File.expand_path(path) == File.expand_path(@file.path)
        raise ArgumentError.new("Upload destination must differ from its temporary file")
      end
      position = @file.pos
      begin
        @file.rewind
        File.open(path, "wb") { |output| IO.copy(@file, output) }
      ensure
        @file.seek(position) unless @file.closed?
      end
    end

    # Used by the request lifecycle, including failed parsing and early returns.
    def cleanup : Nil
      @file.close unless @file.closed?
      File.delete?(@file.path)
    end
  end
end
