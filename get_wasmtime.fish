#!/usr/bin/env fish

set --local WASMTIME_URL (zig build wasmtime)

mkdir -p wasmtime
pushd wasmtime

wget --no-clobber $WASMTIME_URL
tar -xf *.tar.xz

set --local DIR_NAME (basename *.tar.xz .tar.xz)
mv $DIR_NAME wasmtime
