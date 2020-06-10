require "yaml"
require "./config/log"

# port: 47990
# host: 127.0.0.1
# default_log: log/default.log
# daemonize: false
# syncinterval: 1
# pidfile: log/analogger.pid
# logs:
# - service:
#   - a
#   - b
#   logfile: log/a.log
#   cull: true
#   levels: a,b,c,d
# - service: c
#   logfile: log/c.log
#   cull: true

@[YAML::Serializable::Options(emit_nulls: true)]

module Analogger
  class Config
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    @[YAML::Field(key: "port")]
    property port : String = "6766"

    @[YAML::Field(key: "host")]
    property host : String = "127.0.0.1"

    @[YAML::Field(key: "secret")]
    property secret : String | Nil

    @[YAML::Field(key: "key")]
    property key : String | Nil

    @[YAML::Field(key: "levels")]
    property levels : String | Array(String) | Hash(String, Bool) | Nil

    @[YAML::Field(key: "interval")]
    property interval : String | Int32 = 1

    @[YAML::Field(key: "syncinterval")]
    property syncinterval : String | Int32 = 60

    @[YAML::Field(key: "default_log")]
    property default_log : String | Nil

    @[YAML::Field(key: "daemonize")]
    property daemonize : Bool | Nil

    @[YAML::Field(key: "pidfile")]
    property pidfile : String | Nil

    @[YAML::Field(key: "logs")]
    property logs : Array(Analogger::Config::Log)
  end
end
