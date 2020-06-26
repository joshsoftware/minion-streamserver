require "json"

module Minion
  class StreamServer
    class Destination
      class SQL
        def self.fields_from_table(table, frame)
          case table
          when "logs"
            {
              table:   table,
              columns: {"server_id", "uuid", "service", "msg"},
              data:    [
                frame.data[1],
                frame.uuid.to_s,
                frame.data[2],
                frame.data[3],
              ] of DB::Any,
            }
          when "telemetries"
            {
              table:   table,
              columns: {"server_id", "uuid", "data"},
              data:    [
                frame.data[1],
                frame.uuid.to_s,
                frame.data[2],
              ] of DB::Any,
            }
          else
            {
              table:   "unassigned_data",
              columns: {"server_id", "uuid", "data"},
              data:    [
                frame.data[1],
                frame.uuid.to_s,
                frame.data[2..-1].to_json,
              ] of DB::Any,
            }
          end
        end

        def self.insert_args(fields, type = "pg")
          sql = <<-ESQL
            INSERT INTO #{fields[:table]} (#{columns(fields)}) VALUES (#{bind_variables(fields, type)})
          ESQL
          {sql: sql, data: fields[:data]}
        end

        def self.columns(fields)
          fields[:columns].join(", ")
        end

        def self.bind_variables(fields, type = "pg")
          case type
          when "pg"
            (1..(fields[:columns].size)).map do |n|
              "$#{n}"
            end.join(", ")
          when "mysql"
            fields[:columns].map { "?" }.join(", ")
          end
        end
      end
    end
  end
end
