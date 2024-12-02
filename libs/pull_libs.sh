#!/usr/bin/env bash

pushd ../

git subtree pull --prefix libs/datetime-zig https://github.com/dylibso/datetime-zig.git main --squash
git subtree pull --prefix libs/zig-tracy https://github.com/cipharius/zig-tracy.git master --squash
git subtree pull --prefix libs/wgpu-native-zig https://github.com/bronter/wgpu-native-zig.git main --squash

popd
