require "yaml"
require "option_parser"
require "./config"

module Minion
  class StreamServer
    class CommandLine
      property config : Config

      def initialize
        @config = parse_options
      end

      def parse_options
        empty_config = <<-EYAML
      ---
      groups: []
      EYAML
        config = Config.from_yaml(empty_config)
        # Config file to read
        #
        # port: 12345
        # secret: abcdef
        # interval: 1
        # default_log: /var/log/emlogger
        # logs:
        # - service: client1
        #   logfile: /foo/bar.txt
        #   cull: true
        #
        OptionParser.new do |opts|
          opts.banner = "StreamServer v#{Minion::StreamServer::VERSION}\nUsage: streamserver [options]"
          opts.separator ""
          opts.on("-c", "--config CONFFILE", "The configuration file to read.") do |conf|
            config = Config.from_yaml(File.read(conf))
          end
          opts.on("-p", "--port [PORT]", "The port to receive connections on.") do |port|
            config.port = port
          end
          opts.on("-h", "--host [HOST]", "The host to bind the connection to.") do |host|
            config.host = host
          end
          opts.on("-s", "--syncinterval [INTERVAL]", "The interval between queue syncs.  Defaults to 60 seconds.") do |interval|
            config.syncinterval = interval
          end
          opts.on("-d", "--default [PATH]", "The default log destination.  Defaults to stdout.") do |default|
            config.default_log = default
          end
          opts.on("-x", "--daemonize", "Tell the StreamServer to daemonize itself.") do
            config.daemonize = true
          end
          opts.on("-w", "--writepid [FILENAME]", "The filename to write a PID file to.") do |pidfile|
            config.pidfile = pidfile || "streamserver.pid"
          end
          opts.on("--help", "Show this help") do
            puts opts
            exit
          end
          opts.on("-v", "--version", "Show the current version of StreamServer.") do
            puts "StreamServer v#{Minion::StreamServer::VERSION}"
            exit
          end
          opts.invalid_option do |flag|
            STDERR.puts "Error: #{flag} is not a valid option."
            STDERR.puts opts
            exit(1)
          end
        end.parse

        puts
        config
      end
    end
  end
end
