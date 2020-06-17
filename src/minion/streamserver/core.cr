require "./core/*"
require "./timer"
require "./destination_registry"
require "./destination/*"
require "socket"
require "./protocol"

struct Number
  def positive?
    self > 0
  end
end

module Minion
  class StreamServer
    class Core

      property config : Config
      property invocation_arguments : ExecArguments
      property key : String
      class_property default_log : String = "STDOUT"
      class_property default_log_destination : Minion::StreamServer::Destination | Nil

      class NoPortProvided < RuntimeError
        def initialize
          @message = "The port to bind to was not provided."
        end
      end

      class BadPort < RuntimeError
        def initialize(port : String | Int32 | Nil)
          @message = "The port provided (#{port}) is invalid."
        end
      end

      EXIT_SIGNALS    = [Signal::INT, Signal::TERM]
      RELOAD_SIGNALS  = [Signal::HUP]
      RESTART_SIGNALS = [Signal::USR2]

      def initialize(command_line : CommandLine)
        @key = ""
        @config = command_line.config
        @invocation_arguments = ExecArguments.new(command: File.expand_path(PROGRAM_NAME), args: ARGV)
        @groups = Hash(String, Group).new 
        @cull_tracker = Hash(
          String, Hash(
            String, StaticArray(String|UInt32, 2)
          )
        ).new {|h,k| h[k] = Hash(
          String, StaticArray(String|UInt32,2)).new {|h, k| h[k] = StaticArray(String|UInt32, 2).new(0.to_u32)}
        }
        @queue = Hash(String, Channel(Frame)).new {|h,k| h[k] = Channel(Frame).new}
        @handlers = Hash(String, Fiber).new
        @rcount = 0
        @wcount = 0
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
          spawn handle(client)
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
          service = frame.data[1]
          log = group.logs[service]?
          if log && log.cull
            cull_tracker = @cull_tracker[id]
            if cull_tracker[service][0] == frame.data[2]
              cull_tracker[service][1] = cull_tracker[service][1].as(UInt32) + 1
            elsif cull_tracker[service][1].as(UInt32) > 0
              new_frame = Frame.new(
                verb: frame.verb,
                uuid: frame.uuid,
                data: [
                  frame.data[0],
                  frame.data[1],
                  "Previous message repeated #{cull_tracker[service][1]} times."
                ])
              log.destination.not_nil!.channel.send(new_frame) if log
              cull_tracker[service][1] = 0
              cull_tracker[service][0] = "\x00\x00"
            else
              cull_tracker[service][1] = frame.data[2]
              log.destination.not_nil!.channel.send(frame) if log
            end
          else
            log.destination.not_nil!.channel.send(frame) if log
          end
        end
      end

      def handle_response(frame)
        id = frame.data[0]
        group = @groups[id]?
        if group
          group.responses.each do |response|
            response.destination.not_nil!.channel.send(frame)
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
        case group && frame.data[1]
        when "authenticate-agent"
          if group.not_nil!.key == frame.data[2]
            reply = Frame.new(verb: :response, data: ["accepted"])
          else
            reply = Frame.new(verb: :response, data: ["denied"])
          end
          protocol.send_data(reply)
        else
          # NOP
        end
      end

      ##########
      def setup_signal_traps
        safe_trap(signal_list: EXIT_SIGNALS) { handle_pending_and_exit }
        safe_trap(signal_list: RELOAD_SIGNALS) { cleanup_and_reopen }
        safe_trap(signal_list: RESTART_SIGNALS) do
          purge_queues
          Process.exec(
            command: invocation_arguments.command,
            args: invocation_arguments.args
          )
        end
      end

      def safe_trap(signal_list : Array(Signal), &operation)
        signal_list.each do |sig|
          sig.trap { operation.call }
        end
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
          group_logs = populate_logs(group)
          group_telemetry = populate_telemetry(group)
          group_responses = populate_responses(group)

          @groups[group.id] = Group.new(
            id: group.id,
            key: group.key,
            logs: group_logs,
            telemetry: group_telemetry,
            responses: group_responses)
        end
      end

      def populate_logs(group)
        group_logs = {} of String => Log

        group.logs.each do |log|
          next unless log.service

          service_array = log.service.as?(Array)
          if service_array
            service_array.each do |loglog|
              new_log = Log.new(
                service: loglog,
                raw_destination: log.destination,
                destination: destination(log.destination, log.type, log.options),
                cull: log.cull,
                type: log.type,
                options: log.options)
              group_logs[new_log.service] = new_log
            end
          else
            service_string = log.service.to_s
            new_log = Log.new(
              service: service_string,
              raw_destination: log.destination,
              destination: destination(log.destination, log.type, log.options),
              cull: log.cull,
              type: log.type,
              options: log.options)
            group_logs[new_log.service] = new_log
          end
        end

        group_logs
      end

      def populate_telemetry(group)
        group_telemetry = [] of Telemetry

        group.telemetry.each do |telemetry|
          group_telemetry << Telemetry.new(
            type: telemetry.type,
            options: telemetry.options,
            destination: destination(telemetry.destination, telemetry.type, telemetry.options)
          )
        end

        group_telemetry
      end

      def populate_responses(group)
        group_responses = [] of Response

        group.responses.each do |response|
          group_responses << Response.new(
            type: response.type,
            options: response.options,
            destination: destination(response.destination, response.type, response.options)
          )
        end

        group_responses
      end

      def destination(destination : Minion::StreamServer::Destination)
        destination.reopen() if destination.respond_to? :reopen
      end

      def destination(destination : String, type : String? = "file", options : Array(String)? = ["ab"])
        type ||= "file"
        type = type.to_s.downcase

        obj = Minion::StreamServer::DestinationRegistry.get(type)
        obj.open(destination, options)
      rescue e : Exception
        STDERR.puts e
        STDERR.puts e.backtrace.join("\n")
        raise e
      end

      ##########
      def set_config_defaults
        @config.host ||= "127.0.0.1"

        #@config.interval = @config.interval.nil? ? 1 : @config.interval.to_i
        @config.syncinterval = @config.syncinterval.nil? ? 60 : @config.syncinterval.to_i
        Minion::StreamServer::Core.default_log = @config.default_log.to_s.blank? ? "STDOUT" : @config.default_log.to_s
        Minion::StreamServer::Core.default_log_destination = destination(destination: "STDERR", type: "Io")
      end

      ##########
      def create_periodic_timers
        @clock_update_timer = Minion::StreamServer::Timer.new(periodic: true) { @now = Time.local }
        # @write_queue_timer = Minion::StreamServer::Timer.new(
        #   interval: @config.interval.to_i,
        #   periodic: true
        # ) { write_queue }
        @flush_queue_timer = Minion::StreamServer::Timer.new(
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
          group.responses.each do |response|
            response.destination.not_nil!.flush rescue Exception
          end
        end
      end

      # This needs to be reworked along with the signal handler so that it doesn't die until the channels
      # are all flushed of unwritten content.
      def any_in_queue?
        any = 0
        @queue.each do |service, q|
          next unless (log = @logs[service])

          q.each do |m|

            any += 1
          end
        end
        any.positive? ? any : false
      end

      def purge_queues
        flush_queue
        cleanup
      end

      def handle_pending_and_exit
        STDOUT.puts "Caught termination signal. Exiting..." # TODO: Add better signal handling notifcations
        purge_queues
        exit
      end

      def fsync_or_flush(dest)
#        if !dest.closed?
#          if dest.responds_to?(:fsync)
#            dest.fsync
#          elsif dest.responds_to?(:flush)
#            dest.flush
#          end
#        end
      end

      def cleanup
#        @logs.each do |_service, l|
#          if !(dest = l.destination).nil?
#            fsync_or_flush(dest)
#            dest.close unless dest.closed? || [STDERR, STDOUT].includes?(dest)
#          end
#        end
      end

      def cleanup_and_reopen
#        @logs.each do |_service, l|
#          if !(dest = l.destination).nil?
#            fsync_or_flush(dest)
#            if dest.responds_to?(:reopen)
#              dest.reopen(dest) if ![STDERR, STDOUT].includes?(dest)
#            end
#          end
#        end
      end
    end
  end
end
