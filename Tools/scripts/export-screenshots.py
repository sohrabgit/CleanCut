#!/usr/bin/env python3
"""Renames attachments exported by `xcresulttool export attachments` to their test-given names."""
import json, os, re, sys

folder = sys.argv[1]
manifest = json.load(open(os.path.join(folder, "manifest.json")))
for test in manifest:
    for attachment in test.get("attachments", []):
        name = re.sub(r"_\d+_[0-9A-F-]+(\.\w+)$", r"\1", attachment["suggestedHumanReadableName"])
        os.replace(os.path.join(folder, attachment["exportedFileName"]), os.path.join(folder, name))
        print(name)
