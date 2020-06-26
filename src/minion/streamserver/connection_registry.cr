require "./connection"

module Minion
  class StreamServer
    class ConnectionRegistry
      @@name_to_class_map = {} of String => Minion::StreamServer::Connection.class

      def self.register(name, klass)
        @@name_to_class_map[name[/Minion::StreamServer::Connection::(.*)/, 1].downcase] = klass
      end

      def self.registry
        @name_to_class_map
      end

      def self.get(key)
        @@name_to_class_map[key]
      end
    end
  end
end
