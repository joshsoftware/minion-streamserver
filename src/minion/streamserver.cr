require "./streamserver/version"
require "minion-common"
require "./streamserver/exec"

Minion::StreamServer::Exec.run
