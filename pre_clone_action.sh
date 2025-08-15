#!/usr/bin/env bash
# 告诉电脑使用 bash 程序来执行这个脚本（就像用特定播放器打开视频文件）

set -e
# 设置"安全模式"：任何步骤出错就立即停止（就像烹饪时发现食材坏了就立刻停止做菜）

BASE_PATH=$(cd $(dirname $0) && pwd)
# 获取脚本所在位置的完整路径（就像记住自己站在哪个房间）
# 这样无论在哪里运行脚本，都能找到其他需要的文件

Dev=$1
# 获取第一个输入参数（设备型号），比如"x86_64"或"小米路由器"
# 就像在点餐时告诉服务员你要什么菜

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
# 拼接出设备配置文件的完整路径
# 例如：/home/user/project/deconfig/x86_64.config
# 就像找到特定菜品的食谱文件

INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"
# 拼接出设备参数文件的完整路径
# 例如：/home/user/project/compilecfg/x86_64.ini
# 就像找到烹饪这道菜需要的特殊工具清单

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi
# 检查设备配置文件是否存在：
# 如果不存在 → 显示错误信息（告诉用户具体缺哪个文件）
# 然后立即停止运行（就像发现没带菜谱就不做饭了）

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi
# 检查设备参数文件是否存在：
# 如果不存在 → 显示错误信息（告诉用户具体缺哪个文件）
# 然后立即停止运行（就像发现没带工具就不开工了）

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}
# 定义一个"文件阅读助手"函数：
# 输入：要查找的参数名称（比如"仓库地址"）
# 输出：对应的参数值（比如"https://github.com/..."）
# 就像在工具清单里查找"螺丝刀"对应的品牌型号

REPO_URL=$(read_ini_by_key "REPO_URL")
# 从参数文件中读取"仓库地址"（存储源代码的地方）
# 就像查到食材供应商的地址

REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
# 从参数文件中读取"分支名称"（源代码的版本）
# 就像查到要买哪个批次的食材（比如"2023年秋季版"）

REPO_BRANCH=${REPO_BRANCH:-main}
# 如果没指定分支名称，就默认使用"main"分支
# 就像如果没说买哪批，就买最新批次的食材

BUILD_DIR="$BASE_PATH/action_build"
# 设置构建目录名称（存放源代码的文件夹）
# 就像指定一个"备料间"来存放买回来的食材

echo $REPO_URL $REPO_BRANCH
# 在屏幕上显示仓库地址和分支名称
# 就像把供应商地址和食材批次写出来给厨师确认

echo "$REPO_URL/$REPO_BRANCH" >"$BASE_PATH/repo_flag"
# 把仓库地址和分支名称合并后写入一个标记文件
# 就像在备料间门口贴张便条："食材来自XX供应商，XX批次"

git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR
# 执行代码下载操作：
# --depth 1：只下载最新版本（不下载历史记录，节省时间）
# -b $REPO_BRANCH：指定下载的版本分支
# $REPO_URL：从哪个地址下载
# $BUILD_DIR：下载到哪个文件夹
# 就像让快递员只送最新批次的食材到备料间

PROJECT_MIRRORS_FILE="$BUILD_DIR/scripts/projectsmirrors.json"
# 设置镜像源文件的路径（这个文件记录了备用下载地址）

if [ -f "$PROJECT_MIRRORS_FILE" ]; then
    sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi
# 如果镜像源文件存在：
# 删除所有包含".cn/"、"tencent"、"aliyun"的行
# 就像从供应商清单中划掉所有国内供应商
# （因为GitHub Action在国外，用国内源反而慢）