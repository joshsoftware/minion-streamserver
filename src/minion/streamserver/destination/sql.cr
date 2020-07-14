require "json"

module Minion
  class StreamServer
    class Destination
      class SQL
        extend Minion::Util

        DateFields = {"created_at", "updated_at"}

        def self.fields_from_table(table, frame, data_only)
            case table
            when "logs"
              {
                  frame.data[1].as(String),
                  frame.uuid.to_s,
                  frame.data[2].as(String),
                  string_from_string_or_array(frame.data[3]),
              }
            when "telemetries"
              {
                  frame.data[1].as(String),
                  frame.uuid.to_s,
                  frame.data[2..-1].to_json,
              }
            else
              {
                  frame.data[1].as(String),
                  frame.uuid.to_s,
                  frame.data[2].to_json,
              }
            end
        end

        def self.fields_from_table(table, frame)
          case table
          when "logs"
            {
              table:   table,
              columns: {"server_id", "uuid", "service", "msg"},
              data:    {
                frame.data[1].as(String),
                frame.uuid.to_s,
                frame.data[2].as(String),
                string_from_string_or_array(frame.data[3]),
               },
            }
          when "telemetries"
            {
              table:   table,
              columns: {"server_id", "uuid", "data"},
              data:    {
                frame.data[1].as(String),
                frame.uuid.to_s,
                frame.data[2..-1].to_json,
          },
            }
          else
            {
              table:   "unassigned_data",
              columns: {"server_id", "uuid", "data"},
              data:    {
                frame.data[1].as(String),
                frame.uuid.to_s,
                frame.data[2].to_json,
          },
            }
          end
        end

        def self.insert_args(fields, type = "pg")
          sql = <<-ESQL
            INSERT INTO #{fields[:table]} (#{columns(fields)}) VALUES (#{bind_variables(fields, type)}, now(), now())
          ESQL
          {sql: sql, data: fields[:data]}
        end

        def self.insert_batch_args(table, column_names, data, type = "pg")
          sql = <<-ESQL
            INSERT INTO #{table} (#{(column_names.not_nil! + DateFields).join(", ")}) VALUES

          ESQL
          m = column_names.not_nil!.size
          n = 1 - m

          sql += (1..(data.size // m)).map { n += m; "(#{(n..(n + m - 1)).map { |z| "$#{z}" }.join(", ")}, now(), now())" }.join(",\n")

          sql
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
