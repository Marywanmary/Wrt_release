#!/usr/bin/env bash
# 指定使用 bash 解释器执行此脚本

set -e
# 设置脚本在遇到任何错误时立即退出，防止继续执行错误操作

BASE_PATH=$(cd $(dirname $0) && pwd)
# 获取脚本所在目录的绝对路径，并保存到变量 BASE_PATH 中
# 这样无论脚本在哪里运行，都能正确找到其他文件

Dev=$1
# 从命令行获取第一个参数（设备名称），保存到变量 Dev 中
# 例如：./build.sh x86_64 这里的 $1 就是 "x86_64"

Build_Mod=$2
# 从命令行获取第二个参数（构建模式），保存到变量 Build_Mod 中
# 例如：./build.sh x86_64 debug 这里的 $2 就是 "debug"

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
# 拼接配置文件路径：脚本目录/deconfig/设备名.config
# 例如：/home/user/project/deconfig/x86_64.config

INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"
# 拼接INI配置文件路径：脚本目录/compilecfg/设备名.ini
# 例如：/home/user/project/compilecfg/x86_64.ini

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi
# 检查设备配置文件是否存在，如果不存在：
# 1. 打印错误信息（显示缺失的文件路径）
# 2. 立即终止脚本（exit 1 表示错误退出）

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi
# 检查INI配置文件是否存在，如果不存在：
# 1. 打印错误信息（显示缺失的文件路径）
# 2. 立即终止脚本

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}
# 定义一个函数 read_ini_by_key，用于从INI文件中读取配置值
# 工作原理：
# 1. 接收一个参数 key（要查找的配置项名称）
# 2. 使用 awk 工具按行解析INI文件：
#    - -F"=" 表示用等号分隔每行
#    - 找到第一列等于 key 的行，并打印第二列（即配置值）
# 例如：INI文件中有 REPO_URL=https://github.com/openwrt/openwrt
# 调用 read_ini_by_key "REPO_URL" 会返回 "https://github.com/openwrt/openwrt"

remove_uhttpd_dependency() {
    local config_path="$BASE_PATH/$BUILD_DIR/.config"
    local luci_makefile_path="$BASE_PATH/$BUILD_DIR/feeds/luci/collections/luci/Makefile"

    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled."
        fi
    fi
}
# 定义函数 remove_uhttpd_dependency，用于移除 uhttpd 依赖
# 工作逻辑：
# 1. 检查构建配置中是否启用了 luci-app-quickfile 插件（该插件使用 nginx 服务器）
# 2. 如果启用：
#    a. 检查 LuCI（Web界面）的 Makefile 文件是否存在
#    b. 存在则删除其中包含 "luci-light" 的行（即移除 uhttpd 依赖）
#    c. 打印提示信息说明已移除依赖
# 目的：避免同时安装两个Web服务器（uhttpd 和 nginx）造成冲突

REPO_URL=$(read_ini_by_key "REPO_URL")
# 从INI文件读取代码仓库地址，保存到 REPO_URL
# 例如：https://github.com/openwrt/openwrt

REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
# 从INI文件读取代码仓库分支，保存到 REPO_BRANCH
# 例如：v23.05

REPO_BRANCH=${REPO_BRANCH:-main}
# 如果 REPO_BRANCH 为空，则默认使用 "main" 分支
# 这是保险措施，确保始终有有效的分支名

BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
# 从INI文件读取构建目录名，保存到 BUILD_DIR
# 例如：openwrt-build

COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
# 从INI文件读取代码提交哈希值，保存到 COMMIT_HASH
# 例如：a1b2c3d

COMMIT_HASH=${COMMIT_HASH:-none}
# 如果 COMMIT_HASH 为空，则设为 "none"
# 表示不指定特定提交，使用分支最新代码

if [[ -d $BASE_PATH/action_build ]]; then
    BUILD_DIR="action_build"
fi
# 检查是否存在 action_build 目录，如果存在：
# 强制使用 "action_build" 作为构建目录
# 这可能是为特殊构建场景准备的覆盖逻辑

$BASE_PATH/update.sh "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH/$BUILD_DIR" "$COMMIT_HASH"
# 执行 update.sh 脚本，传入参数：
# 1. 代码仓库地址
# 2. 分支名称
# 3. 构建目录完整路径
# 4. 提交哈希值（或"none"）
# 此脚本负责下载/更新OpenWrt源码

\cp -f "$CONFIG_FILE" "$BASE_PATH/$BUILD_DIR/.config"
# 强制复制设备配置文件到构建目录，命名为 .config
# \cp 避免别名覆盖，-f 表示强制覆盖已有文件
# .config 是OpenWrt的构建配置文件

remove_uhttpd_dependency
# 调用前面定义的函数，处理 uhttpd 依赖移除逻辑

cd "$BASE_PATH/$BUILD_DIR"
# 进入构建目录，后续操作都在此目录下执行

make defconfig
# 执行OpenWrt的配置初始化：
# 根据 .config 文件生成完整的构建配置
# 类似于"应用默认配置"的操作

if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    DISTFEEDS_PATH="$BASE_PATH/$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
    fi
fi
# 特殊处理x86_64架构设备：
# 1. 检查设备配置是否为x86_64架构
# 2. 如果是：
#    a. 定位软件源配置文件（99-distfeeds.conf）
#    b. 将文件中的 "aarch64_cortex-a53" 替换为 "x86_64"
# 目的：修正x86_64设备的软件源架构标识，避免安装错误架构的软件包

if [[ $Build_Mod == "debug" ]]; then
    exit 0
fi
# 检查构建模式是否为 "debug"：
# 如果是调试模式，则立即退出脚本（不执行编译）
# 这样用户可以只检查配置是否正确，不实际编译固件

TARGET_DIR="$BASE_PATH/$BUILD_DIR/bin/targets"
# 设置目标固件输出目录路径
# OpenWrt编译后的固件会存放在此目录

if [[ -d $TARGET_DIR ]]; then
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec rm -f {} +
fi
# 清理旧的编译产物：
# 1. 检查目标目录是否存在
# 2. 存在则删除所有以下类型的文件：
#    - *.bin（固件文件）
#    - *.manifest（组件清单）
#    - *efi.img.gz（EFI启动镜像）
#    - *.itb（设备树镜像）
#    - *.fip（固件镜像包）
#    - *.ubi（UBI文件系统镜像）
#    - *rootfs.tar.gz（根文件系统压缩包）
# 目的：避免旧文件干扰新编译结果

make download -j$(($(nproc) * 2))
# 下载编译所需的软件包：
# -j$(($(nproc) * 2)) 表示使用 CPU 核心数 × 2 的并行任务数
# 例如：4核CPU会使用8个并行任务加速下载

make -j$(($(nproc) + 1)) || make -j1 V=s
# 执行编译：
# 1. 首次尝试：使用 (CPU核心数 + 1) 的并行任务数编译
# 2. 如果失败（||），则使用单任务（-j1）并开启详细日志（V=s）重新编译
# 这是为了在并行编译出错时，能用单任务模式获取更详细的错误信息

FIRMWARE_DIR="$BASE_PATH/firmware"
# 设置最终固件输出目录路径

\rm -rf "$FIRMWARE_DIR"
# 强制删除整个固件目录（包括旧固件）
# \rm 避免别名覆盖，-rf 表示递归强制删除

mkdir -p "$FIRMWARE_DIR"
# 创建新的固件目录
# -p 表示自动创建父目录（如果不存在）

find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec cp -f {} "$FIRMWARE_DIR/" \;
# 从编译输出目录复制所有固件相关文件到最终固件目录：
# 复制文件类型与之前清理的相同（固件、清单、镜像等）
# -f 表示强制覆盖（虽然目录刚创建，但保持一致性）

\rm -f "$BASE_PATH/firmware/Packages.manifest" 2>/dev/null
# 删除固件目录中的 Packages.manifest 文件（如果存在）
# 2>/dev/null 表示忽略错误（文件不存在时不报错）
# 此文件可能是中间产物，不需要保留给用户

if [[ -d $BASE_PATH/action_build ]]; then
    make clean
fi
# 如果存在 action_build 目录：
# 执行 make clean 清理编译环境
# 释放磁盘空间（因为临时构建目录可能很大）