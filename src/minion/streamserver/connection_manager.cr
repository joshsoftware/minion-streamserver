require "./connection"
require "./connection/*"

module Minion
  class StreamServer
    # The Stream Server may maintain connections to multile data stores.
    # The destination modules that use those connections should not have to worry
    # about the details of getting one, nor of any connection pooling management.
    class ConnectionManager
      @@pool = {} of String => Minion::StreamServer::Connection

      def self.open(uri : String)
        type, _ = uri.split(/:/, 2)
        # We already have a connection.
        if @@pool.has_key?(uri)
          @@pool[uri]
        else
          @@pool[uri] = ConnectionRegistry.get(type).new(uri)
        end
      end
    end
  end
end
