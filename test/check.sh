#!/bin/sh
# Runs the helper on the sample tabs and asserts the output is well-formed.
set -e
cd "$(dirname "$0")/.."
out=$(./bin/tidy-helper < test/sample-tabs.json)
echo "$out" | python3 -m json.tool
echo "$out" | python3 -c '
import json, sys
g = json.load(sys.stdin)["groups"]
ids = [i for x in g for i in x["ids"]]
assert len(ids) == len(set(ids)), "tab in two groups"
assert set(ids) <= set(range(1, 21)), "unknown id"
assert all(x["name"].strip() for x in g), "empty name"
print(f"OK: {len(g)} groups, {len(ids)}/20 tabs grouped")'
