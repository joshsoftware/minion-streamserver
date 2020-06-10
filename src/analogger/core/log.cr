module Analogger
  class Core
    class Log
      getter service : String
      getter levels : Hash(String, Bool)
      getter raw_destination : String | Nil
      getter destination : Analogger::Destination | IO | Nil
      getter cull : Bool | Nil
      getter type : String | Nil
      getter options : Array(String)

      DEFAULT_SERVICE = "default"
      DEFAULT_TYPE    = "file"
      DEFAULT_OPTIONS = ["ab"]

      def initialize(
        service = DEFAULT_SERVICE,
        levels = DEFAULT_SEVERITY_LEVELS,
        raw_destination = Analogger::Core.default_log,
        destination = Analogger::Core.default_log_destination,
        cull = true,
        type = DEFAULT_TYPE,
        options = DEFAULT_OPTIONS
      )
        @service = service || DEFAULT_SERVICE
        @levels = levels
        @raw_destination = raw_destination.to_s
        @destination = destination
        @cull = !!cull
        @type = type || DEFAULT_TYPE
        @options = options || DEFAULT_OPTIONS
      end

      def to_s
        "service: #{@service}\nlevels: #{@levels.inspect}\nraw_destination: #{@raw_destination}\ndestination: #{@destination}\ncull: #{@cull}\ntype: #{@type}\noptions: #{@options.inspect}"
      end

      def ==(other)
        other.service == @service &&
          other.levels == @levels &&
          other.raw_destination == @raw_destination &&
          other.cull == @cull &&
          other.type == @type &&
          other.options == @options
      end
    end
  end
end
