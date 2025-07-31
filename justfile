#!/usr/bin/env -S just --justfile
# just reference  : https://just.systems/man/en/


set dotenv-load := true


@default:
    just --list


[working-directory("app")]
dev:
    just generate_asset_types &
    bun run dev
    killall entr


[working-directory("scripts/generate_asset_types")]
generate_asset_types:
    find . -type f | entr bun run generate
