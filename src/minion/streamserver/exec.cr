require "./command_line"
require "./core"

module Minion
  class StreamServer
    class Exec
      def self.run
        Core.new( CommandLine.new ).start
      end
    end
  end
end
