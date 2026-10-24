#!/usr/bin/env bash
# Checks that the field numbers and wire types used by our hand-written
# Meshtastic decoder/encoder match the official .proto schema.
#
# The Meshtastic protobufs are GPL-3.0, so nothing derived from them is
# kept in this repository: protoc and the .proto files are fetched into a
# temporary directory, only a binary descriptor set is produced, and the
# test reads it at runtime.
#
# Usage: tool/check_meshtastic_schema.sh [meshtastic-protobufs-tag]
#   MESHTASTIC_PROTOBUFS_VERSION (default v2.8.1), PROTOC_VERSION (36.2)
#   PROTOC=/path/to/protoc and PROTO_DIR=/path/to/protobufs reuse local copies.
set -euo pipefail

version="${1:-${MESHTASTIC_PROTOBUFS_VERSION:-v2.8.1}}"
protoc_version="${PROTOC_VERSION:-36.2}"
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ -z "${PROTOC:-}" ]]; then
  curl -sSL -o "$work/protoc.zip" \
    "https://github.com/protocolbuffers/protobuf/releases/download/v${protoc_version}/protoc-${protoc_version}-linux-x86_64.zip"
  unzip -q "$work/protoc.zip" -d "$work/protoc"
  PROTOC="$work/protoc/bin/protoc"
  protoc_include="$work/protoc/include"
else
  protoc_include="$(dirname "$PROTOC")/../include"
fi

if [[ -z "${PROTO_DIR:-}" ]]; then
  curl -sSL -o "$work/protobufs.tar.gz" \
    "https://github.com/meshtastic/protobufs/archive/refs/tags/${version}.tar.gz"
  mkdir -p "$work/protobufs"
  tar -xzf "$work/protobufs.tar.gz" -C "$work/protobufs" --strip-components=1
  PROTO_DIR="$work/protobufs"
fi

"$PROTOC" --include_imports \
  --descriptor_set_out="$work/meshtastic.desc" \
  -I"$PROTO_DIR" -I"$protoc_include" \
  meshtastic/mesh.proto meshtastic/telemetry.proto meshtastic/portnums.proto

echo "Checking against Meshtastic protobufs ${version}"
cd "$root"
MESHTASTIC_DESCRIPTOR_SET="$work/meshtastic.desc" \
  flutter test test/meshtastic_schema_test.dart
