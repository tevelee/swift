#!/usr/bin/env bash
set -euo pipefail

swift_source="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pack_build="${PACK_BUILD_DIR:-$swift_source/../build/receiver-poc-release/swift-macosx-arm64}"
pack_ninja="${PACK_NINJA:-$pack_build/../ninja-build/ninja}"
pack_logs="${PACK_LOG_DIR:-$swift_source/../pack-destructuring-poc/logs}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.2.0-Beta.3.app/Contents/Developer}"
pack_native_tools="$(dirname "$(/usr/bin/xcrun --toolchain XcodeDefault --find clang)")"
export SWIFT_DRIVER_TEST_OPTIONS="${SWIFT_DRIVER_TEST_OPTIONS:-} -tools-directory $pack_native_tools"
mkdir -p "$pack_logs"

"$pack_ninja" -C "$pack_build" -j "${PACK_JOBS:-6}" \
  swift-frontend test-macosx-arm64/lit.swift-features.cfg \
  2>&1 | tee "$pack_logs/build-current.log"

cd "$swift_source"
python3 utils/run-test --build skip --build-dir "$pack_build" \
  test/Parse/pack_destructuring.swift \
  test/Constraints/pack_destructuring.swift \
  test/Interpreter/pack_destructuring.swift \
  test/Interpreter/pack_destructuring_regex.swift \
  test/ModuleInterface/pack_destructuring.swift \
  2>&1 | tee "$pack_logs/focused.log"

if grep -q 'Unsupported:' "$pack_logs/focused.log"; then
  printf '%s\n' 'A focused PoC test was skipped; inspect the lit feature configuration.' >&2
  exit 1
fi

python3 utils/run-test --build skip --build-dir "$pack_build" \
  test/Parse/type_parameter_packs.swift \
  test/Parse/type_parameter_packs_executable.swift \
  test/Constraints/pack-expansion-expressions.swift \
  test/Constraints/pack_expansion_types.swift \
  test/Constraints/nested_pack_expansion.swift \
  test/Generics/parameter-pack-requirements.swift \
  test/SILGen/pack_expansion_type.swift \
  test/SILGen/nested_pack_expansion.swift \
  test/SILGen/pack_iteration.swift \
  test/Interpreter/pack_iteration.swift \
  test/Constraints/closure_receiver_parameters.swift \
  2>&1 | tee "$pack_logs/neighbors.log"

python3 utils/run-test --build skip --mode optimize --build-dir "$pack_build" \
  test/Interpreter/pack_destructuring.swift \
  test/Interpreter/pack_destructuring_regex.swift \
  2>&1 | tee "$pack_logs/optimized.log"

if grep -q 'Unsupported:' "$pack_logs/optimized.log"; then
  printf '%s\n' 'An optimized PoC test was skipped.' >&2
  exit 1
fi

/usr/bin/xcrun swift test --package-path "$swift_source/../swift-syntax" \
  -j "${PACK_JOBS:-4}" --parallel --num-workers 2 \
  --filter 'SwiftParserTest.(PackDestructuringTests|PatternTests|MatchingPatternsTests|ClosureReceiverParameterTests)' \
  2>&1 | tee "$pack_logs/swift-parser-combined.log"

/usr/bin/xcrun swift test --package-path "$swift_source/../swift-syntax/CodeGeneration" \
  -j "${PACK_JOBS:-4}" --parallel --num-workers 2 --filter ValidateSyntaxNodes \
  2>&1 | tee "$pack_logs/syntax-schema-tests.log"
