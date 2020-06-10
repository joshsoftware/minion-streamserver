module Analogger
  class Config
    @[YAML::Serializable::Options(emit_nulls: true)]
    class Log
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      # service
      # levels
      # logfile
      # cull
      # type
      # options
      @[YAML::Field(key: "service")]
      property service : String | Array(String) = "default"

      @[YAML::Field(key: "levels")]
      property levels : String | Array(String) | Hash(String, Bool) | Nil

      @[YAML::Field(key: "logfile")]
      property logfile : String

      @[YAML::Field(key: "cull")]
      property cull : Bool = true

      @[YAML::Field(key: "type")]
      property type : String = "file"

      @[YAML::Field(key: "options")]
      property options : Array(String) = ["ab"]

      @[YAML::Field(key: "default")]
      property default : Bool = false
    end
  end
end
