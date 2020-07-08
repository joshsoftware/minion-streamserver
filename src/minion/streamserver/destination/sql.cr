require "json"

module Minion
  class StreamServer
    class Destination
      class SQL
        DateFields = {"created_at", "updated_at"}

        # TODO: put this method on some class where everything can find it.
        def self.string_from_string_or_array(val) : String
          val.is_a?(Array) ? val.as(Array).join : val.as(String)
        end

        def self.fields_from_table(table, frame)
          case table
          when "logs"
            {
              table:   table,
              columns: {"server_id", "uuid", "service", "msg"},
              data:    [
                 frame.data[1].as(String),
                 frame.uuid.to_s,
                 frame.data[2].as(String),
                 string_from_string_or_array(frame.data[3]),
              ] of DB::Any,
            }
          when "telemetries"
            {
              table:   table,
              columns: {"server_id", "uuid", "data"},
              data:    [
                frame.data[1].as(String),
                frame.uuid.to_s,
                frame.data[2..-1].to_json,
              ] of DB::Any,
            }
          else
            {
              table:   "unassigned_data",
              columns: {"server_id", "uuid", "data"},
              data:    [
                frame.data[1].as(String),
                frame.uuid.to_s,
                frame.data[2].to_json,
              ] of DB::Any,
            }
          end
        end

        def self.insert_args(fields, type = "pg")
          sql = <<-ESQL
            INSERT INTO #{fields[:table]} (#{columns(fields)}) VALUES (#{bind_variables(fields, type)}, now(), now())
          ESQL
          {sql: sql, data: fields[:data]}
        end

        def self.columns(fields)
          (fields[:columns] + DateFields).join(", ")
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
