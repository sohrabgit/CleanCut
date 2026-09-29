#!/bin/sh
# Condenses xcodebuild output to diagnostics and test results.
# Passes xcodebuild's exit status through when used with `set -o pipefail`.
grep --line-buffered -E "^/.*: (error|warning): |error: |✘|Test run|Suite .* failed|\*\* (BUILD|TEST|ARCHIVE) " || true
