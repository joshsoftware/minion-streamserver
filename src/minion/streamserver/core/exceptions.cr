module Minion
  class StreamServer
    class Core
      class NoPortProvided < RuntimeError
        def initialize
          @message = "The port to bind to was not provided."
        end
      end

      class BadPort < RuntimeError
        def initialize(port : String | Int32 | Nil)
          @message = "The port provided (#{port}) is invalid."
        end
      end
    end
  end
end
