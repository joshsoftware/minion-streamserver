require "./listener"

module Minion
  class StreamServer
    class Command
      class ListenerRegistry
        @@name_to_class_map = {} of String => Minion::StreamServer::Command::Listener.class

        def self.register(name, klass)
          @@name_to_class_map[name[/Minion::StreamServer::Command::Listener::(.*)/, 1].downcase] = klass
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
end

require "./listener/*"
