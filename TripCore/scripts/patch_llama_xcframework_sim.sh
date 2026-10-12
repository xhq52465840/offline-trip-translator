#!/usr/bin/env bash
# 给 SPM 解压出的 llama.xcframework 补上 iOS 模拟器切片。
# 官方 b11541 zip 只有 ios-arm64（真机）和 macos-arm64_x86_64。
# 用法：patch_llama_xcframework_sim.sh <DerivedData 目录>
# 依赖：LLAMA_CPP 指向已检出 tag b11541 的 llama.cpp（默认 ~/trip-work/llama.cpp）。
# 不改 Package.swift 的 checksum，不把二进制写进仓库。
set -euo pipefail

DD="${1:?usage: patch_llama_xcframework_sim.sh <DerivedData path>}"
LLAMA_CPP="${LLAMA_CPP:-$HOME/trip-work/llama.cpp}"
PACK="${LLAMA_SIM_PACK:-$HOME/trip-work/ios-sim-pack}"
FW="$DD/SourcePackages/artifacts/tripcore/llama/llama.xcframework"
DYLIB="$PACK/llama"

if [ ! -d "$LLAMA_CPP/.git" ]; then
  echo "llama.cpp 不在 $LLAMA_CPP" >&2
  exit 1
fi
TAG=$(git -C "$LLAMA_CPP" describe --tags --exact-match 2>/dev/null || true)
if [ "$TAG" != "b11541" ]; then
  echo "需要 llama.cpp tag b11541，当前是 '${TAG:-未知}'（$LLAMA_CPP）" >&2
  exit 1
fi
if [ ! -d "$FW/ios-arm64/llama.framework" ]; then
  echo "还没有解压出的 xcframework：$FW" >&2
  echo "先用这个 DerivedData 跑一次 xcodebuild -resolvePackageDependencies。" >&2
  exit 1
fi

mkdir -p "$PACK"
need_build=1
# vtool -show-build 只打印 platform/minos/sdk，不打印 architecture。
# 单架构库要用 lipo -info（输出含 "architecture: arm64"）。
if [ -f "$DYLIB" ] && vtool -show-build "$DYLIB" 2>/dev/null | grep -q 'platform IOSSIMULATOR'; then
  if lipo -info "$DYLIB" 2>/dev/null | grep -q 'arm64'; then
    need_build=0
    echo "复用已编好的模拟器库 $DYLIB"
  fi
fi

if [ "$need_build" = 1 ]; then
  echo "编译 llama.cpp b11541 iphonesimulator arm64"
  cmake -B "$LLAMA_CPP/build-ios-sim" -G Xcode \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" \
    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    -DCMAKE_XCODE_ATTRIBUTE_COPY_PHASE_STRIP=NO \
    -DCMAKE_XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT=NO \
    -DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM=ggml \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_APP=OFF \
    -DLLAMA_BUILD_COMMON=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_BUILD_MTMD=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_BLAS_DEFAULT=ON \
    -DGGML_METAL=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 \
    -DIOS=ON \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DGGML_METAL_TARGET_OS=ios \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator \
    -DCMAKE_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g" \
    -DCMAKE_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g" \
    -DLLAMA_OPENSSL=OFF \
    -DMTMD_VIDEO=OFF \
    -S "$LLAMA_CPP"
  cmake --build "$LLAMA_CPP/build-ios-sim" --config Release -j 4
  B="$LLAMA_CPP/build-ios-sim"
  REL=Release-iphonesimulator
  TMP="$PACK/obj"
  rm -rf "$TMP"
  mkdir -p "$TMP"
  xcrun libtool -static -o "$TMP/combined.a" \
    "$B/src/$REL/libllama.a" \
    "$B/ggml/src/$REL/libggml.a" \
    "$B/ggml/src/$REL/libggml-base.a" \
    "$B/ggml/src/$REL/libggml-cpu.a" \
    "$B/ggml/src/ggml-metal/$REL/libggml-metal.a" \
    "$B/ggml/src/ggml-blas/$REL/libggml-blas.a" \
    "$B/tools/mtmd/$REL/libmtmd.a" \
    "$B/vendor/hash/$REL/libvendor-hash.a"
  SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
  xcrun -sdk iphonesimulator clang++ -dynamiclib \
    -isysroot "$SDK" -arch arm64 -mios-simulator-version-min=16.4 \
    -Wl,-force_load,"$TMP/combined.a" \
    -framework Foundation -framework Metal -framework Accelerate \
    -install_name "@rpath/llama.framework/llama" \
    -o "$DYLIB"
fi

codesign --force --sign - "$DYLIB"
vtool -show-build "$DYLIB" | head -12

python3 - "$FW" "$DYLIB" << 'PY'
import os, shutil, plistlib, sys
fw, dylib = sys.argv[1], sys.argv[2]
dest = os.path.join(fw, "ios-arm64-simulator")
if os.path.exists(dest):
    shutil.rmtree(dest)
os.makedirs(dest)
shutil.copytree(os.path.join(fw, "ios-arm64", "llama.framework"), os.path.join(dest, "llama.framework"))
target = os.path.join(dest, "llama.framework", "llama")
shutil.copy2(dylib, target)
os.chmod(target, 0o755)
plist_path = os.path.join(fw, "Info.plist")
with open(plist_path, "rb") as f:
    pl = plistlib.load(f)
libs = [x for x in pl["AvailableLibraries"] if x.get("LibraryIdentifier") != "ios-arm64-simulator"]
libs.append({
    "BinaryPath": "llama.framework/llama",
    "LibraryIdentifier": "ios-arm64-simulator",
    "LibraryPath": "llama.framework",
    "SupportedArchitectures": ["arm64"],
    "SupportedPlatform": "ios",
    "SupportedPlatformVariant": "simulator",
})
pl["AvailableLibraries"] = libs
with open(plist_path, "wb") as f:
    plistlib.dump(pl, f)
print("patched", fw)
PY
