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
          @channel = Channel(Frame).new(1024 * 1024)
          opts = parse_options

          queues = Hash(String, Deque(Frame)).new {|h,k| h[k] = Deque(Frame).new}

          @handle = spawn(name: "transfer to insert queue") do
            while frame = @channel.receive?
              queues[tablename_from_verb(frame.verb)] << frame
            end
          end

          @handle = spawn(name: "process insert queue") do
            loop do
            sleep 1
            queues.each do |table, queue|
              columns = nil
              while queue.size > 0
                batch = [] of Array(Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil)
                batch_count = 0
                while queue.size > 0 && batch_count < 10
                  fft = Minion::StreamServer::Destination::SQL.fields_from_table(table: table, frame: queue.shift)
                  if columns.nil?
                    columns = fft[:columns]
                  end
                  batch << fft[:data]
                  batch_count += 1
                end
        
                ConnectionManager.open(@destination).using_connection do |cnn|
                  batch_insert_into(table: table, columns: columns, data: batch, connection: cnn) if batch.size > 0
                end
              end
            end
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

        def batch_insert_into(table, columns, data, connection)
          sql = Minion::StreamServer::Destination::SQL.insert_batch_args(table, columns, data)
          flat_data = [] of Array(String)|Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil
          data.each { |d| d.each {|i| flat_data << i} }
          connection.exec(sql, args: flat_data)
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
