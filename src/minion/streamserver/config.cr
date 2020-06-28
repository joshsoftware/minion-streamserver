require "yaml"
require "./config/*"

# port: 47990
# host: 127.0.0.1
# default_log: log/default.log
# daemonize: false
# syncinterval: 1
# pidfile: log/streamserver.pid
# groups:
#   id: some_string
#   key: authentication_key
#   logs:
#     - service:
#       - a
#       - b
#     logfile: log/a.log
#     cull: true
#     - service: c
#       logfile: log/c.log
#       cull: true
#   telemetry:
@[YAML::Serializable::Options(emit_nulls: true)]

module Minion
  class StreamServer
    class Config
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      @[YAML::Field(key: "port")]
      property port : String = "6766"

      @[YAML::Field(key: "host")]
      property host : String = "127.0.0.1"

      @[YAML::Field(key: "syncinterval")]
      property syncinterval : String | Int32 = 60

      @[YAML::Field(key: "default_log")]
      property default_log : String?

      @[YAML::Field(key: "daemonize")]
      property daemonize : Bool?

      @[YAML::Field(key: "pidfile")]
      property pidfile : String?

      @[YAML::Field(
        key: "service_defaults",
        default: {
          "service"     => nil,
          "destination" => nil,
          "cull"        => true,
          "type"        => nil,
          "options"     => ["a+"],
        })]
      property service_defaults : Minion::StreamServer::Config::Service?

      @[YAML::Field(key: "groups")]
      property groups : Array(Minion::StreamServer::Config::Group)
    end
  end
end
