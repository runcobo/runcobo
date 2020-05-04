require "log"

module Runcobo
  Log = Runcobo.logger(STDOUT)

  # Defines logger with output and level
  #
  # ```
  # Runcobo.logger(STDOUT, level: :info)
  # ```
  def self.logger(output : IO, *, level : ::Log::Severity = :info) : ::Log
    backend = ::Log::IOBackend.new(output)
    backend.formatter = ::Log::Formatter.new do |entry, io|
      label = entry.severity.label
      io << "[" << entry.timestamp << "]"
      io << label.rjust(5) << " -- " << entry.message
    end
    builder = ::Log::Builder.new
    builder.bind("", level, backend)
    builder.for("")
  end
end
