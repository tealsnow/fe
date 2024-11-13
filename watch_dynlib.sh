#!/usr/bin/env bash

# TODO: Make this a zig build action
watchexec -r -w src/dynlib/ -e zig "zig build dynlib"
