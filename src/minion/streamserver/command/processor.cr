module Minion
  class StreamServer
    class Command
      abstract class Processor
        macro inherited
          ProcessorRegistry.register("{{@type.name.id}}", self)
        end

        abstract def response_queue
      end
    end
  end
end
