module Minion
  class StreamServer
    abstract class Destination
      macro inherited
        DestinationRegistry.register("{{@type.name.id}}", self)
      end

      getter valid : Bool = true
      # def self.open(logfile, options : Array(String) | Nil)
      # end
    end
  end
end
