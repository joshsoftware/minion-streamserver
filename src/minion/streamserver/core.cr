require "random/isaac"
require "./core/*"
require "./destination_registry"
# require "./destination/*"
require "socket"
require "./protocol"
require "./connection_registry"
require "./connection_manager"
require "./command/processor_registry"
require "./command/listener_registry"
require "./types"

module Minion
  class StreamServer
    class Core
      include Minion::Util

      @@prng = Random::ISAAC.new

      property config : Config
      property invocation_arguments : ExecArguments
      property key : String
      class_property default_log : String = "STDOUT"
      class_property default_log_destination : Minion::StreamServer::Destination = setup_destination(destination: "STDERR", type: "Io")

      EXIT_SIGNALS    = [Signal::INT, Signal::TERM]
      RELOAD_SIGNALS  = [Signal::HUP]
      RESTART_SIGNALS = [Signal::USR2]

      def initialize(command_line : CommandLine)
        @key = ""
        @config = command_line.config
        @invocation_arguments = ExecArguments.new(command: File.expand_path(PROGRAM_NAME), args: ARGV)
        @groups = Hash(String, Group).new
        @cull_tracker = CullTracker.new
        @queue = Hash(String, Channel(Frame)).new { |h, k| h[k] = Channel(Frame).new }
        @handlers = [] of Fiber
        @rcount = 0
        @wcount = 0
        @registered_agents = {} of String => Protocol
        @registered_agents_by_group = Hash(Group, Array(Protocol)).new { |h, k| h[k] = Array(Protocol).new }
        @now = Time.local
      end

      def start
        handle_daemonize
        setup_signal_traps
        @config.groups ||= [] of Minion::StreamServer::Config::Group
        check_config_settings
        populate_groups
        set_config_defaults
        create_periodic_timers

        server = TCPServer.new(
          host: @config.host,
          port: @config.port.to_i,
          reuse_port: true
        )

        while client = server.accept?
          @handlers << spawn handle(client)
        end
      end

      def setup_database_monitor
        spawn do
        end
      end

      def handle(client)
        # Or this way?
        #     client.sync = false if client.responds_to?(:sync=)
        # if client.is_a?(IO::Buffered)
        #  client.sync = false
        # end
        #     client.read_buffering = true if client.responds_to?(:read_buffering)

        handler = Minion::StreamServer::Protocol.new(client: client, logger: self)
        until client.closed?
          handler.receive
        end
      ensure
        client.close rescue IO::Error
      end

      # TODO: This handle* stuff should probably all live in the handler...
      # aka the Protocol.
      #
      # L -- log
      # C - Command
      # R - Response
      # T - Telemetry
      # Q - Query Key/Value Store
      # S - Set Key/Value
      def handle_frame(frame, protocol)
        case frame.verb
        when "L"
          handle_log(frame)
        when "R"
          handle_response(frame)
        when "T"
          handle_telemetry(frame)
        when "C"
          handle_command(frame, protocol)
        else
          # Any other frames currently die here; maybe in the future we log them or something?
        end
      end

      def handle_log(frame)
        id = frame.data[0]
        group = @groups[id]?
        if group
          server = frame.data[1]
          service_label = frame.data[2]
          service = if group.logs.has_key?(service_label)
                      group.logs[service_label]
                    elsif group.default_log.is_a?(Minion::StreamServer::Core::Service)
                      group.default_log.as(Minion::StreamServer::Core::Service)
                    else
                      nil
                    end

          if service && service.cull
            cull_tracker = @cull_tracker[id]
            if cull_tracker[service_label][server].msg == string_from_string_or_array(frame.data[3])
              cull_tracker[service_label][server].increment
            elsif cull_tracker[service_label][server].positive?
              new_uuid = frame.uuid
              loop do
                timestamp = frame.uuid.as(Minion::UUID).timestamp
                identifier = @@prng.random_bytes(6).to_slice
                new_uuid = UUID.new(timestamp: timestamp.not_nil!, identifier: identifier)
                break if new_uuid != frame.uuid
              end

              new_frame = Frame.new(
                verb: frame.verb,
                uuid: new_uuid,
                data: [
                  frame.data[0].as(String),
                  frame.data[1].as(String),
                  frame.data[2].as(String),
                  "Previous message repeated #{cull_tracker[service_label][server].count} times.",
                ])
              service.destination.not_nil!.channel.send(new_frame)
              cull_tracker[service_label][server].reset(string_from_string_or_array(frame.data[3]))
              service.destination.not_nil!.channel.send(frame)
            else
              cull_tracker[service_label][server].msg = string_from_string_or_array(frame.data[3])
              service.destination.not_nil!.channel.send(frame)
            end
          else
            service.destination.not_nil!.channel.send(frame) if service
          end
        end
      end

      def handle_response(frame)
        id = frame.data[0]
        group = @groups[id]?
        if group
          unless group.command.nil?
            group.command.not_nil!.each do |command|
              command.processor.not_nil!.response_queue.send(frame)
            end
          end
        end
      end

      def handle_telemetry(frame)
        id = frame.data[0]
        group = @groups[id]?
        if group
          group.telemetry.each do |telemetry|
            telemetry.destination.not_nil!.channel.send(frame)
          end
        end
      end

      def handle_command(frame, protocol)
        id = frame.data[0]
        group = @groups[id]?
        # This assumes that there are few commands that an agent can send to the streamserver.
        if group
          case frame.data[2]
          when "authenticate-agent"
            if group.key.to_s == string_from_string_or_array(frame.data[3])
              reply = Frame.new(verb: :response, data: [frame.uuid.to_s, "accepted"])
              register_agent(group, frame, protocol)
              protocol.send_data(reply)
            else
              reply = Frame.new(verb: :response, data: [frame.uuid.to_s, "denied"])
              protocol.send_data(reply)
              protocol.close
            end
          when "heartbeat"
            record_heartbeat(group, frame)
            reply = Frame.new(verb: :response, data: [frame.uuid.to_s, "recorded"])
            protocol.send_data(reply)
          else
            # NOP
          end
        end
      end

      def record_heartbeat(group, frame)
        id = frame.data[0]
        group = @groups[id]?
        server_id = frame.data[1]
        unless group.nil?
          destination = group.not_nil!.command.not_nil!.first.destination
          ConnectionManager.open(destination.not_nil!).using_connection do |cnn|
            sql = <<-ESQL
            UPDATE servers
            SET heartbeat_at = now()
            where id = $1
            ESQL
            cnn.exec(sql, server_id)
          end
        end
      end

      def register_agent(group, frame, protocol)
        register_agent_connection(frame.data[1].to_s, protocol, group)
        id = frame.data[0]
        group = @groups[id]?
        agent_address = protocol.client.remote_address.address
        server_id = frame.data[1]
        unless group.nil?
          destination = group.not_nil!.command.not_nil!.first.destination
          if rec = server_record(destination, frame.data[1], protocol)
            ConnectionManager.open(destination.not_nil!).using_connection do |cnn|
              if rec[1].includes? agent_address
                sql = <<-ESQL
                UPDATE servers
                SET updated_at = now()
                WHERE id = $1
                ESQL
                cnn.exec(sql, server_id)
              else
                sql = <<-ESQL
                UPDATE servers
                SET addresses = array_append(addresses, $1), updated_at = now()
                WHERE id = $2
                ESQL
                cnn.exec(sql, agent_address, server_id)
              end
            end
          else
            ConnectionManager.open(destination.not_nil!).using_connection do |cnn|
              sql = <<-ESQL
              INSERT INTO servers (id, addresses, created_at, updated_at)
              VALUES ($1, Array[$2], now(), now())
              ESQL
              cnn.exec(sql, server_id, agent_address)
            end
          end
        end
      end

      def server_record(destination, server_id, protocol)
        sql = <<-ESQL
        SELECT id, addresses
        FROM servers
        WHERE id = $1
        ESQL
        rec = nil
        ConnectionManager.open(destination.not_nil!).using_connection do |cnn|
          begin
            rec = cnn.query_one(sql, server_id, as: {String, Array(String)})
          rescue DB::NoResultsError
            rec = nil
          end
        end

        rec
      end

      def register_agent_connection(agent_id, handler, group)
        @registered_agents_by_group[group] << handler
        @registered_agents[agent_id] = handler
      end

      ##########
      def handle_daemonize
        daemonize if @config.daemonize
        File.open(@config.pidfile.to_s, "w+") { |fh| fh.puts Process.pid } if @config.pidfile
      end

      ##########
      def check_config_settings
        raise NoPortProvided.new unless @config.port
        raise BadPort.new(@config.port) unless @config.port.to_s.to_i.positive?
      end

      ##########
      # Iterate through the group in the configuration file, creating group and log
      # records as needed.
      def populate_groups
        # Read through each Group stanza
        @config.groups.each do |group|
          failure_notification_channel = Channel(Bool).new
          group_logs = populate_services(group, failure_notification_channel)
          group_telemetry = populate_telemetry(group, failure_notification_channel)
          # group_responses = populate_responses(group)
          group_command = populate_command(group)
          default_log = group_logs.values.find(if_none: "default") { |service| service.default }
          @groups[group.id] = Group.new(
            id: group.id,
            key: group.key,
            logs: group_logs,
            default_log: default_log,
            telemetry: group_telemetry,
            command: group_command,
            failure_notification_channel: failure_notification_channel)

          spawn handle_group_failure(@groups[group.id])
        end
      end

      def handle_group_failure(group)
        loop do
          status = group.failure_notification_channel.receive

          if status # There was a failure of the group
            group.valid = false
            disconnect_all_group_clients(group)
          else
            group.valid = true
          end
        end
      end

      def disconnect_all_group_clients(group)
        @registered_agents_by_group[group].each do |protocol|
          protocol.close
        end
      end

      def populate_services(group, failure_notification_channel)
        group_services = {} of String => Service

        group.services.each do |service|
          next unless service.service

          service_array = service.service.as?(Array)

          destination_or_default =
            service.destination ||
              group.service_defaults.not_nil!.destination ||
              @config.service_defaults.not_nil!.destination ||
              "default"
          type_or_default =
            service.type ||
              group.service_defaults.not_nil!.type ||
              @config.service_defaults.not_nil!.type ||
              "io"
          options_or_default =
            service.options ||
              group.service_defaults.not_nil!.options ||
              @config.service_defaults.not_nil!.options ||
              ["a+"]
          if service_array
            service_array.each do |label|
              new_service = Service.new(
                service: label,
                raw_destination: destination_or_default,
                destination: Minion::StreamServer::Core.setup_destination(
                  destination: destination_or_default,
                  type: type_or_default,
                  options: options_or_default,
                  failure_notification_channel: failure_notification_channel),
                cull: service.cull ||
                      group.service_defaults.not_nil!.cull ||
                      @config.service_defaults.not_nil!.cull ||
                      true,
                type: type_or_default,
                options: options_or_default,
                default: service.default)
              group_services[new_service.service] = new_service
            end
          else
            service_string = service.service.to_s
            new_service = Service.new(
              service: service_string,
              raw_destination: destination_or_default,
              destination: Minion::StreamServer::Core.setup_destination(
                destination: destination_or_default,
                type: type_or_default,
                options: options_or_default,
                failure_notification_channel: failure_notification_channel),
              cull: service.cull ||
                    group.service_defaults.not_nil!.cull ||
                    @config.service_defaults.not_nil!.cull ||
                    true,
              type: type_or_default,
              options: options_or_default,
              default: service.default)
            group_services[new_service.service] = new_service
          end
        end

        group_services
      end

      def populate_telemetry(group, failure_notification_channel)
        group_telemetry = [] of Telemetry

        group.telemetry.each do |telemetry|
          destination_or_default =
            telemetry.destination ||
              group.service_defaults.not_nil!.destination ||
              @config.service_defaults.not_nil!.destination ||
              "default"
          type_or_default =
            telemetry.type ||
              group.service_defaults.not_nil!.type ||
              @config.service_defaults.not_nil!.type ||
              "io"
          options_or_default =
            telemetry.options ||
              group.service_defaults.not_nil!.options ||
              @config.service_defaults.not_nil!.options ||
              ["a+"]
          group_telemetry << Telemetry.new(
            type: type_or_default,
            options: options_or_default,
            destination: Minion::StreamServer::Core.setup_destination(
              destination: destination_or_default,
              type: type_or_default,
              options: options_or_default,
              failure_notification_channel: failure_notification_channel)
          )
        end

        group_telemetry
      end

      def populate_responses(group, failure_notification_channel)
        group_responses = [] of Response

        group.responses.each do |response|
          group_responses << Response.new(
            type: response.type,
            options: response.options,
            destination: Minion::StreamServer::Core.setup_destination(
              destination: response.destination,
              type: response.type,
              options: response.options,
              failure_notification_channel: failure_notification_channel)
          )
        end

        group_responses
      end

      def populate_command(group)
        group_command = [] of Command

        default_command = @config.try(&.command).try(&.first)

        unless group.command.nil?
          group.command.not_nil!.each do |command|
            processor = setup_processor(
              type: command.processor || default_command.try(&.processor).not_nil!,
              agent_registry: @registered_agents,
              destination: command.destination || default_command.try(&.destination).not_nil!
            )
            listener = setup_listener(
              type: command.listener || default_command.try(&.listener).not_nil!,
              channel: command.channel || default_command.try(&.channel).not_nil!,
              destination: command.destination || default_command.try(&.destination).not_nil!,
              processor: processor
            )
            group_command << Command.new(
              listener: listener,
              processor: processor,
              destination: command.destination || default_command.try(&.destination).not_nil!,
              source: command.source || default_command.try(&.source).not_nil!,
              channel: command.channel || default_command.try(&.channel).not_nil!
            )
          end
        else
          unless default_command.nil?
            processor = setup_processor(
              type: default_command.try(&.processor).not_nil!,
              agent_registry: @registered_agents,
              destination: default_command.try(&.destination).not_nil!
            )
            listener = setup_listener(
              type: default_command.try(&.listener).not_nil!,
              channel: default_command.try(&.channel).not_nil!,
              destination: default_command.try(&.destination).not_nil!,
              processor: processor
            )
            group_command << Command.new(
              listener: listener,
              processor: processor,
              destination: default_command.try(&.destination),
              source: default_command.try(&.source),
              channel: default_command.try(&.channel)
            )
          end
        end
      end

      ##########
      def create_periodic_timers
        @clock_update_timer = Minion::Timer.new(periodic: true) { @now = Time.local }
        @flush_queue_timer = Minion::Timer.new(
          interval: @config.syncinterval.to_i,
          periodic: true
        ) { flush_queue }
      end

      def flush_queue
        @groups.each_value do |group|
          group.logs.each_value do |log|
            log.destination.not_nil!.flush rescue Exception
          end
          group.telemetry.each do |telemetry|
            telemetry.destination.not_nil!.flush rescue Exception
          end
        end
      end

      # This needs to be reworked along with the signal handler so that it doesn't die until the channels
      # are all flushed of unwritten content.
      def any_in_queue?
        any = 0
        @queue.each do |service, q|
          next unless (@logs[service])

          q.each do
            any += 1
          end
        end
        any.positive? ? any : false
      end

      def purge_queues
        flush_queue
      end

      def handle_pending_and_exit
        STDOUT.puts "Caught termination signal. Exiting..." # TODO: Add better signal handling notifcations
        purge_queues
        exit
      end
    end
  end
end
