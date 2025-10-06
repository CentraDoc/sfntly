cmake -G Xcode -S . -B build "-DCMAKE_OSX_ARCHITECTURES=arm64,x86_64"
cmake --build build
