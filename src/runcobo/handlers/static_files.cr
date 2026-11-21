require "http/server/handlers/static_file_handler"

module Runcobo
  # Mount a public directory before the action router.
  class StaticFiles < HTTP::StaticFileHandler
    def initialize(prefix : String, *, directory : String)
      unless prefix.starts_with?("/") && !prefix.includes?('?') && !prefix.includes?('#')
        raise ArgumentError.new("Static prefix must be an absolute URL path")
      end
      raise ArgumentError.new("Static directory must not be empty") if directory.empty?
      @prefix = prefix.rstrip('/')
      @directory = File.expand_path(directory)
      super(directory, fallthrough: false, directory_listing: false)
    end

    def call(context) : Nil
      return call_next(context) unless mounted?(context.request.path)
      unless %w(GET HEAD).includes?(context.request.method)
        context.response.status_code = 405
        context.response.headers["Allow"] = "GET, HEAD"
        return
      end
      relative = request_path(URI.decode(context.request.path))
      if relative.includes?('\0') || relative.includes?('\\') || relative.split('/').includes?("..")
        return missing(context)
      end
      path = File.join(@directory, relative.lchop('/'))
      return missing(context) unless File.file?(path) && allowed_file?(path)
      super
    end

    protected def request_path(path : String) : String
      path.lchop(@prefix).presence || "/"
    end

    private def mounted?(path : String) : Bool
      @prefix.empty? || path == @prefix || path.starts_with?(@prefix + "/")
    end

    private def allowed_file?(path) : Bool
      root = File.realpath(@directory)
      target = File.realpath(path)
      target == root || target.starts_with?(root.rstrip('/') + "/")
    rescue File::Error
      false
    end

    private def missing(context) : Nil
      %w(Content-Encoding Content-Length ETag Last-Modified).each { |name| context.response.headers.delete(name) }
      if context.request.method == "HEAD"
        context.response.status_code = 404
      else
        call_next(context)
      end
    end

    # The standard handler selects precompressed files before sending. Check the
    # selected path too, so a symlink to an outside .gz file cannot escape the root.
    private def serve_file(context, file_info, file_path, original_file_path, last_modified)
      return missing(context) unless allowed_file?(file_path.to_s)
      if context.request.method == "HEAD"
        context.response.status = :ok
        context.response.content_type = MIME.from_filename(original_file_path.to_s, "application/octet-stream")
        context.response.content_length = file_info.size
        context.response.headers["Accept-Ranges"] = "bytes"
      else
        super
      end
    end

    private def redirect_to(context, path)
      uri = context.request.uri.dup
      uri.path = URI.encode_path(@prefix + path.to_s)
      context.response.redirect(uri)
    end
  end
end
