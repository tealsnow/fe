#!/usr/bin/env bash

git subtree add --prefix libs/datetime https://github.com/dylibso/datetime-zig.git main --squash
git subtree add --prefix libs/tracy https://github.com/cipharius/zig-tracy.git master --squash
