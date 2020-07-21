require "pg"

module Minion
  class StreamServer
    class Command
      class Processor
        class Postgresql < Minion::StreamServer::Command::Processor
          property destination : String?
          property source : String
          property agent_registry : Hash(String, Protocol)
          property table : String
          getter response_queue : Channel(Frame)

          def initialize(@destination, @agent_registry, @table = "commands", @source = "command_queues")
            @destination = destination.to_s
            @processing_queue = Channel(Tuple(String, String, String)).new(1000)
            initiate_command_processing
            @response_queue = Channel(Frame).new(1000)
            initiate_command_response
          end

          def string_from_string_or_array(val)
            val.is_a?(Array) ? val.as(Array).join : val.as(String)
          end

          def initiate_command_processing
            @processing_queue.parallel.run do |dispatch_params|
              next unless @agent_registry.has_key?(dispatch_params[0])

              server_id, command_id, server_command_id = dispatch_params
              ConnectionManager.open(@destination.not_nil!).using_connection do |cnn|
                argv, type = cnn.query_one(
                  "select argv, type from #{table} where id = $1",
                  command_id,
                  as: {Array(String), String}
                )

                msg = Frame.new(
                  verb: :command,
                  uuid: server_command_id,
                  data: [type] + argv
                )
                @agent_registry[server_id].send_data(msg)
                cnn.exec(
                  "update servers_commands set dispatched_at = now() where id = $1",
                  server_command_id,
                )
              end
            end
          end

          # TODO: Refactor this so that if a response is received for a command that has already
          # gotten a response, that new response is just appended to the original. This becomes
          # potentially complicated when one factors in the hashing of responses in order to
          # deduplcate them.
          #
          # I think that if responses are streaming back, they will have to diverge into separate
          # response records for each server because it's not readily possible to know whether a
          # chunk is a _different_ response from one server, or just a new chunk that needs to be
          # appended.
          def initiate_command_response
            @response_queue.parallel.run do |frame|
              ConnectionManager.open(@destination.not_nil!).using_connection do |cnn|
                command_uuid = frame.data[2]

                sql = <<-ESQL
                INSERT INTO command_responses
                  (stdout, stderr, hash, created_at, updated_at)
                VALUES
                  (
                    $1,
                    $2,
                    encode(
                      digest(CAST(($3 || $4) as TEXT), 'sha256'),
                      'hex'
                    ),
                    now(),
                    now()
                  )
                ON CONFLICT(hash)
                  DO UPDATE SET updated_at = now()
                RETURNING id
                ESQL
                stdout = [string_from_string_or_array(frame.data[3])]
                stderr = [string_from_string_or_array(frame.data[4])]
                response_id = cnn.query_one(
                  sql,
                  stdout,
                  stderr,
                  stdout,
                  stderr,
                  as: {String}
                )

                sql = <<-ESQL
                update servers_commands set response_at = now(), response_id = $1 where id = $2
                ESQL

                cnn.exec(sql, response_id, command_uuid)
              end
            end
          end

          def call
            command_id = nil

            sql = <<-ESQL
            DELETE FROM #{@source}
            WHERE command_id = (
              SELECT command_id
              FROM #{@source}
              ORDER BY created_at
              FOR UPDATE SKIP LOCKED
              LIMIT 1
            )
            RETURNING command_id;
            ESQL

            begin
              ConnectionManager.open(@destination.not_nil!).using_connection do |cnn|
                cnn.transaction do |tx|
                  inner_cnn = tx.connection
                  command_id = nil
                  inner_cnn.query_each(sql) do |rs|
                    command_id = rs.read(String)
                    break
                  end
                end
              end
            rescue DB::NoResultsError
              # Do nothing
            rescue e : Exception
              STDERR.puts "ERROR in Postgresql Driver with #{sql}"
              STDERR.puts e
              STDERR.puts e.backtrace.join("\n")
            end

            dispatch_command(command_id) if command_id
          end

          def dispatch_command(command_id)
            sql = <<-ESQL
            SELECT server_id, command_id, id FROM servers_commands
            WHERE command_id = $1
            ESQL
            ConnectionManager.open(@destination.not_nil!).using_connection do |cnn|
              cnn.query_each(sql, command_id) do |rs|
                @processing_queue.send({rs.read(String), rs.read(String), rs.read(String)})
              end
            end
          end
        end
      end
    end
  end
end
