module String::EnvConverter
  def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
    unless node.is_a?(YAML::Nodes::Scalar)
      node.raise "Expected scalar, not #{node.class}"
    end
    nv = node.value.gsub(/ENV\["(\w*)"\]/) { ENV.has_key?($1) ? ENV[$1] : "" }
  end
end
