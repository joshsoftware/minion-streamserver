require "pg"
require "concurrent/channel"

module Minion
  class StreamServer
    class Destination
      # Accept a standard Postgresql libpg style connection URI to specify the database
      # https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING
      class Postgresql < Minion::StreamServer::Destination
        getter handles : Array(Fiber)
        getter channel
        getter destination
        getter failure_notification_channel : Channel(Bool)

        @options : Hash(String, Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil)

        def initialize(
          @destination : String,
          options : Array(String) | Array(Hash(String, Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil)),
          @failure_notification_channel : Channel(Bool)
          )
          @options = parse_options(options)
          set_option_defaults

          @channel = Channel(Frame).new(@options["channel_depth"].as(Int32))
          queues = Hash(String, Deque(Frame)).new { |h, k| h[k] = Deque(Frame).new }

          @handles = [] of Fiber
          @handles << spawn(name: "transfer to insert queue") do
            while frame = @channel.receive?
              tablename = tablename_from_verb(frame.verb)

              # Don't push the frame into the queue (or receive more frames from the channel)
              # until the max queue depth is low enough. This prevents unbounded RAM usage in
              # the event of a massive and protracted burst in activity.
              until queues[tablename].size < @options["queue_depth"].as(Int32)
                sleep @options["queue_drain_wait"].as(Float)
              end

              queues[tablename] << frame
            end
          end

          # TODO: Right now if there is a DB error, records will get lost. Instead, if there is a
          # DB error, records should be pushed back into the queue, and it should try again after
          # a short wait.
          @handles << spawn(name: "process insert queue") do
            dont_sleep = true
            loop do
              sleep @options["queue_process_wait"].as(Float) unless dont_sleep
              dont_sleep = false
              ConnectionManager.open(@destination).transaction do |tx|
                insert_count = 0
                cnn = tx.connection
                batch = Array(Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil).new(initial_capacity: @options["batch_size"].as(Int32))
                batch_size = @options["batch_size"].as(Int32)

                queues.each do |table, queue|
                  break if insert_count > @options["inserts_per_transaction"].as(Int32)
                  columns = nil
                  while queue.size > 0
                    batch_count = 0
                    batch.clear
                    while queue.size > 0 && batch_count < batch_size
                      if columns.nil?
                        fft = Minion::StreamServer::Destination::SQL.fields_from_table(table: table, frame: queue.shift)
                        columns = fft[:columns]
                        batch.concat(fft[:data])
                      else
                        fft = Minion::StreamServer::Destination::SQL.fields_from_table(table: table, frame: queue.shift, data_only: true)
                        batch.concat(fft)
                      end
                      batch_count += 1
                    end

                    if batch.size > 0
                      batch_insert_into(table: table, columns: columns, data: batch, connection: cnn)
                      insert_count += 1
                      dont_sleep = true
                      break if insert_count > @options["inserts_per_transaction"].as(Int32)
                    end
                  end
                end
              end
            end
          end
        end

        # Options are passed as an array of one or more hashes. This format is derived
        # from the use of YAML as the main configuration, and the need to be able to
        # specify options as a simple array for some destinations.
        # The option parser iterates the array, and composes a new hash containing the
        # keys and values of all of the hashes passed in the options array.
        def parse_options(options)
          r = {} of String => Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil
          options.each do |o|
            if o.is_a?(Hash)
              o.each do |k, v|
                r[k] = v
              end
            end
          end
          r
        end

        def set_option_defaults
          @options["batch_size"] = 1000 unless @options.has_key?("batch_size")
          @options["queue_depth"] = 100000 unless @options.has_key?("queue_depth")
          @options["channel_depth"] = 10000 unless @options.has_key?("channel_depth")
          @options["queue_drain_wait"] = 0.01 unless @options.has_key?("queue_drain_wait")
          @options["queue_process_wait"] = 0.5 unless @options.has_key?("queue_process_wait")
          @options["inserts_per_transaction"] = 10 unless @options.has_key?("inserts_per_transaction")
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
          begin
            connection.exec(sql, args: data)
          rescue ex
            # TODO: Recover
            STDERR.puts "Error in Batch Insert Into: #{ex}"
          end
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
