module Minion
  class StreamServer
    abstract class Destination
      macro inherited
        DestinationRegistry.register("{{@type.name.id}}", self)
      end

      getter failure_notification_channel : Channel(Bool) = Channel(Bool).new
      getter valid : Bool = true

      # def self.open(logfile, options : Array(String) | Nil)
      # end

      def notify_upstream_of_destination_failure
        @failure_notification_channel.send true
      end

      def notify_upstream_of_destination_success
        @failure_notification_channel.send false
      end
    end
  end
end
