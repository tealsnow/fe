#!/usr/bin/env -S just --justfile
# just reference  : https://just.systems/man/en/

set dotenv-load := true

@default:
    just --list

alias b := build
alias r := run
alias c := check

build:
    zig build

run:
    zig build run

profile:
    pidof tracy-profiler || tracy -a localhost &
    zig build -Dprofile=true run

debug: build
    gf2 ./zig-out/bin/fe

nproc := `nproc --all`
check:
    zig build --prominent-compile-errors -fincremental \
        -j`expr {{nproc}} - 1` -Dno_bin=true -Duse_llvm=false --watch
