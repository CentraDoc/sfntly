#!/bin/bash

# macos universal build of ICU library

# Set variables
ICU_VERSION="74.2"
BUILD_DIR="$(pwd)/build"
INSTALL_DIR="$(pwd)/universal"
INTEL_DIR="${BUILD_DIR}/intel"
ARM_DIR="${BUILD_DIR}/arm"

# Create directories
mkdir -p "${INTEL_DIR}" "${ARM_DIR}" "${INSTALL_DIR}"

# Build for Intel (x86_64)
echo "Building for Intel x86_64..."
cd "${INTEL_DIR}"
CFLAGS="-arch x86_64" CXXFLAGS="-arch x86_64" LDFLAGS="-arch x86_64 -Wl,-headerpad_max_install_names" \
../../../source/configure \
    --prefix="${INTEL_DIR}/install" \
    --enable-static \
    --enable-shared \
    --disable-samples \
    --disable-tests
make -j$(sysctl -n hw.ncpu)
make install

# Build for Apple Silicon (arm64)
echo "Building for Apple Silicon arm64..."
cd "${ARM_DIR}"
CFLAGS="-arch arm64" CXXFLAGS="-arch arm64" LDFLAGS="-arch arm64 -Wl,-headerpad_max_install_names" \
../../../source/configure \
    --prefix="${ARM_DIR}/install" \
    --enable-static \
    --enable-shared \
    --disable-samples \
    --disable-tests
make -j$(sysctl -n hw.ncpu)
make install

# Create universal binaries
echo "Creating universal binaries..."
cd "${BUILD_DIR}"

# Create universal lib directory
mkdir -p "${INSTALL_DIR}/lib"
mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/include"

# Copy headers (same for both architectures)
cp -r "${INTEL_DIR}/install/include/"* "${INSTALL_DIR}/include/"

# Create universal static libraries
for lib in "${INTEL_DIR}/install/lib/"*.a; do
    lib_name=$(basename "$lib")
    arm_lib="${ARM_DIR}/install/lib/${lib_name}"
    if [ -f "$arm_lib" ]; then
        echo "Creating universal static library: $lib_name"
        lipo -create "$lib" "$arm_lib" -output "${INSTALL_DIR}/lib/$lib_name"
    fi
done

# Create universal dynamic libraries
for lib in "${INTEL_DIR}/install/lib/"*.dylib; do
    lib_name=$(basename "$lib")
    arm_lib="${ARM_DIR}/install/lib/${lib_name}"
    if [ -f "$arm_lib" ]; then
        echo "Creating universal dynamic library: $lib_name"
        lipo -create "$lib" "$arm_lib" -output "${INSTALL_DIR}/lib/$lib_name"

        # Fix install names for the universal library to use @rpath
        install_name_tool -id "@rpath/$lib_name" "${INSTALL_DIR}/lib/$lib_name"

        # Update any dependencies to use @rpath as well
        otool -L "${INSTALL_DIR}/lib/$lib_name" | grep -E "libicu.*\.dylib" | awk '{print $1}' | while read dep; do
            dep_name=$(basename "$dep")
            if [[ "$dep_name" != "$lib_name" ]]; then
                install_name_tool -change "$dep" "@rpath/$dep_name" "${INSTALL_DIR}/lib/$lib_name" 2>/dev/null || true
            fi
        done
    fi
done

# Create universal binaries for tools
for bin in "${INTEL_DIR}/install/bin/"*; do
    bin_name=$(basename "$bin")
    arm_bin="${ARM_DIR}/install/bin/${bin_name}"
    if [ -f "$bin" ] && [ -f "$arm_bin" ] && [ ! -L "$bin" ]; then
        echo "Creating universal binary: $bin_name"
        lipo -create "$bin" "$arm_bin" -output "${INSTALL_DIR}/bin/$bin_name"
        chmod +x "${INSTALL_DIR}/bin/$bin_name"
    fi
done

echo "Universal ICU build complete in: ${INSTALL_DIR}"
echo "Libraries have been configured with @rpath for easy embedding"