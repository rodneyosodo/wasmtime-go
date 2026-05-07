#!/bin/bash

wasmtime=$1
if [ "$wasmtime" = "" ]; then
  echo "usage: $0 <path-to-wasmtime> [target]"
  echo "  target: native (default), riscv64"
  exit 1
fi

target=${2:-native}

# Clean and re-create "build" directory hierarchy
rm -rf build
for d in "include" "include/wasmtime" "include/wasmtime/component" "include/wasmtime/component/types" "include/wasmtime/types" "linux-x86_64" "macos-x86_64" "windows-x86_64" "linux-aarch64" "macos-aarch64"; do
  path="build/$d"
  mkdir -p "$path"
  name=$(basename $d | tr - _)
  echo "package $name" > "$path/empty.go"
done

if [ "$target" = "riscv64" ]; then
  rust_target="riscv64gc-unknown-linux-gnu"
  subdir="$rust_target"

  if ! rustup target list --installed | grep -q "$rust_target"; then
    echo "Installing Rust target $rust_target ..."
    rustup target add "$rust_target"
  fi

  mkdir -p "build/linux-riscv64"
  echo "package linux_riscv64" > "build/linux-riscv64/empty.go"

  build="$wasmtime/target/$subdir/release"
  if [ ! -d "$build" ]; then
    build="$wasmtime/target/$subdir/debug"
  fi

  if [ ! -f "$build/libwasmtime.a" ]; then
    echo "Building wasmtime-c-api for $rust_target ..."
    CC_riscv64gc_unknown_linux_gnu="zig cc -target riscv64-linux-gnu" \
      cargo build --release --target "$rust_target" \
        -p wasmtime-c-api --manifest-path "$wasmtime/crates/c-api/artifact/Cargo.toml"
    build="$wasmtime/target/$subdir/release"
  fi

  build=$(cd "$build" && pwd)
  ln -s "$build/libwasmtime.a" "build/linux-riscv64/libwasmtime.a"

  # Copy headers
  cp "$wasmtime"/crates/c-api/include/*.h build/include
  cp -r "$wasmtime"/crates/c-api/include/wasmtime build/include

  conf=$(find "$build"/build/wasmtime-c-api-impl-*/out/include/wasmtime/conf.h 2>/dev/null | head -1)
  if [ -n "$conf" ]; then
    cp "$conf" build/include/wasmtime/conf.h
  fi

  echo "riscv64 build ready. Cross-compile with:"
  echo "  GOOS=linux GOARCH=riscv64 CGO_ENABLED=1 CC=\"zig cc -target riscv64-linux-gnu\" go build -ldflags \"-s -w\" ./main.go"
else
  build="$wasmtime/target/release"
  if [ ! -d "$build" ]; then
    build="$wasmtime/target/debug"
  fi
  build=$(cd "$build" && pwd)

  if [ ! -f "$build/libwasmtime.a" ]; then
    echo 'Missing libwasmtime.a. Build with:'
    echo '  cargo build --release -p wasmtime-c-api --manifest-path crates/c-api/artifact/Cargo.toml'
  fi

  for d in "linux-x86_64" "macos-x86_64" "linux-aarch64" "macos-aarch64"; do
    ln -s "$build/libwasmtime.a" "build/$d/libwasmtime.a"
  done

  cp "$wasmtime"/crates/c-api/include/*.h build/include
  cp -r "$wasmtime"/crates/c-api/include/wasmtime build/include

  conf=$(find "$build"/build/wasmtime-c-api-impl-*/out/include/wasmtime/conf.h 2>/dev/null | head -1)
  if [ -n "$conf" ]; then
    cp "$conf" build/include/wasmtime/conf.h
  fi
fi
