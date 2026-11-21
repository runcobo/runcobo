require "log"

module Runcobo
  Log = ::Log.for("runcobo")

  # Configure the shared logging pipeline. Global Log.setup and Log.capture also
  # control framework logs, including exception chains and request context.
  def self.logger(output : IO, *, level : ::Log::Severity = :info) : ::Log
    ::Log.setup(level, ::Log::IOBackend.new(output))
    Log
  end
end
