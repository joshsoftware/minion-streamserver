require "option_parser"
require "pg"
require "colorize"
require "tablo"
require "minion-common"
require "debug"

module Minion
  class MCMD
    VERSION      = "0.1.0"
    JSON_SPACING = "  "

    # mcmd is used to issue minion commands to agents via the command line.
    # It can:
    #   -  list tags
    #   -  list and query servers by id, tag, address, or organization
    #   -  query telemetry data by server ID, before/after a date, or json field
    #   -  query logs by server ID, service, before/after a date, or text field match
    #   -  show command history by server id, before/after a date
    #   -  issue commands to one or more servers
    #   -  get command responses for one or more servers
    #
    # To operate, it needs postgresql config, which can be passed via ENV variable
    # or via the command line.
    # TODO: In the future this should operate through the API server.

    class Config
      getter config

      def initialize
        @config = {} of String => String | Bool | Float32 | Float64

        parse_opts
      end

      def parse_opts
        command = [] of String
        @config["pgurl"] = ENV["PG_URL"] if ENV.has_key?("PG_URL")
        @config["synchronous"] = false
        @config["timeout"] = 30.0
        @config["format"] = "csv"

        OptionParser.new do |opts|
          opts.banner = <<-EUSAGE
          MCMD Minion Command v#{VERSION}

          Usage: mcmd [options] CMD

          show servers by id=foo, id=bar, address=127
          show telemetry from server=foo, field=load_avg, after=2020-07-15
          show logs from server=bar, text=postgresql
          show commands from server=bif, before=2020-07-15
          using server=foo, server=bar, tag=whatever run cmd arg1 arg2 argn
          show responses from command=id, server=id, tag=blah
          EUSAGE
          opts.separator ""

          opts.on("--connect [PGURL]", "A connection URL in the form of postgresql://[user[:password]@][netloc][:port][/dbname][?param1=value1&...]") do |url|
            @config["pgurl"] = url
          end

          # opts.on("-n", "--dry-run", "Display the query that would be performed, or the servers that the command would be ran against, but do not actually do it.") do
          #  @config["dry-run"] = true
          # end

          opts.on("-f", "--format", "Format the output nicely into a table instead of rendering the output as CSV.") do
            @config["format"] = "table"
          end

          opts.on("-w", "--wait", "Instead of asynchronously issuing the remote command, and then exiting, the tool will wait for responses and render them to STDOUT.") do
            @config["synchronous"] = true
          end

          opts.on("-t", "--timeout [SECONDS]", "The number of seconds to wait before timing out when waiting on the remote command.") do |seconds|
            @config["timeout"] = seconds.to_f
          end

          opts.on("-h", "--help", "Show this help") do
            puts opts
            exit
          end

          opts.on("-v", "--version", "Show the current version of MCMD.") do
            puts "MCMD v#{VERSION}"
            exit
          end

          opts.unknown_args do |args|
            args.each do |arg|
              command << arg
            end
          end
        end.parse

        @config["command"] = command.join(" ")
      end
    end

    def self.run
      config = Config.new.config
      mcmd = self.new(config)

      if mcmd.connected?
        mcmd.execute
      else
        STDERR.puts "Error: #{mcmd.error}"
        exit 1
      end
    end

    # -----

    getter error : String? = nil

    @db : DB::Database?
    @verb : String = ""
    @subject : String = ""
    @args : Array(Array(String)) = [] of Array(String)

    def initialize(@config : Hash(String, String | Bool | Float32 | Float64))
      begin
        @db = DB.open(@config["pgurl"].as(String))
      rescue ex
        @db = nil
        @error = ex.to_s
      end

      @verb, @subject, @args = parse_command if connected?
    end

    def connected?
      !@db.nil?
    end

    def parse_command : {String, String, Array(Array(String))}
      {parse_verb, parse_subject, parse_args}
    end

    def parse_verb
      if @config["command"] =~ /\s*show\s/i
        "show"
      elsif @config["command"] =~ /\s+run\s/i
        "run"
      else
        ""
      end
    end

    def parse_subject
      _verb = parse_verb
      if _verb == "show"
        @config["command"] =~ /\s*#{_verb}\s+(\w+)/
      else
        @config["command"] =~ /\s*#{_verb}\s+(.*)$/
      end

      $1.to_s
    end

    def parse_args
      @config["command"]
        .as(String)
        .scan(/\s*(\w+\s*=(?:.+?(?=(?:\s+\w+=|\srun))|[^,]+))/)
        .map do |a|
          a[0]
            .tr("\"", "")
            .strip
            .sub(/,\s*$/, "")
            .split(/\s*=\s*/, 2)
        end
    end

    def parse_remote_command
      @config["command"] =~ /\s*run\s+(.*)$/i
      argv = $1.to_s.split

      command, type = get_type_and_command_from(argv[0])
      argv[0] = command

      {argv, type}
    end

    def get_type_and_command_from(data)
      if data =~ /^\s*internal:/i
        type, command = data.split(/:/, 2)
      else
        type = "external"
        command = data
      end

      {command, type}
    end

    def execute
      debug!(@args)
      execute_show if show?

      if run?
        command_id, servers = execute_run
        if command_id && synchronous?
          execute_run_wait(command_id, servers)
        else
          puts "Executing as command #{command_id} on #{servers.size} agents."
        end
      end
    end

    def execute_run_wait(command_id, servers)
      finish_notifications = Channel(String).new
      finish_count = 0

      servers.each do |server|
        server_command = nil
        @db.try do |db|
          db.using_connection do |cnn|
            begin
              sql = <<-ESQL
              SELECT id FROM servers_commands WHERE server_id = $1 AND command_id = $2
              ESQL
              server_command = cnn.query_one(sql, server, command_id, as: {String})
            rescue ex
              STDERR.puts "Failure to get server command record for server_id=#{server} and command_id=#{command_id}.\n#{ex}"
            end
          end
        end

        if server_command
          spawn do
            begin
              start = Time.monotonic
              sleep_time = 0.001
              sleep_factor = 1.1
              sleep_max = 1.5
              still_waiting = true
              while still_waiting && ((Time.monotonic - start).to_f < @config["timeout"].as(Float64))
                @db.try do |db|
                  db.using_connection do |cnn|
                    sql = <<-ESQL
                  SELECT response_id FROM servers_commands where id = $1
                  ESQL
                    response = cnn.query_one(sql, server_command, as: {String?})

                    if response
                      sql = <<-ESQL
                    SELECT stdout, stderr, hash, updated_at FROM command_responses WHERE id = $1
                    ESQL
                      stdout, stderr, hash, updated_at = cnn.query_one(sql, response, as: {Array(String), Array(String), String, Time})
                      puts "#{server}[#{updated_at}]:\n#{stdout.join}" if !stdout.join.empty?
                      puts "#{server}[#{updated_at}]:\n#{stderr.join}".colorize(:red) if !stderr.join.empty?
                      still_waiting = false
                    end
                  end
                end

                sleep sleep_time if still_waiting
                if sleep_time < sleep_max
                  sleep_time *= sleep_factor
                  sleep_time = sleep_max if sleep_time > sleep_max
                end
              end
            ensure
              finish_notifications.send(server)
            end
          end
        end
      end

      start = Time.monotonic
      while finish_count < servers.size
        finish_notifications.receive
        finish_count += 1
      end
    end

    def synchronous?
      @config["synchronous"]
    end

    def show?
      @verb == "show"
    end

    def run?
      @verb == "run"
    end

    def execute_show
      case @subject.downcase
      when "servers"
        execute_show_servers
      when "telemetry"
        execute_show_telemetry
      when "logs"
        execute_show_logs
      when "commands"
        execute_show_commands
      when "responses"
        execute_show_responses
      end
    end

    def execute_show_servers
      servers = get_servers
      data = [] of {String, Array(String)?, Array(String)?, String?, Time?, Time?}
      @db.try do |db|
        db.using_connection do |cnn|
          servers.each do |server|
            sql = <<-ESQL
            SELECT id, aliases, addresses, organization_id, created_at, heartbeat_at
            FROM servers
            WHERE id = $1
            #{where_by_date("created_at")}
            ORDER BY heartbeat_at ASC, created_at ASC
            ESQL
            debug!(sql)
            data << cnn.query_one(sql, server, as: {String, Array(String)?, Array(String)?, String?, Time?, Time?}) rescue {"", nil, nil, nil, nil, nil}
          end
        end
      end
      if @config["format"] == "csv"
        puts "id, aliases, addresses, organization_id, created_at, heartbeat_at"
        data.each do |datum|
          puts "#{datum.map(&.to_s).join(", ")}"
        end
      else
        table_data = [] of Array(String)
        data.map do |datum|
          table_data << [
            datum[0],
            datum[1].nil? ? "" : datum[1].not_nil!.join(", "),
            datum[2].nil? ? "" : datum[2].not_nil!.join(",\n"),
            datum[3].to_s,
            datum[4].to_s,
            datum[5].to_s,
          ]
        end

        table = Tablo::Table.new(table_data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
          t.add_column("Id") { |r| r[0] }
          t.add_column("Aliases") { |r| r[1] }
          t.add_column("Addresses") { |r| r[2] }
          t.add_column("Organization Id") { |r| r[3] }
          t.add_column("Created At") { |r| r[4] }
          t.add_column("Heartbeat At") { |r| r[5] }
        end

        table.shrinkwrap!
        puts table
      end
    end

    def execute_show_telemetry
      servers = get_servers
      data = [] of {String, String, JSON::Any, Time?}
      @db.try do |db|
        db.using_connection do |cnn|
          servers.each do |server|
            sql = <<-ESQL
            SELECT server_id, uuid, data, created_at
            FROM telemetries
            WHERE server_id = $1
            #{where_by_date("created_at")}
            ORDER BY server_id ASC, created_at ASC 
            ESQL
            debug!(sql)
            cnn.query_each(sql, server) do |rs|
              data << {rs.read(String), rs.read(String), rs.read(JSON::Any), rs.read(Time)}
            end
          end
        end
      end
      if @config["format"] == "csv"
        puts "server_id, uuid, data, created_at"
        data.each do |datum|
          puts "#{datum.map(&.to_s).join(", ")}"
        end
      else
        table_data = [] of Array(String)
        data.map do |datum|
          output = ""
          begin
            if datum[2].as_a.size == 1
              output = JSON.parse(datum[2][0].as_s).to_pretty_json(JSON_SPACING)
            else
              output = datum[2].to_pretty_json(JSON_SPACING)
            end
          rescue ex
            output = datum[2].to_s
          end
          table_data << [
            datum[0],
            datum[1],
            output,
            datum[3].to_s,
          ]
        end

        table = Tablo::Table.new(table_data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
          t.add_column("Server Id") { |r| r[0] }
          t.add_column("UUID") { |r| r[1] }
          t.add_column("Data") { |r| r[2] }
          t.add_column("Created At") { |r| r[3] }
        end

        table.shrinkwrap!
        puts table
      end
    end

    def execute_show_logs
      servers = get_servers
      data = [] of {String, String, String, String, Time?}
      @db.try do |db|
        db.using_connection do |cnn|
          servers.each do |server|
            sql = <<-ESQL
            SELECT server_id, uuid, service, msg, created_at
            FROM logs
            WHERE server_id = $1
            #{where_by_date("created_at")}
            ORDER BY server_id ASC, created_at ASC 
            ESQL
            debug!(sql)
            cnn.query_each(sql, server) do |rs|
              data << {rs.read(String), rs.read(String), rs.read(String), rs.read(String), rs.read(Time)}
            end
          end
        end
      end
      if @config["format"] == "csv"
        puts "server_id, uuid, service, msg, created_at"
        data.each do |datum|
          puts "#{datum.map(&.to_s).join(", ")}"
        end
      else
        table_data = [] of Array(String)
        data.map do |datum|
          table_data << [
            datum[0],
            datum[1],
            datum[2],
            datum[3],
            datum[4].to_s,
          ]
        end

        table = Tablo::Table.new(table_data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
          t.add_column("Server Id") { |r| r[0] }
          t.add_column("UUID") { |r| r[1] }
          t.add_column("Service") { |r| r[2] }
          t.add_column("Message") { |r| r[3] }
          t.add_column("Created At") { |r| r[4] }
        end

        table.shrinkwrap!
        puts table
      end
    end

    def execute_show_commands
      servers = get_servers
      data = [] of {String, String, Array(String), String, Time?, Time?}
      @db.try do |db|
        db.using_connection do |cnn|
          servers.each do |server|
            sql = <<-ESQL
            SELECT servers_commands.server_id, commands.id, commands.argv, commands.type, servers_commands.dispatched_at, servers_commands.response_at
            FROM servers_commands, commands
            WHERE servers_commands.server_id = $1 AND servers_commands.command_id = commands.id
            #{where_by_date("servers_commands.dispatched_at")}
            ORDER BY servers_commands.server_id ASC, commands.created_at ASC 
            ESQL
            debug!(sql)
            cnn.query_each(sql, server) do |rs|
              data << {rs.read(String), rs.read(String), rs.read(Array(String)), rs.read(String), rs.read(Time?), rs.read(Time?)}
            end
          end
        end
      end
      if @config["format"] == "csv"
        puts "server_id, command_id, argv, type, dispatched_at, response_at"
        data.each do |datum|
          puts "#{datum.map(&.to_s).join(", ")}"
        end
      else
        table_data = [] of Array(String)
        data.map do |datum|
          table_data << [
            datum[0],
            datum[1],
            datum[2].join(", "),
            datum[3],
            datum[4].to_s,
            datum[5].to_s,
          ]
        end

        table = Tablo::Table.new(table_data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
          t.add_column("Server Id") { |r| r[0] }
          t.add_column("Command Id") { |r| r[1] }
          t.add_column("ARGV") { |r| r[2] }
          t.add_column("Type") { |r| r[3] }
          t.add_column("Dispatched At") { |r| r[4] }
          t.add_column("Response At") { |r| r[5] }
        end

        table.shrinkwrap!
        puts table
      end
    end

    def execute_show_responses
      servers = get_servers
      data = [] of {String, String, Array(String), Array(String), Array(String), Time?}
      @db.try do |db|
        db.using_connection do |cnn|
          servers.each do |server|
            sql = <<-ESQL
            SELECT servers_commands.server_id, commands.id, commands.argv, responses.stdout, responses.stderr, servers_commands.response_at
            FROM servers_commands, commands, command_responses as responses
            WHERE servers_commands.server_id = $1
              AND servers_commands.command_id = commands.id
              AND servers_commands.response_id = responses.id
              #{where_by_date("servers_commands.response_at")}
            ORDER BY servers_commands.server_id ASC, commands.created_at ASC 
            ESQL
            debug!(sql)
            cnn.query_each(sql, server) do |rs|
              data << {rs.read(String), rs.read(String), rs.read(Array(String)), rs.read(Array(String)), rs.read(Array(String)), rs.read(Time?)}
            end
          end
        end
      end
      if @config["format"] == "csv"
        puts "server_id, commands_id, argv, stdout, stderr, response_at"
        data.each do |datum|
          puts "#{datum.map(&.to_s).join(", ")}"
        end
      else
        table_data = [] of Array(String)
        data.map do |datum|
          stdout = JSON.parse(datum[3].join).to_pretty_json(JSON_SPACING) rescue datum[3].join("\n")
          stderr = JSON.parse(datum[4].join).to_pretty_json(JSON_SPACING).colorize(:red).to_s rescue datum[4].join("\n")
          ["out: #{stdout}", "err: #{stderr}"].each do |output|
            table_data << [
              "#{datum[0]}\n#{datum[1]}\n",
              datum[2].join(", "),
              output,
              datum[5].to_s,
            ]
          end
        end

        table = Tablo::Table.new(table_data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
          t.add_column("Server+Command Id") { |r| r[0] }
          t.add_column("ARGV") { |r| r[1] }
          t.add_column("STDOUT + STDERR") { |r| r[2] }
          t.add_column("Response At") { |r| r[3] }
        end

        table.shrinkwrap!
        puts table
      end
    end

    def execute_run
      servers = get_servers
      command_id = nil
      command, type = parse_remote_command

      if !servers.empty?
        @db.try do |db|
          db.using_connection do |cnn|
            sql = <<-ESQL
              INSERT INTO COMMANDS (argv, created_at, updated_at, type)
              VALUES ($1, now(), now(), $2)
              RETURNING id
            ESQL
            command_id = cnn.query_one(sql, command, type, as: {String})

            # Create the servers_commands records.
            servers.each do |server|
              sql = <<-ESQL
              INSERT INTO SERVERS_COMMANDS (server_id, command_id, created_at, updated_at)
              VALUES ($1, $2, now(), now())
              ESQL

              cnn.exec(sql, server, command_id)
            end

            # Insert into the command_queues
            sql = <<-ESQL
            INSERT INTO command_queues (command_id, created_at, updated_at) VALUES ($1, now(), now())
            ESQL
            cnn.exec(sql, command_id)

            # Trigger the command.
            cnn.exec("NOTIFY agent_commands")

            # Return the command ID.
          end
        end
      end
      {command_id, servers}
    end

    def get_servers
      servers = @args.dup.unshift(["", ""]).map do |arg|
        find_server_by(arg)
      end

      if servers.size > 1
        servers[1..-1]
          .reject(&.empty?)
          .reduce(servers[0]) { |a, v| a & v }
      else
        servers.flatten
      end
    end

    def find_server_by(arg)
      key, value = arg
      results = [] of String

      sql = case key.downcase
            when "server"
              "SELECT id FROM SERVERS WHERE id::text = $1 OR $1 = ANY(aliases) OR $1 = ANY(addresses) ORDER BY heartbeat_at asc, created_at asc"
            when "id"
              "SELECT id FROM SERVERS WHERE id::text = $1"
            when "alias"
              "SELECT id FROM SERVERS WHERE $1 = ANY(aliases) ORDER BY heartbeat_at asc, created_at asc"
            when "address"
              "SELECT id FROM SERVERS WHERE $1 = ANY(addresses) ORDER BY heartbeat_at asc, created_at asc"
            when "tag"
              "SELECT server_id FROM SERVERS_TAGS WHERE server_id = $1 ORDER BY server_id"
            when ""
              "SELECT id from SERVERS ORDER BY heartbeat_at asc, created_at asc"
            end

      if sql
        @db.try do |db|
          db.using_connection do |cnn|
            if key.empty?
              cnn.query_each(sql) do |rs|
                results << rs.read(String)
              end
            else
              cnn.query_each(sql, value) do |rs|
                results << rs.read(String)
              end
            end
          end
        end
      end

      results
    end

    def where_by_date(field)
      sql = [] of String
      timestamp_args = @args.select do |arg|
        arg[0] =~ /before|after|on/i
      end

      debug!("Timestamp args: #{timestamp_args.inspect}")

      timestamp_keys = timestamp_args.map(&.first).map(&.downcase)
      before_count = timestamp_keys.select { |k| k == "before" }.size
      after_count = timestamp_keys.select { |k| k == "after" }.size

      if before_count == 1 && after_count == 1
        sql << date_between(field, timestamp_args)
        timestamp_args.each { |arg| sql << date_on(field, arg) }
      else
        timestamp_args.each do |arg|
          sql << date_before_or_after(field, arg)
          sql << date_on(field, arg)
        end
      end

      debug!("Timestamp SQL: #{sql.inspect}")
      sql.reject(&.empty?).join
    end

    def date_between(field, args)
      before = nil
      after = nil
      args.each do |arg|
        key, value = arg
        if key == "before"
          before = value
        elsif key == "after"
          after = value
        end
      end

      before_cast, before_parsed_date = parse_and_cast_date_value(before)
      after_cast, after_parsed_date = parse_and_cast_date_value(after)

      if before_parsed_date && after_parsed_date
        "AND #{field} BETWEEN '#{after_parsed_date}' AND '#{before_parsed_date}'\n"
      else
        ""
      end
    end

    def date_before_or_after(field, arg)
      key, value = arg
      debug!(arg)
      key = key.downcase
      cast, parsed_date = parse_and_cast_date_value(value)
      debug!(parsed_date)

      if parsed_date && key == "before"
        "AND #{field}#{cast} < '#{parsed_date}'\n"
      elsif parsed_date && key == "after"
        "AND #{field}#{cast} > '#{parsed_date}'\n"
      else
        ""
      end
    end

    def date_on(field, arg)
      key, value = arg
      key = key.downcase
      cast, parsed_date = parse_and_cast_date_value(value)

      if parsed_date && key == "on"
        "AND #{field}#{cast} = '#{parsed_date}'\n"
      else
        ""
      end
    end

    def parse_and_cast_date_value(value)
      parsed_date = Minion::ParseDate.parse(value)
      return {"", nil} unless parsed_date

      parsed_date = parsed_date.to_s("%Y-%m-%d %H:%M:%S")
      cast = ""
      if parsed_date =~ /00:00:00/
        cast = "::date"
        parsed_date = Minion::ParseDate.parse(value).not_nil!.to_s("%Y-%m-%d")
      end

      {cast, parsed_date}
    end
  end
end

#####

Minion::MCMD.run
