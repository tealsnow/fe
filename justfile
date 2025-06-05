#!/usr/bin/env -S just --justfile
# just reference  : https://just.systems/man/en/

set dotenv-load := true

@default:
    just --list

nproc := `nproc --all`

check:
    zig build --prominent-compile-errors -fincremental \
        -j`expr {{nproc}} - 1` check --watch
