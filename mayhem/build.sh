#!/usr/bin/env bash
#
# mayhem/build.sh — build hoextdown's fuzz harness, its standalone reproducer, and the
# `hoedown` binary the functional test suite (test/runner.py) drives.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/mayhemheroes/base) already exports the build contract: CC, CXX, LIB_FUZZING_ENGINE,
# SANITIZER_FLAGS (ASan+UBSan halting), DEBUG_FLAGS (-g -gdwarf-3), STANDALONE_FUZZ_MAIN, SRC.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# SANITIZER_FLAGS uses `=` (no colon) on purpose — an explicit EMPTY value
# (--build-arg SANITIZER_FLAGS=) is honored and builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# Two benign, ubiquitous UBSan checks flood on ~every input and would abort the fuzzer before it
# explores, so relax ONLY these (ASan + the rest of UBSan stay on and halting):
#   * pointer-overflow / nonnull-attribute: hoedown_buf_put (src/buffer.c:127) does
#     memcpy(buf->data + size, data, 0) with NULL pointers on every empty buffer.
#   * function: hoedown's renderer is a vtable of callbacks invoked through generic pointer types
#     (src/document.c calls rndr_* through mismatched fn-pointer types) — fires on any list/inline.
if [ -n "$SANITIZER_FLAGS" ]; then SANITIZER_FLAGS="$SANITIZER_FLAGS -fno-sanitize=pointer-overflow,nonnull-attribute,function"; fi
# Coverage feedback for libFuzzer: instrument the LIBRARY (not just the harness) with sancov.
# The sancov callbacks are provided by the sanitizer runtime, so gate on SANITIZER_FLAGS being
# non-empty (the no-sanitizer build stays uninstrumented and links cleanly).
if [ -n "$SANITIZER_FLAGS" ]; then SANITIZER_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link"; fi
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# src/html_blocks.c / src/html5_blocks.c are committed gperf outputs; make sure make never
# tries to regenerate them (gperf is not installed) if checkout timestamps race.
touch src/html_blocks.c src/html5_blocks.c

BASE_CFLAGS="-O1 -std=c99 -D_DEFAULT_SOURCE -Wall -Wextra -Wno-unused-parameter -fPIC"

# 1) Sanitized+DWARF-3 build of the library itself, so the fuzzed code is instrumented.
make clean
make -j"$MAYHEM_JOBS" CC="$CC" CFLAGS="$BASE_CFLAGS $SANITIZER_FLAGS $DEBUG_FLAGS" libhoedown.a

# 2) The harness (upstream test/hoedown_fuzzer.c): fuzzer binary + standalone run-once reproducer.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -std=c99 -Isrc -c test/hoedown_fuzzer.c -o /tmp/hoedown_fuzzer.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE /tmp/hoedown_fuzzer.o libhoedown.a \
    -o /mayhem/hoedown_fuzzer
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS /tmp/hoedown_fuzzer.o /tmp/standalone_main.o libhoedown.a \
    -o /mayhem/hoedown_fuzzer-standalone

# 3) Test-suite build with the project's NORMAL flags (clean, independent build): test/runner.py
#    drives the ./hoedown CLI against golden HTML outputs. COVERAGE_FLAGS (empty by default)
#    instruments only this oracle build.
make clean
make -j"$MAYHEM_JOBS" \
    CFLAGS="-g -O3 -std=c99 -D_DEFAULT_SOURCE -pedantic -Wall -Wextra -Wno-unused-parameter $COVERAGE_FLAGS" \
    hoedown
