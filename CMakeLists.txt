cmake_minimum_required(VERSION 3.22)

#
# This file is generated only once,
# and is not re-generated if converter is called multiple times.
#
# User is free to modify the file as much as necessary
#

# Setup compiler settings
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)


# Define the build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Debug")
endif()

# Set the project name
set(CMAKE_PROJECT_NAME LED_Homework)

# Enable compile command to ease indexing with e.g. clangd
set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

# Core project settings
project(${CMAKE_PROJECT_NAME})
message("Build type: " ${CMAKE_BUILD_TYPE})

# Enable CMake support for ASM and C languages
enable_language(C ASM)

# Create an executable object type
add_executable(${CMAKE_PROJECT_NAME})

# Add STM32CubeMX generated sources
add_subdirectory(cmake/stm32cubemx)

# Link directories setup
target_link_directories(${CMAKE_PROJECT_NAME} PRIVATE
    # Add user defined library search paths
)

# Add sources to executable
target_sources(${CMAKE_PROJECT_NAME} PRIVATE
    # Add user sources here
)

# Add include paths
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
    # Add user defined include paths
)

# Add project symbols (macros)
target_compile_definitions(${CMAKE_PROJECT_NAME} PRIVATE
    # Add user defined symbols
)

# Remove wrong libob.a library dependency when using cpp files
list(REMOVE_ITEM CMAKE_C_IMPLICIT_LINK_LIBRARIES ob)

# Add linked libraries
target_link_libraries(${CMAKE_PROJECT_NAME}
    stm32cubemx

    # Add user defined libraries
)

# ---------------------------------------------------------------------------
# 自动烧录: 固件链接完成后立刻烧录到开发板
# 这样只要 CLion 编译了这个工程(按 RUN 或按小锤子都会先编译), 板子就被更新。
#
# 这里故意不带 strict: flash_postbuild.cmd 失败也返回 0,
# 所以板子没插 / SWD 线掉了的时候, 普通编译不会因此报红。
# 想看到烧录失败, 用下面的 flash 目标(它带 strict)。
# ---------------------------------------------------------------------------
add_custom_command(TARGET ${CMAKE_PROJECT_NAME} POST_BUILD
    COMMAND cmd /c "${CMAKE_SOURCE_DIR}/cmake/flash_postbuild.cmd" "$<TARGET_FILE:${CMAKE_PROJECT_NAME}>"
    COMMENT "自动烧录 ${CMAKE_PROJECT_NAME}.elf 到开发板"
    VERBATIM
)

# ---------------------------------------------------------------------------
# 一键烧录目标
# 用法: 在 CLion 的构建目标下拉框里选中 "flash", 然后点 Build
#       (会先编译, 再烧录, 自动校验并复位运行)
# 下载器: ST-LINK V2 (SWD)
#
# 实际烧录交给 cmake/flash.ps1, 策略是:
#   1) 单遍 program <elf> verify reset exit (OpenOCD 逐字节回读校验,
#      通过才算成功), 速度 480 kHz -> 100 kHz 逐级重试;
#   2) 单遍多次失败才降级到"逐页擦除 + 每 256 字节写入"的兜底路径。
#
# 这里带 strict: 烧录失败会以非 0 退出码回到 CLion, 界面上能看见错误,
# 不会被误当成烧录成功。
# ---------------------------------------------------------------------------
add_custom_target(flash
    COMMAND cmd /c "${CMAKE_SOURCE_DIR}/cmake/flash_postbuild.cmd" "$<TARGET_FILE:${CMAKE_PROJECT_NAME}>" strict
    DEPENDS ${CMAKE_PROJECT_NAME}
    COMMENT "烧录 ${CMAKE_PROJECT_NAME}.elf 到 STM32F103 (ST-LINK V2 / SWD)"
    VERBATIM
)
