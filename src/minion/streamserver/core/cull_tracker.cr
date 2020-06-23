module Minion
  class StreamServer
    class Core
      class CullTracker
        @groups : Hash(String, Group) = Hash(String, Group).new { |h, k| h[k] = Group.new }

        def initialize
        end

        def [](val)
          @groups[val]
        end

        def []=(key, val)
          @groups[key] = val
        end

        class Group
          @services : Hash(String, Service) = Hash(String, Service).new { |h, k| h[k] = Service.new }

          def initialize
          end

          def [](val)
            @services[val]
          end

          def []=(key, val)
            @services[key] = val
          end
        end

        class Service
          @servers : Hash(String, Server) = Hash(String, Server).new { |h, k| h[k] = Server.new }

          def initialize
          end

          def [](val)
            @servers[val]
          end

          def []=(key, val)
            @servers[key] = val
          end
        end

        class Server
          property msg
          property count

          def initialize(@msg = "", @count = 0_u64)
          end

          @[AlwaysInline]
          def increment
            @count += 1
          end

          @[AlwaysInline]
          def positive?
            @count > 0
          end

          @[AlwaysInline]
          def reset(message)
            @count = 0
            @msg = message
          end
        end
      end
    end
  end
end
