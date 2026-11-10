cmake_minimum_required(VERSION 3.14)
project(windows_mp4_check LANGUAGES CXX)

# Builds the app's own Media Foundation writer (windows/runner/mp4_writer.cpp)
# into a console program that writes a clip and reads it back — the check for
# Windows video export that needs neither the app nor Flutter. See main.cpp.
set(CMAKE_CXX_STANDARD 17)
add_executable(windows_mp4_check
  main.cpp
  "${CMAKE_CURRENT_SOURCE_DIR}/../../windows/runner/mp4_writer.cpp"
)
target_include_directories(windows_mp4_check PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../../windows/runner")
target_compile_definitions(windows_mp4_check PRIVATE NOMINMAX UNICODE _UNICODE)
target_link_libraries(windows_mp4_check PRIVATE
  mfplat mfreadwrite mfuuid ole32)
