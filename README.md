# Minion StreamServer

The Streamserver acts as the communications nexus for Minion. It communicates
with Minion Agents located on remote instances in order to issue commands,
receive responses from those commands, receive telemetry, and receive logs
from those agents.

## Configuration

The configuration for the StreamServer gives it all of the operational input
that tells it how to do it's job. A configuration file has multiple parameters,
some of which are optional, and some of which are required.

For example:

```yaml
---
service_defaults:
  service: default
  type: postgresql
  destination: postgresql://postgres@127.0.0.1/minion
  cull: true
port: 47990
host: 0.0.0.0
default_log: log/default.log
daemonize: false
syncinterval: 1
pidfile: log/streamserver.pid
command:
  - listener: postgresql
    destination: postgresql://postgres@127.0.0.1/minion
    channel: agent_commands
    processor: postgresql
groups:
  - id: "test-group-1"
    key: "ee2df8e807e99f6d5ee48b00b4558b069d3af0e25a9c3fdf741952857b2bd84f"
    services:
      - service:
        - a
        - b
        type: file
        destination: log/a.log
        cull: true
        levels: a,b,c,d
      - service: c
        type: file
        destination: log/c.log
        cull: true
    telemetry:
      - destination: STDERR
        type: io
    responses:
      - destination: STDERR
        type: io
  - id: "test-group-2"
    key: "798c733ba086c606fa8a925ab69bebf1cc44ee11a19ac81eaa4689774a6b6b04"
    service_defaults:
      service: default
      type: postgresql
      destination: postgresql://postgres@127.0.0.1/minion
      options: []
    services:
      - service: pg
      - service: auth
      - service: null
        destination: /dev/null
        cull: false
      - service: stderr
        destination: STDERR
        type: io
        cull: true
        default: true
    telemetry:
      - label: telemetry 
    responses:
      - destination: STDERR
        type: io
```
