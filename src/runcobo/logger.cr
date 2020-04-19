require "colorize"

module Runcobo
  class Logger
    STYLES = {
      success: {
        emoji:      "✔",
        foreground: :light_green,
        size:       1,
      },
      error: {
        emoji:      "✖",
        foreground: :red,
        size:       3,
      },
      fatal: {
        emoji:      "✖",
        foreground: :red,
        size:       3,
      },
      warn: {
        emoji:      "⚠",
        foreground: :yellow,
        size:       4,
      },
      log: {
        emoji:      "ℹ",
        foreground: :white,
        size:       5,
      },
      info: {
        emoji:      "ℹ",
        foreground: :light_blue,
        size:       4,
      },
      start: {
        emoji:      "●",
        foreground: :light_blue,
        size:       3,
      },
      ready: {
        emoji:      "♥",
        foreground: :green,
        size:       3,
      },
      debug: {
        emoji:      "…",
        foreground: :default,
        size:       3,
      },
      trace: {
        emoji:      "…",
        foreground: :default,
        size:       3,
      },
    }

    def initialize(@io : IO)
    end

    def success(message)
      format(:success, message)
    end

    def error(message)
      format(:error, message)
    end

    def fatal(message)
      format(:fatal, message)
    end

    def warn(message)
      format(:warn, message)
    end

    def log(message)
      format(:log, message)
    end

    def info(message)
      format(:info, message)
    end

    def start(message)
      format(:start, message)
    end

    def ready(message)
      format(:ready, message)
    end

    def debug(message)
      format(:debug, message)
    end

    def trace(message)
      format(:trace, message)
    end

    def format(log_type, message)
      style = STYLES[log_type]
      foreground = style[:foreground]
      colored_emoji = style[:emoji].colorize.fore(foreground).mode(:bold)
      colored_log_type = log_type.colorize.fore(foreground).mode(:bold)
      @io.puts "#{colored_emoji} #{colored_log_type}#{" " * style[:size]} #{message}"
    end
  end
end
