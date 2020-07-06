module Minion
  class StreamServer
    class Command
      abstract class Listener
        macro inherited
          ListenerRegistry.register("{{@type.name.id}}", self)
        end
      end
    end
  end
end
