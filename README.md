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

## Building The Software

The Minion server and the CLI tool (MCMD) for Minion are written with the [https://crystal-lang.org/](Crystal Language.

To build the software, Crystal must be installed in order for the software to be compiled.

Full instructions for a wide variety of platforms are available on [https://crystal-lang.org/install/](the Crystal web site). A couple of the more common scenarios are summarized below:

### Mac OS

Using Homebrew:

```
brew update
brew install crystal
```

### Ubuntu

Add the signing key and the distribution repository to your configuration:

```
curl -sSL https://dist.crystal-lang.org/apt/setup.sh | sudo bash
```

If you prefer manual control over those steps:

```
curl -sL "https://keybase.io/crystal/pgp_keys.asc" | sudo apt-key add -
echo "deb https://dist.crystal-lang.org/apt crystal main" | sudo tee /etc/apt/sources.list.d/crystal.list
sudo apt-get update
```

After, you can install Crystal. For full support of all language features, some optional libraries are recommended:

```
sudo apt update
sudo apt install libssl-dev      # for using OpenSSL
sudo apt install libxml2-dev     # for using XML
sudo apt install libyaml-dev     # for using YAML
sudo apt install libgmp-dev      # for using Big numbers
sudo apt install libz-dev        # for using crystal play
```

None of these are strictly necessary, but unless one has a reason not to install them, all are recommended.

Installing Crystal is done through this command:

```
sudo apt update
sudo apt install crystal
```

### Building The Executables

To compile all binaries for deployment, the recommended command line is:

```
shards build --release -p -s -t --error-trace
```

This will build both `streamserver` and `mcmd` and place them in the `bin/` directory. Either may be built individually by specifying just it on the command line:

```
shards build mcmd --release -p -s -t --error-trace
```

The above commands build dynamically linked executables. To build a statically linked executable, just add `--static` to the command line:

```
shards build --release --static -p -s -t --error-trace
```

The `--error-trace` includes stack trace information in the build. If it is omitted, the build will be slightly smaller, but if there is an exception, the error message may not be useful for diagnosing the failure.