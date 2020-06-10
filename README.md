# Minion Streamserver

The Streamserver acts as the communications nexus for Minion. It communicates
with Minion Agents located on remote instances in order to issue commands,
receive responses from those commands, receive telemetry, and receive logs
from those agents.

The stream server communicates with a message bus to receive its commands and
to return command output and responses from its commands, and it communicates
with a logging backend, which could be a file, or another socket, or a more
sophisticated backend like Logstash.

The Stream Server is being based on the Crystal Language version of the
[Analogger](https://github.com/wyhaines/analogger.cr) asynchronous logger and log aggregator.

## Installation

TODO: Write installation instructions here

## Usage

TODO: Write usage instructions here

## Development

TODO: Write development instructions here
