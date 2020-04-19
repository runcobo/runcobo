require "teeplate"

module Runcobo
  # An Init Template for `runcobo init` command.
  class InitTemplate < Teeplate::FileTree
    # :nodoc:
    directory "#{__DIR__}/../../templates/init"
    @file : String

    def initialize(@file)
    end
  end
end
