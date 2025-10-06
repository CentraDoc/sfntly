########################################################################
# CMake build script for Google Typography sfntly.


cmake_minimum_required(VERSION 3.19 FATAL_ERROR)
cmake_policy(VERSION 3.19)

set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING "good configs" FORCE)
set(CMAKE_LEGACY_CYGWIN_WIN32 0)

project(sfntly)

# Set C++ standard to C++17

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# non-Windows flag

set(GCC_OR_CLANG FALSE)
if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  set(GCC_OR_CLANG TRUE)
endif()
if (CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  set(GCC_OR_CLANG TRUE)
endif()

# Set up universal binary for macOS (Intel + Apple Silicon)

if(APPLE)
  # Force universal binary build
  set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "Build architectures for macOS" FORCE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum macOS deployment version")

  # Build both static and shared libraries on macOS
  set(BUILD_SHARED_LIBS OFF)  # We'll explicitly create both types
  message(STATUS "Building universal static and dynamic libraries for architectures: ${CMAKE_OSX_ARCHITECTURES}")
endif()


if(GCC_OR_CLANG)
  # default to release build
  if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
    add_definitions("-DNDEBUG -O2")

    # For gcc, make the default be debug build and valgrind friendly.
    #set(CMAKE_BUILD_TYPE Debug)
    #add_definitions("-DDEBUG -D_DEBUG -g -fno-inline -fno-omit-frame-pointer -fno-builtin")
  endif(NOT CMAKE_BUILD_TYPE)

  # Suppress deprecated function warnings
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-deprecated-declarations")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-deprecated-declarations")

  # Add position independent code for static libraries
  set(CMAKE_POSITION_INDEPENDENT_CODE ON)

endif(GCC_OR_CLANG)

set(LIBRARY_OUTPUT_PATH ${CMAKE_CURRENT_BINARY_DIR}/lib)
set(EXECUTABLE_OUTPUT_PATH ${CMAKE_CURRENT_BINARY_DIR}/bin)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src ext/gtest/include ext/gtest
    ${CMAKE_CURRENT_SOURCE_DIR}/src/sample ${CMAKE_CURRENT_SOURCE_DIR}/src/sample/subtly)

if(MSVC)
    set(ICU_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/ext/icu)
    set(ICU_FOUND TRUE)
    set(ICU_INCLUDE_DIR "${ICU_ROOT}/include")
    if  (CMAKE_SIZEOF_VOID_P EQUAL 8)
      set(ICU_LIBRARY_DIR "${ICU_ROOT}/lib64")
    else()
      set(ICU_LIBRARY_DIR "${ICU_ROOT}/lib")
    endif()
    set(ICU_SHARED_LIBRARIES "${ICU_LIBRARY_DIR}/icuuc.lib")

# Find ICU - with support for universal builds
elseif(APPLE)
  # For universal builds, we need to handle ICU differently
  # Try multiple locations for universal ICU
  set(ICU_POSSIBLE_PATHS
    "${CMAKE_CURRENT_SOURCE_DIR}/ext/icu/source/universal"
    "/usr/local/icu-universal"
    "/usr/local"
    "/opt/homebrew"
    "/usr/local/opt/icu4c"
  )

  set(ICU_FOUND FALSE)
  foreach(ICU_PATH ${ICU_POSSIBLE_PATHS})
    if(EXISTS "${ICU_PATH}/include/unicode/uchar.h")
      set(ICU_INCLUDE_DIR "${ICU_PATH}/include")
      set(ICU_LIBRARY_DIR "${ICU_PATH}/lib")

      # Look for static ICU libraries first
      find_library(ICU_UC_LIBRARY
        NAMES libicuuc.a icuuc
        PATHS ${ICU_LIBRARY_DIR}
        NO_DEFAULT_PATH
      )
      find_library(ICU_DATA_LIBRARY
        NAMES libicudata.a icudata
        PATHS ${ICU_LIBRARY_DIR}
        NO_DEFAULT_PATH
      )
      find_library(ICU_I18N_LIBRARY
        NAMES libicui18n.a icui18n
        PATHS ${ICU_LIBRARY_DIR}
        NO_DEFAULT_PATH
      )

      # Also look for shared libraries for dylib target
      find_library(ICU_UC_SHARED_LIBRARY
        NAMES libicuuc.dylib icuuc
        PATHS ${ICU_LIBRARY_DIR}
        NO_DEFAULT_PATH
      )
      find_library(ICU_DATA_SHARED_LIBRARY
        NAMES libicudata.dylib icudata
        PATHS ${ICU_LIBRARY_DIR}
        NO_DEFAULT_PATH
      )
      find_library(ICU_I18N_SHARED_LIBRARY
        NAMES libicui18n.dylib icui18n
        PATHS ${ICU_LIBRARY_DIR}
        NO_DEFAULT_PATH
      )

      if(ICU_UC_LIBRARY AND ICU_DATA_LIBRARY)
        # For static libraries, check if they support required architectures
        execute_process(
          COMMAND lipo -info ${ICU_UC_LIBRARY}
          OUTPUT_VARIABLE ICU_ARCHS
          ERROR_QUIET
        )

        # Check if it contains both architectures we need
        if(ICU_ARCHS MATCHES "x86_64" AND ICU_ARCHS MATCHES "arm64")
          message(STATUS "Found universal ICU static libraries at: ${ICU_PATH}")
          set(ICU_ROOT ${ICU_PATH})
          set(ICU_FOUND TRUE)
          break()
        elseif(ICU_ARCHS MATCHES "arm64" OR ICU_ARCHS MATCHES "x86_64")
          message(STATUS "Found single-arch ICU at: ${ICU_PATH} (${ICU_ARCHS})")
          set(ICU_ROOT ${ICU_PATH})
          set(ICU_FOUND TRUE)
          # Continue looking for universal version, but use this as fallback
        endif()
      endif()
    endif()
  endforeach()

  if(ICU_FOUND AND ICU_ROOT)
    include_directories(${ICU_INCLUDE_DIR})
    # Use full paths to static libraries for static target
    set(ICU_STATIC_LIBRARIES ${ICU_UC_LIBRARY})
    if(ICU_DATA_LIBRARY)
      list(APPEND ICU_STATIC_LIBRARIES ${ICU_DATA_LIBRARY})
    endif()
    if(ICU_I18N_LIBRARY)
      list(APPEND ICU_STATIC_LIBRARIES ${ICU_I18N_LIBRARY})
    endif()

    # Use shared libraries for shared target if available
    set(ICU_SHARED_LIBRARIES "")
    if(ICU_UC_SHARED_LIBRARY)
      list(APPEND ICU_SHARED_LIBRARIES ${ICU_UC_SHARED_LIBRARY})
    endif()
    if(ICU_DATA_SHARED_LIBRARY)
      list(APPEND ICU_SHARED_LIBRARIES ${ICU_DATA_SHARED_LIBRARY})
    endif()
    if(ICU_I18N_SHARED_LIBRARY)
      list(APPEND ICU_SHARED_LIBRARIES ${ICU_I18N_SHARED_LIBRARY})
    endif()

    # Fallback to static libraries for shared target if no shared libs found
    if(NOT ICU_SHARED_LIBRARIES)
      set(ICU_SHARED_LIBRARIES ${ICU_STATIC_LIBRARIES})
    endif()

    message(STATUS "Using ICU static libraries from: ${ICU_ROOT}")
    message(STATUS "ICU static libraries: ${ICU_STATIC_LIBRARIES}")
    if(ICU_SHARED_LIBRARIES)
      message(STATUS "ICU shared libraries: ${ICU_SHARED_LIBRARIES}")
    endif()
  else()
    message(WARNING "Universal ICU libraries not found. Building without ICU support.")
    message(STATUS "To install universal ICU:")
    message(STATUS "  1. Download ICU source from https://github.com/unicode-org/icu")
    message(STATUS "  2. Build with: ./configure CFLAGS='-arch x86_64 -arch arm64' CXXFLAGS='-arch x86_64 -arch arm64' LDFLAGS='-arch x86_64 -arch arm64' --enable-static --disable-shared")
    message(STATUS "  3. Or use Homebrew: brew install icu4c")
    set(ICU_STATIC_LIBRARIES "")
    set(ICU_SHARED_LIBRARIES "")
  endif()
else()
  # Non-macOS systems
  find_package(PkgConfig QUIET)
  if(PkgConfig_FOUND)
    pkg_check_modules(ICU REQUIRED icu-uc)
    if(ICU_FOUND)
      include_directories(${ICU_INCLUDE_DIRS})
      link_directories(${ICU_LIBRARY_DIRS})
      set(ICU_STATIC_LIBRARIES ${ICU_LIBRARIES})
      set(ICU_SHARED_LIBRARIES ${ICU_LIBRARIES})
    endif()
  endif()
endif()


# The following simulates Chrome compilation flags
add_definitions(-DSFNTLY_NO_EXCEPTION)
if(GCC_OR_CLANG)
  add_definitions(-D__wur=__attribute__\(\(warn_unused_result\)\) -Wall -fno-exceptions)
endif(GCC_OR_CLANG)

# Use STL for TinyXML library
add_definitions(-DTIXML_USE_STL)

# Enable CMap and Bitmap handling
add_definitions(-DSFNTLY_EXPERIMENTAL)

# VC specific flags
if(MSVC)
  set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Zi /nologo /W4 /O2 /Ob2 /Oy /GF /Gm- /MT /GS /Gy /fp:precise /Zc:wchar_t /Zc:forScope /GR-")
  set (CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} /Zi /nologo /W4 /Od /Oy- /RTC1 /MTd /GS /Gy /fp:precise /Zc:wchar_t /Zc:forScope /GR-")
  add_definitions(-D_UNICODE -DUNICODE)
  include_directories(${CMAKE_CURRENT_SOURCE_DIR}/ext/icu/include)
  link_directories(${CMAKE_CURRENT_SOURCE_DIR}/ext/icu/lib)
endif(MSVC)

file(GLOB SFNTLY_CORE_FILES src/sfntly/*.h src/sfntly/*.cc)
file(GLOB SFNTLY_PORT_FILES src/sfntly/port/*.h src/sfntly/port/*.cc)
file(GLOB SFNTLY_DATA_FILES src/sfntly/data/*.h src/sfntly/data/*.cc)
file(GLOB SFNTLY_MATH_FILES src/sfntly/math/*.h src/sfntly/math/*.cc)
file(GLOB SFNTLY_TABLE_COMMON_FILES src/sfntly/table/*.h src/sfntly/table/*.cc)
file(GLOB SFNTLY_TABLE_BITMAP_FILES src/sfntly/table/bitmap/*.h src/sfntly/table/bitmap/*.cc)
file(GLOB SFNTLY_TABLE_CORE_FILES src/sfntly/table/core/*.h src/sfntly/table/core/*.cc)
file(GLOB SFNTLY_TABLE_TTF_FILES src/sfntly/table/truetype/*.h src/sfntly/table/truetype/*.cc)

set(SFNTLY_ALL_FILES
    ${SFNTLY_CORE_FILES}
    ${SFNTLY_PORT_FILES}
    ${SFNTLY_DATA_FILES}
    ${SFNTLY_MATH_FILES}
    ${SFNTLY_TABLE_COMMON_FILES}
    ${SFNTLY_TABLE_BITMAP_FILES}
    ${SFNTLY_TABLE_CORE_FILES}
    ${SFNTLY_TABLE_TTF_FILES})

# are these used for anything?
  source_group(core FILES ${SFNTLY_CORE_FILES})
  source_group(ports FILES ${SFNTLY_PORT_FILES})
  source_group(data FILES ${SFNTLY_DATA_FILES})
  source_group(math FILES ${SFNTLY_MATH_FILES})
  source_group(table FILES ${SFNTLY_TABLE_COMMON_FILES})
  source_group(table\\bitmap FILES ${SFNTLY_TABLE_BITMAP_FILES})
  source_group(table\\core FILES ${SFNTLY_TABLE_CORE_FILES})
  source_group(table\\truetype FILES ${SFNTLY_TABLE_TTF_FILES})

# Build sfntly as a static library
add_library(sfntly_static STATIC ${SFNTLY_ALL_FILES})

# Build sfntly as a shared library (dylib on macOS)
add_library(sfntly_shared SHARED ${SFNTLY_ALL_FILES})

# Set library properties for static library
set_target_properties(sfntly_static PROPERTIES
  VERSION 1.0.0
  OUTPUT_NAME sfntly
  ARCHIVE_OUTPUT_NAME sfntly
  POSITION_INDEPENDENT_CODE ON
)

# Set library properties for shared library
set_target_properties(sfntly_shared PROPERTIES
  VERSION 1.0.0
  SOVERSION 1
  OUTPUT_NAME sfntly
  LIBRARY_OUTPUT_NAME sfntly
  POSITION_INDEPENDENT_CODE ON
)

# macOS specific shared library properties
if(APPLE)
  set_target_properties(sfntly_shared PROPERTIES
    MACOSX_RPATH TRUE
    INSTALL_NAME_DIR "@rpath"
  )
endif()

# Link ICU to static library (only if found)
if(ICU_STATIC_LIBRARIES)
  target_link_libraries(sfntly_static ${ICU_STATIC_LIBRARIES})
  target_compile_definitions(sfntly_static PRIVATE SFNTLY_HAS_ICU=1)
else()
  target_compile_definitions(sfntly_static PRIVATE SFNTLY_HAS_ICU=0)
endif()

# Link ICU to shared library (only if found)
if(ICU_SHARED_LIBRARIES)
  target_link_libraries(sfntly_shared ${ICU_SHARED_LIBRARIES})
  target_compile_definitions(sfntly_shared PRIVATE SFNTLY_HAS_ICU=1)
else()
  target_compile_definitions(sfntly_shared PRIVATE SFNTLY_HAS_ICU=0)
endif()

# Create alias for backward compatibility
add_library(sfntly ALIAS sfntly_static)

# Optional: Build executables (comment out if you only want the library)
if(BUILD_EXECUTABLES)
  file(GLOB_RECURSE SIMPLE_SUBSETTER src/sample/subsetter/*.h src/sample/subsetter/*.cc
                                     src/sfntly/tools/*.h src/sfntly/tools/*.cc)
  add_executable(subsetter ${SIMPLE_SUBSETTER})
  target_link_libraries(subsetter sfntly_static)
  if(ICU_STATIC_LIBRARIES)
    target_link_libraries(subsetter ${ICU_STATIC_LIBRARIES})
  endif()
  if(GCC_OR_CLANG)
    target_link_libraries(subsetter pthread)
  endif(GCC_OR_CLANG)

  # subtly targets
  file(GLOB SUBTLY_FILES src/sample/subtly/*.h src/sample/subtly/*.cc)
  file(GLOB SUBTLY_MAINS src/sample/subtly/*main.cc)
  list(REMOVE_ITEM SUBTLY_FILES ${SUBTLY_MAINS})
  add_library(subtly STATIC ${SUBTLY_FILES})

  add_executable(subtly_subsetter src/sample/subtly/subsetter_main.cc)
  target_link_libraries(subtly_subsetter subtly sfntly_static)
  if(ICU_STATIC_LIBRARIES)
    target_link_libraries(subtly_subsetter ${ICU_STATIC_LIBRARIES})
  endif()
  if(GCC_OR_CLANG)
    target_link_libraries(subtly_subsetter pthread)
  endif(GCC_OR_CLANG)

  add_executable(subtly_merger src/sample/subtly/merger_main.cc)
  target_link_libraries(subtly_merger subtly sfntly_static)
  if(ICU_STATIC_LIBRARIES)
    target_link_libraries(subtly_merger ${ICU_STATIC_LIBRARIES})
  endif()
  if(GCC_OR_CLANG)
    target_link_libraries(subtly_merger pthread)
  endif(GCC_OR_CLANG)

  add_executable(subtly_debug src/sample/subtly/debug_main.cc)
  target_link_libraries(subtly_debug subtly sfntly_static)
  if(ICU_STATIC_LIBRARIES)
    target_link_libraries(subtly_debug ${ICU_STATIC_LIBRARIES})
  endif()
  if(GCC_OR_CLANG)
    target_link_libraries(subtly_debug pthread)
  endif(GCC_OR_CLANG)
endif()

# Installation rules
install(TARGETS sfntly_static sfntly_shared
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
)

# Install headers
install(DIRECTORY src/sfntly/
  DESTINATION include/sfntly
  FILES_MATCHING PATTERN "*.h"
)

# Print build information
message(STATUS "Build configuration:")
message(STATUS "  CMake version: ${CMAKE_VERSION}")
message(STATUS "  System: ${CMAKE_SYSTEM}")
message(STATUS "  Processor: ${CMAKE_SYSTEM_PROCESSOR}")
if(APPLE)
  message(STATUS "  Target architectures: ${CMAKE_OSX_ARCHITECTURES}")
  message(STATUS "  Deployment target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()
message(STATUS "  Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  Library types: STATIC + SHARED")
if(ICU_STATIC_LIBRARIES OR ICU_SHARED_LIBRARIES)
  if(ICU_STATIC_LIBRARIES)
    message(STATUS "  ICU static libraries: ${ICU_STATIC_LIBRARIES}")
  endif()
  if(ICU_SHARED_LIBRARIES)
    message(STATUS "  ICU shared libraries: ${ICU_SHARED_LIBRARIES}")
  endif()
else()
  message(STATUS "  ICU libraries: NOT FOUND (building without ICU support)")
endif()