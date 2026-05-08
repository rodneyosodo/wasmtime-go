#!/bin/bash

copy_c_api_headers() {
  local wasmtime_dir=$1 build_dir=$2
  cp "$wasmtime_dir"/crates/c-api/include/*.h build/include
  cp -r "$wasmtime_dir"/crates/c-api/include/wasmtime build/include
  local conf
  conf=$(find "$build_dir"/build/wasmtime-c-api-impl-*/out/include/wasmtime/conf.h 2>/dev/null | head -1)
  if [ -n "$conf" ]; then
    cp "$conf" build/include/wasmtime/conf.h
  fi
}

wasmtime=$1
if [ "$wasmtime" = "" ]; then
  echo "usage: $0 <path-to-wasmtime> [target]"
  echo "  target: native (default), riscv64"
  exit 1
fi

target=${2:-native}

if [ "$target" = "riscv64" ]; then
  # Add riscv64 to existing build directory (does not remove other platforms)
  mkdir -p "build/linux-riscv64" "build/include" "build/include/wasmtime"
  echo "package linux_riscv64" > "build/linux-riscv64/empty.go"

  rust_target="riscv64gc-unknown-linux-gnu"

  if command -v rustup &>/dev/null && ! rustup target list --installed 2>/dev/null | grep -q "$rust_target"; then
    echo "Installing Rust target $rust_target ..."
    rustup target add "$rust_target"
  fi

  build="$wasmtime/target/$rust_target/release"
  if [ ! -d "$build" ]; then
    build="$wasmtime/target/$rust_target/debug"
  fi

  if [ ! -f "$build/libwasmtime.a" ]; then
    echo "Building wasmtime-c-api for $rust_target ..."
    CC_riscv64gc_unknown_linux_gnu="zig cc -target riscv64-linux-gnu" \
      cargo build --release --target "$rust_target" \
        -p wasmtime-c-api --manifest-path "$wasmtime/crates/c-api/artifact/Cargo.toml"
    build="$wasmtime/target/$rust_target/release"
  fi

  cp "$build/libwasmtime.a" "build/linux-riscv64/libwasmtime.a"

  copy_c_api_headers "$wasmtime" "$build"

  echo "riscv64 build ready. Cross-compile with:"
  echo "  GOOS=linux GOARCH=riscv64 CGO_ENABLED=1 CC=\"zig cc -target riscv64-linux-gnu\" go build -ldflags \"-s -w\" ./main.go"
  exit 0
fi

# Clean and re-create "build" directory hierarchy
rm -rf build
for d in "include" "include/wasmtime" "include/wasmtime/component" "include/wasmtime/component/types" "include/wasmtime/types" "linux-x86_64" "macos-x86_64" "windows-x86_64" "linux-aarch64" "macos-aarch64"; do
  path="build/$d"
  mkdir -p "$path"
  name=$(basename $d | tr - _)
  echo "package $name" > "$path/empty.go"
done

build="$wasmtime/target/release"
if [ ! -d "$build" ]; then
  build="$wasmtime/target/debug"
fi
build=$(cd "$build" && pwd)

if [ ! -f "$build/libwasmtime.a" ]; then
  echo 'Missing libwasmtime.a. Build with:'
  echo '  cargo build --release -p wasmtime-c-api --manifest-path crates/c-api/artifact/Cargo.toml'
  exit 1
fi

for d in "linux-x86_64" "macos-x86_64" "linux-aarch64" "macos-aarch64"; do
  ln -s "$build/libwasmtime.a" "build/$d/libwasmtime.a"
done

copy_c_api_headers "$wasmtime" "$build"
