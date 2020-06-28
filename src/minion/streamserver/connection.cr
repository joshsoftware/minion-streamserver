module Minion
  class StreamServer
    abstract class Connection
      macro inherited
        ConnectionRegistry.register("{{@type.name.id}}", self)
      end

      # def self.open(logfile, options : Array(String) | Nil)
      # end
    end
  end
end
