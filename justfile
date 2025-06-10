#!/usr/bin/env -S just --justfile
# just reference  : https://just.systems/man/en/

set dotenv-load := true

@default:
    just --list

alias b := build
alias r := run
alias c := check

build:
    zig build -Duse_llvm=true

run:
    zig build -Duse_llvm=true run

profile:
    pidof tracy-profiler || tracy -a localhost &
    zig build -fincremental -Dprofile run

nproc := `nproc --all`
check:
    zig build -fincremental --prominent-compile-errors  \
        -j`expr {{nproc}} - 1` check --watch
