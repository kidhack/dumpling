#!/bin/sh
# Runs the app's real Sorter against sample items on this Mac's on-device model (macOS 26+, Apple Intelligence on).
set -e
cd "$(dirname "$0")"
OUT="${TMPDIR:-/tmp}/dumpling-sortcheck"
swiftc -o "$OUT" ../../DumplingApp/Sorting/Sorter.swift ../../DumplingApp/Sorting/PageReader.swift stub.swift main.swift
"$OUT" "$@"
