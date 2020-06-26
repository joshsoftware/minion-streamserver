require "pg"

module Minion
  class StreamServer
    class Connection
      class Postgresql < Minion::StreamServer::Connection
        property handle : DB::Database

        def initialize(uri)
          @handle = DB.open(uri)
        end

        forward_missing_to @handle
      end
    end
  end
end
