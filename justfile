#!/usr/bin/env -S just --justfile
# just reference  : https://just.systems/man/en/

set dotenv-load := true

alias b := build
alias r := run
alias c := check

@default:
    just --list

build:
    zig build -fincremental

run:
    zig build -fincremental run

profile:
    pidof tracy-profiler || tracy -a localhost &
    zig build -fincremental -Dprofile run

nproc := `nproc --all`
check:
    zig build -fincremental --prominent-compile-errors  \
        -j`expr {{nproc}} - 1` check --watch
