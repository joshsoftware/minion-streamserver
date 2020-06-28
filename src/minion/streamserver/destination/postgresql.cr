require "pg"
require "concurrent/channel"

module Minion
  class StreamServer
    class Destination
      # Accept a standard Postgresql libpg style connection URI to specify the database
      # https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING
      class Postgresql < Minion::StreamServer::Destination
        getter handle : Fiber
        getter channel
        getter destination

        def initialize(@destination : String, @options : Array(String))
          @channel = Channel(Frame).new(1024)
          opts = parse_options

          @handle = spawn do
            begin
              @channel.parallel.run do |frame|
                ConnectionManager.open(destination).using_connection do |cnn|
                  table = tablename_from_verb(frame.verb)
                  insert_into(table: table, frame: frame, connection: cnn)
                end
              end
            rescue e : Exception
              STDERR.puts "ERROR in Postgresql Driver:"
              STDERR.puts e
              STDERR.puts e.backtrace.join("\n")
            end
          end
        end

        def insert_into(table, frame, connection)
          parts = Minion::StreamServer::Destination::SQL.insert_args(
            fields: Minion::StreamServer::Destination::SQL.fields_from_table(table: table, frame: frame),
            type: "pg"
          )
          connection.exec(parts[:sql], args: parts[:data])
        end

        def reopen
        end

        def flush
        end

        def parse_options
          opts = {} of String => String
          @options.each do |opt|
            if opt =~ /^\s*(\w+)\s*:\s*(.*)\s*$/
              opts[$1] = $2
            end
          end
          opts
        end

        def tablename_from_verb(verb)
          case verb
          when "L"
            "logs"
          when "T"
            "telemetries"
          end
        end
      end
    end
  end
end
