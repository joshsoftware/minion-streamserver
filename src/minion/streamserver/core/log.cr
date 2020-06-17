module Minion
  class StreamServer
    class Core
      # This struct stores the configuration information for a given logging destination.
      struct Log
        getter service : String
        getter raw_destination : String | Nil
        getter destination : Minion::StreamServer::Destination | Nil
        getter cull : Bool | Nil
        getter type : String | Nil
        getter options : Array(String)

        DEFAULT_SERVICE = "default"
        DEFAULT_TYPE    = "file"
        DEFAULT_OPTIONS = ["ab"]

        def initialize(
          @service = DEFAULT_SERVICE,
          @raw_destination = Minion::StreamServer::Core.default_log,
          @destination = Minion::StreamServer::Core.default_log_destination,
          @cull = true,
          @type = DEFAULT_TYPE,
          @options = DEFAULT_OPTIONS
        )
          @raw_destination = @raw_destination.to_s
          @cull = !!cull
        end

        def to_s
          "service: #{@service}\nraw_destination: #{@raw_destination}\ndestination: #{@destination}\ncull: #{@cull}\ntype: #{@type}\noptions: #{@options.inspect}"
        end

        def ==(other)
          other.service == @service &&
            other.raw_destination == @raw_destination &&
            other.cull == @cull &&
            other.type == @type &&
            other.options == @options
        end
      end
    end
  end
end
