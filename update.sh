#!/usr/bin/env bash
# 指定使用 bash 程序执行此脚本

set -e
# 设置"安全模式"：任何步骤出错就立即停止
set -o errexit
# 同上，设置错误时退出（与set -e相同）
set -o errtrace
# 设置错误追踪，使得错误能被trap捕获

# 定义错误处理函数
error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}
# 当脚本出错时，这个函数会被调用，打印出错的行号和命令

# 设置trap捕获ERR信号（当命令返回非零状态时）
trap 'error_handler' ERR
# 当发生错误时，调用error_handler函数处理

BASE_PATH=$(cd $(dirname $0) && pwd)
# 获取脚本所在的目录的绝对路径，并保存到BASE_PATH变量中

REPO_URL=$1
# 从命令行获取第一个参数（代码仓库地址）

REPO_BRANCH=$2
# 从命令行获取第二个参数（代码仓库分支）

BUILD_DIR=$3
# 从命令行获取第三个参数（构建目录路径）

COMMIT_HASH=$4
# 从命令行获取第四个参数（代码提交的哈希值，用于指定特定版本）

FEEDS_CONF="feeds.conf.default"
# 设置feeds配置文件的名称，这个文件定义了软件包的源

GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
# 设置Golang语言包的仓库地址

GOLANG_BRANCH="25.x"
# 设置Golang语言包的分支名

THEME_SET="argon"
# 设置默认主题名称

LAN_ADDR="192.168.111.1"
# 设置默认的局域网地址

# 克隆仓库函数
clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo $REPO_URL $REPO_BRANCH
        git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR
    fi
}
# 定义克隆仓库的函数：
# 如果构建目录不存在，则克隆指定的仓库和分支到构建目录
# --depth 1 表示浅克隆，只下载最新提交

# 清理函数
clean_up() {
    cd $BUILD_DIR
    if [[ -f $BUILD_DIR/.config ]]; then
        \rm -f $BUILD_DIR/.config
    fi
    if [[ -d $BUILD_DIR/tmp ]]; then
        \rm -rf $BUILD_DIR/tmp
    fi
    if [[ -d $BUILD_DIR/logs ]]; then
        \rm -rf $BUILD_DIR/logs/*
    fi
    mkdir -p $BUILD_DIR/tmp
    echo "1" >$BUILD_DIR/tmp/.build
}
# 定义清理函数：
# 进入构建目录
# 删除旧的配置文件（.config）
# 删除临时目录（tmp）及其内容
# 删除日志目录（logs）下的所有文件
# 重新创建临时目录（tmp）
# 在临时目录中创建一个.build文件，内容为"1"（标记构建开始）

# 重置feeds配置
reset_feeds_conf() {
    git reset --hard origin/$REPO_BRANCH
    git clean -f -d
    git pull
    if [[ $COMMIT_HASH != "none" ]]; then
        git checkout $COMMIT_HASH
    fi
}
# 定义重置feeds配置的函数：
# 将代码重置到远程分支的最新状态
# 清理未跟踪的文件和目录
# 拉取最新代码
# 如果指定了提交哈希值，则检出该提交（即使用特定版本）

# 更新feeds
update_feeds() {
    # 删除注释行
    sed -i '/^#/d' "$BUILD_DIR/$FEEDS_CONF"

    # 检查并添加 small-package 源
    if ! grep -q "small-package" "$BUILD_DIR/$FEEDS_CONF"; then
        # 确保文件以换行符结尾
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git small8 https://github.com/kenzok8/small-package" >>"$BUILD_DIR/$FEEDS_CONF"
    fi

    # 添加bpf.mk解决更新报错
    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi

    # 更新 feeds
    ./scripts/feeds clean
    ./scripts/feeds update -a
}
# 定义更新feeds的函数：
# 1. 删除feeds配置文件中的注释行（以#开头的行）
# 2. 检查是否已添加small-package源，如果没有则添加（确保文件以换行符结尾）
# 3. 如果bpf.mk文件不存在，则创建一个空文件（避免更新报错）
# 4. 清理旧的feeds缓存
# 5. 更新所有feeds（下载软件包列表）

# 移除不需要的软件包
remove_unwanted_packages() {
    # 定义要移除的软件包列表
    local luci_packages=(...)
    local packages_net=(...)
    local packages_utils=(...)
    local small8_packages=(...)

    # 遍历并删除luci应用包
    for pkg in "${luci_packages[@]}"; do
        if [[ -d ./feeds/luci/applications/$pkg ]]; then
            \rm -rf ./feeds/luci/applications/$pkg
        fi
        if [[ -d ./feeds/luci/themes/$pkg ]]; then
            \rm -rf ./feeds/luci/themes/$pkg
        fi
    done

    # 遍历并删除网络包
    for pkg in "${packages_net[@]}"; do
        if [[ -d ./feeds/packages/net/$pkg ]]; then
            \rm -rf ./feeds/packages/net/$pkg
        fi
    done

    # 遍历并删除工具包
    for pkg in "${packages_utils[@]}"; do
        if [[ -d ./feeds/packages/utils/$pkg ]]; then
            \rm -rf ./feeds/packages/utils/$pkg
        fi
    done

    # 遍历并删除small8包
    for pkg in "${small8_packages[@]}"; do
        if [[ -d ./feeds/small8/$pkg ]]; then
            \rm -rf ./feeds/small8/$pkg
        fi
    done

    # 删除istore目录
    if [[ -d ./package/istore ]]; then
        \rm -rf ./package/istore
    fi

    # 清理qualcommax平台下的脚本文件
    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
}
# 定义移除不需要的软件包的函数：
# 1. 定义四个数组，分别列出要移除的luci应用包、网络包、工具包和small8包
# 2. 遍历luci应用包数组，删除对应的目录（如果存在）
# 3. 遍历网络包数组，删除对应的目录（如果存在）
# 4. 遍历工具包数组，删除对应的目录（如果存在）
# 5. 遍历small8包数组，删除对应的目录（如果存在）
# 6. 删除istore目录（如果存在）
# 7. 删除qualcommax平台下的99开头的脚本文件（临时清理）

# 更新Golang
update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        \rm -rf ./feeds/packages/lang/golang
        git clone --depth 1 $GOLANG_REPO -b $GOLANG_BRANCH ./feeds/packages/lang/golang
    fi
}
# 定义更新Golang的函数：
# 如果Golang包目录存在，则删除它
# 然后克隆指定仓库和分支的Golang包到原位置

# 安装small8包
install_small8() {
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        luci-app-passwall v2dat mosdns luci-app-mosdns adguardhome luci-app-adguardhome ddns-go \
        luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd luci-app-store quickstart \
        luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest netdata luci-app-netdata \
        lucky luci-app-lucky luci-app-openclash luci-app-homeproxy luci-app-amlogic nikki luci-app-nikki \
        tailscale luci-app-tailscale oaf open-app-filter luci-app-oaf easytier luci-app-easytier \
        msd_lite luci-app-msd_lite cups luci-app-cupsd 
# ====== Mary定制包Full======
    ./scripts/feeds install -p small8 -f luci-app-frpc luci-app-frps luci-app-openlist2 \
        luci-app-zerotier

}
# 定义安装small8包的函数：
# 使用feeds命令安装一系列指定的软件包（来自small8源）
# 这些包包括各种网络工具、代理工具、应用等

# 安装fullconenat
install_fullconenat() {
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat-nft ]; then
        ./scripts/feeds install -p small8 -f fullconenat-nft
    fi
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat ]; then
        ./scripts/feeds install -p small8 -f fullconenat
    fi
}
# 定义安装fullconenat的函数：
# 如果fullconenat-nft包不存在，则安装它
# 如果fullconenat包不存在，则安装它
# 这两个包是网络地址转换（NAT）相关的工具

# 安装feeds
install_feeds() {
    ./scripts/feeds update -i
    for dir in $BUILD_DIR/feeds/*; do
        # 检查是否为目录并且不以 .tmp 结尾，并且不是软链接
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [ ! -L "$dir" ]; then
            if [[ $(basename "$dir") == "small8" ]]; then
                install_small8
                install_fullconenat
            else
                ./scripts/feeds install -f -ap $(basename "$dir")
            fi
        fi
    done
}
# 定义安装所有feeds的函数：
# 1. 更新所有feeds的索引（-i表示忽略错误）
# 2. 遍历feeds目录下的所有子目录：
#    - 如果是目录且不以.tmp结尾，且不是软链接：
#        a. 如果是small8源，则调用install_small8和install_fullconenat函数
#        b. 否则，安装该源下的所有包（-f表示强制安装，-a表示所有包，-p表示指定源）

# 修复默认设置
fix_default_set() {
    # 修改默认主题
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    # 安装自定义脚本
    install -Dm755 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm755 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"

    # 替换温度信息脚本
    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}
# 定义修复默认设置的函数：
# 1. 修改默认主题：将所有luci集合中的Makefile文件中的主题从bootstrap改为argon（或其他指定主题）
# 2. 安装两个自定义脚本（990_set_argon_primary和991_custom_settings）到系统初始化目录
# 3. 如果存在tempinfo文件，则用补丁中的tempinfo文件替换它（可能是修复温度显示问题）

# 修复miniupnpd
fix_miniupnpd() {
    local miniupnpd_dir="$BUILD_DIR/feeds/packages/net/miniupnpd"
    local patch_file="999-chanage-default-leaseduration.patch"

    if [ -d "$miniupnpd_dir" ] && [ -f "$BASE_PATH/patches/$patch_file" ]; then
        install -Dm644 "$BASE_PATH/patches/$patch_file" "$miniupnpd_dir/patches/$patch_file"
    fi
}
# 定义修复miniupnpd的函数：
# 如果miniupnpd目录存在且补丁文件存在，则将补丁文件安装到miniupnpd的补丁目录
# 这个补丁可能是修改miniupnpd的默认租约时间

# 将dnsmasq替换为dnsmasq-full
change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
}
# 定义将dnsmasq替换为dnsmasq-full的函数：
# 如果target.mk文件中没有dnsmasq-full，则将所有的dnsmasq替换为dnsmasq-full
# dnsmasq-full是功能更完整的版本

# 修复Makefile依赖
fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' $BUILD_DIR/include/target.mk 2>/dev/null
    if [ -f $BUILD_DIR/target/linux/qualcommax/Makefile ]; then
        sed -i 's/wpad-openssl/wpad-mesh-openssl/g' $BUILD_DIR/target/linux/qualcommax/Makefile
    fi
}
# 定义修复Makefile依赖的函数：
# 1. 将target.mk中的libustream-mbedtls替换为libustream-openssl（使用OpenSSL而不是mbed TLS）
# 2. 如果qualcommax平台的Makefile存在，将wpad-openssl替换为wpad-mesh-openssl（支持网状网络）

# 添加WiFi默认设置
add_wifi_default_set() {
    local qualcommax_uci_dir="$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults"
    local filogic_uci_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/etc/uci-defaults"
    if [ -d "$qualcommax_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$qualcommax_uci_dir/992_set-wifi-uci.sh"
    fi
    if [ -d "$filogic_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$filogic_uci_dir/992_set-wifi-uci.sh"
    fi
}
# 定义添加WiFi默认设置的函数：
# 如果qualcommax平台的UCI默认设置目录存在，则安装WiFi设置脚本
# 如果filogic平台的UCI默认设置目录存在，也安装同样的WiFi设置脚本
# 这个脚本（992_set-wifi-uci.sh）可能是设置WiFi的默认参数

# 更新默认LAN地址
update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f $CFG_PATH ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' $CFG_PATH
    fi
}
# 定义更新默认LAN地址的函数：
# 如果配置生成脚本存在，则将其中的192.168.x.x地址替换为指定的LAN_ADDR（192.168.1.1）

# 移除NSS相关内核模块
remove_something_nss_kmod() {
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    local target_mks=("$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk" "$BUILD_DIR/target/linux/qualcommax/ipq807x/target.mk")

    for target_mk in "${target_mks[@]}"; do
        if [ -f "$target_mk" ]; then
            sed -i 's/kmod-qca-nss-crypto//g' "$target_mk"
        fi
    done

    if [ -f "$ipq_mk_path" ]; then
        sed -i '/kmod-qca-nss-drv-eogremgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-gre/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-map-t/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-match/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-mirror/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-tun6rd/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-tunipip6/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-vxlanmgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-macsec/d' "$ipq_mk_path"

        sed -i 's/automount //g' "$ipq_mk_path"
        sed -i 's/cpufreq //g' "$ipq_mk_path"
    fi
}
# 定义移除NSS相关内核模块的函数：
# 1. 在ipq60xx和ipq807x的target.mk文件中移除kmod-qca-nss-crypto模块
# 2. 在qualcommax的Makefile中移除一系列nss驱动模块（如eogremgr、gre等）
# 3. 移除automount和cpufreq模块
# 这些操作可能是为了精简系统或解决兼容性问题

# 更新亲和性脚本
update_affinity_script() {
    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"

    if [ -d "$affinity_script_dir" ]; then
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
        install -Dm755 "$BASE_PATH/patches/smp_affinity" "$affinity_script_dir/base-files/etc/init.d/smp_affinity"
    fi
}
# 定义更新亲和性脚本的函数：
# 如果qualcommax目录存在：
# 1. 删除所有名为set-irq-affinity的文件
# 2. 删除所有名为smp_affinity的文件
# 3. 安装新的smp_affinity脚本到初始化目录
# 这个脚本可能是设置CPU亲和性（将中断绑定到特定CPU核心）

# 修复哈希值
fix_hash_value() {
    local makefile_path="$1"
    local old_hash="$2"
    local new_hash="$3"
    local package_name="$4"

    if [ -f "$makefile_path" ]; then
        sed -i "s/$old_hash/$new_hash/g" "$makefile_path"
        echo "已修正 $package_name 的哈希值。"
    fi
}
# 定义修复哈希值的函数：
# 参数：Makefile路径、旧哈希值、新哈希值、包名
# 如果Makefile存在，则将其中的旧哈希值替换为新哈希值
# 并打印修正信息

# 应用哈希值修正
apply_hash_fixes() {
    fix_hash_value \
        "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" \
        "150019a03f1ec2e4b5849740a72badf5ea094d5754bd59dd30119523a3ce9398" \
        "abcb3d3bfa99297dfb92b8fb4f1f78d0948a01281fdfc76c9c460a2c3d5c7f79" \
        "smartdns"
}
# 定义应用哈希值修正的函数：
# 调用fix_hash_value函数修正smartdns包的哈希值
# 将旧哈希值替换为新哈希值

# 更新ath11k固件
update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    local new_mk="$BASE_PATH/patches/ath11k_fw.mk"

    if [ -d "$(dirname "$makefile")" ] && [ -f "$makefile" ]; then
        [ -f "$new_mk" ] && \rm -f "$new_mk"
        curl -L -o "$new_mk" https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile
        \mv -f "$new_mk" "$makefile"
    fi
}
# 定义更新ath11k固件的函数：
# 1. 设置ath11k-firmware的Makefile路径
# 2. 如果Makefile存在：
#    a. 删除旧的临时文件（如果存在）
#    b. 从GitHub下载最新的Makefile
#    c. 用下载的文件替换原有的Makefile

# 修复Makefile格式无效问题
fix_mkpkg_format_invalid() {
    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        if [ -f $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-store/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
        fi
    fi
}
# 定义修复Makefile格式无效问题的函数：
# 如果构建目录包含"imm-nss"（可能是特定分支）：
# 1. 修复v2ray-geodata的Makefile中的版本格式
# 2. 修复luci-lib-taskd的Makefile中的版本要求格式
# 3. 修复luci-app-openclash的Makefile中的发布版本
# 4. 修复luci-app-quickstart的Makefile中的版本和发布版本
# 5. 修复luci-app-store的Makefile中的版本和发布版本

# 添加AX6600 LED控制
add_ax6600_led() {
    local athena_led_dir="$BUILD_DIR/package/emortal/luci-app-athena-led"

    # 删除旧的目录（如果存在）
    rm -rf "$athena_led_dir" 2>/dev/null

    # 克隆最新的仓库
    git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led.git "$athena_led_dir"
    # 设置执行权限
    chmod +x "$athena_led_dir/root/usr/sbin/athena-led"
    chmod +x "$athena_led_dir/root/etc/init.d/athena_led"
}
# 定义添加AX6600 LED控制的函数：
# 1. 设置LED应用目录路径
# 2. 删除旧目录（如果存在）
# 3. 从GitHub克隆最新的LED控制应用
# 4. 给两个脚本文件添加执行权限

# 修改CPU使用率显示
change_cpuusage() {
    local luci_rpc_path="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    local qualcommax_sbin_dir="$BUILD_DIR/target/linux/qualcommax/base-files/sbin"
    local filogic_sbin_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/sbin"

    # 修改LuCI RPC脚本以优先使用自定义的cpuusage脚本
    if [ -f "$luci_rpc_path" ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" "$luci_rpc_path"
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' "$luci_rpc_path"
    fi

    # 删除旧脚本（如果存在）
    local old_script_path="$BUILD_DIR/package/base-files/files/sbin/cpuusage"
    if [ -f "$old_script_path" ]; then
        rm -f "$old_script_path"
    fi

    # 安装平台特定的cpuusage脚本
    install -Dm755 "$BASE_PATH/patches/cpuusage" "$qualcommax_sbin_dir/cpuusage"
    install -Dm755 "$BASE_PATH/patches/hnatusage" "$filogic_sbin_dir/cpuusage"
}
# 定义修改CPU使用率显示的函数：
# 1. 设置LuCI RPC脚本路径和两个平台的sbin目录
# 2. 修改LuCI RPC脚本：优先使用自定义的cpuusage脚本，如果不存在则使用原来的top命令
# 3. 删除旧的cpuusage脚本（如果存在）
# 4. 为qualcommax平台安装cpuusage脚本
# 5. 为filogic平台安装hnatusage脚本（重命名为cpuusage）

# 更新tcping工具
update_tcping() {
    local tcping_path="$BUILD_DIR/feeds/small8/tcping/Makefile"

    if [ -d "$(dirname "$tcping_path")" ] && [ -f "$tcping_path" ]; then
        \rm -f "$tcping_path"
        curl -L -o "$tcping_path" https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/refs/heads/main/tcping/Makefile
    fi
}
# 定义更新tcping工具的函数：
# 如果tcping的Makefile存在：
# 1. 删除旧的Makefile
# 2. 从GitHub下载新的Makefile

# 设置自定义任务
set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
# 设置启动优先级
START=99

boot() {
    # 重新添加缓存清理定时任务
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root

    # 删除现有的 wireguard_watchdog 任务
    sed -i '/wireguard_watchdog/d' /etc/crontabs/root

    # 获取 WireGuard 接口名称
    local wg_ifname=$(wg show | awk '/interface/ {print $2}')

    if [ -n "$wg_ifname" ]; then
        # 添加新的 wireguard_watchdog 任务，每15分钟执行一次
        echo "*/15 * * * * /usr/bin/wireguard_watchdog" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi

    # 应用新的 crontab 配置
    crontab /etc/crontabs/root
}
EOF
    chmod +x "$sh_dir/custom_task"
}
# 定义设置自定义任务的函数：
# 1. 设置初始化脚本目录
# 2. 创建一个名为custom_task的初始化脚本：
#    a. 设置启动优先级为99（最后启动）
#    b. 在boot函数中：
#       - 删除旧的缓存清理任务，并添加新的（每天3:15清理缓存）
#       - 删除旧的WireGuard看门狗任务
#       - 如果存在WireGuard接口，添加新的看门狗任务（每15分钟检查一次）
#       - 重启cron服务
#       - 应用新的crontab配置
# 3. 给脚本添加执行权限

# 应用Passwall相关调整
apply_passwall_tweaks() {
    # 清理 Passwall 的 chnlist 规则文件
    local chnlist_path="$BUILD_DIR/feeds/small8/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then
        > "$chnlist_path"
    fi

    # 调整 Xray 最大 RTT
    local xray_util_path="$BUILD_DIR/feeds/small8/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
    fi
}
# 定义应用Passwall相关调整的函数：
# 1. 清空Passwall的chnlist规则文件（可能是清空中国域名列表）
# 2. 调整Xray的最大往返时间（RTT）从1秒改为2秒（可能是为了提高稳定性）

# 安装opkg的distfeeds配置
install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"

    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        cat <<'EOF' >"$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF

        sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile

        sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
    fi
}
# 定义安装opkg的distfeeds配置的函数：
# 1. 设置default-settings包的目录和distfeeds配置文件路径
# 2. 如果目录存在且配置文件不存在：
#    a. 创建distfeeds.conf文件，包含ImmortalWrt的软件源地址
#    b. 修改default-settings的Makefile，在安装部分添加复制distfeeds.conf的命令
#    c. 修改99-default-settings脚本，在退出前：
#       - 将99-distfeeds.conf移动到/etc/opkg/distfeeds.conf
#       - 注释掉opkg.conf中的签名检查（禁用签名验证）

# 更新NSS pbuf性能设置
update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f $pbuf_path ]; then
        sed -i "s/auto_scale '1'/auto_scale 'off'/g" $pbuf_path
        sed -i "s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" $pbuf_path
    fi
}
# 定义更新NSS pbuf性能设置的函数：
# 如果pbuf.uci文件存在：
# 1. 将auto_scale从'1'改为'off'（关闭自动缩放）
# 2. 将scaling_governor从'performance'改为'schedutil'（使用调度器调节CPU频率）

# 设置构建签名
set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by ZqinKing')/g" "$file"
    fi
}
# 定义设置构建签名的函数：
# 如果系统状态JavaScript文件存在：
# 在版本号后面添加" / build by ZqinKing"的签名

# 更新NSS诊断脚本
update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        \rm -f "$file"
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
    fi
}
# 定义更新NSS诊断脚本的函数：
# 如果nss_diag.sh文件存在：
# 1. 删除旧文件
# 2. 安装新的诊断脚本（来自补丁目录）

# 更新菜单位置
update_menu_location() {
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then
        sed -i 's/nas/services/g' "$samba4_path"
    fi

    local tailscale_path="$BUILD_DIR/feeds/small8/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi
}
# 定义更新菜单位置的函数：
# 1. 将Samba4应用从"nas"（网络存储）移动到"services"（服务）菜单
# 2. 将Tailscale应用从"services"（服务）移动到"vpn"菜单

# 修复Coremark编译问题
fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}
# 定义修复Coremark编译问题的函数：
# 如果Coremark的Makefile存在：
# 将mkdir命令改为mkdir -p（自动创建父目录）

# 更新Homeproxy
update_homeproxy() {
    local repo_url="https://github.com/immortalwrt/homeproxy.git"
    local target_dir="$BUILD_DIR/feeds/small8/luci-app-homeproxy"

    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
        git clone --depth 1 "$repo_url" "$target_dir"
    fi
}
# 定义更新Homeproxy的函数：
# 如果Homeproxy目录存在：
# 1. 删除旧目录
# 2. 从GitHub克隆最新的Homeproxy应用

# 更新dnsmasq配置
update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i '/dns_redirect/d' "$file"
    fi
}
# 定义更新dnsmasq配置的函数：
# 如果dnsmasq的dhcp.conf文件存在：
# 删除包含dns_redirect的行（可能是禁用DNS重定向功能）

# 更新软件包版本
update_package() {
    local dir=$(find "$BUILD_DIR/package" \( -type d -o -type l \) -name $1)
    if [ -z "$dir" ]; then
        return 0
    fi
    local branch=$2
    if [ -z "$branch" ]; then
        branch="releases"
    fi
    local mk_path="$dir/Makefile"
    if [ -f "$mk_path" ]; then
        # 提取repo
        local PKG_REPO=$(grep -oE "^PKG_GIT_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" $mk_path | awk -F"/" '{print $(NF - 1) "/" $NF}')
        if [ -z "$PKG_REPO" ]; then
            PKG_REPO=$(grep -oE "^PKG_SOURCE_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" $mk_path | awk -F"/" '{print $(NF - 1) "/" $NF}')
            if [ -z "$PKG_REPO" ]; then
                return 0
            fi
        fi
        local PKG_VER=$(curl -sL "https://api.github.com/repos/$PKG_REPO/$branch" | jq -r '.[0] | .tag_name // .name')
        if [ -n "$3" ]; then
            PKG_VER=$3
        fi
        local COMMIT_SHA=$(curl -sL "https://api.github.com/repos/$PKG_REPO/tags" | jq -r '.[] | select(.name=="'$PKG_VER'") | .commit.sha' | cut -c1-7)
        if [ -n "$COMMIT_SHA" ]; then
            sed -i 's/^PKG_GIT_SHORT_COMMIT:=.*/PKG_GIT_SHORT_COMMIT:='$COMMIT_SHA'/g' $mk_path
        fi
        PKG_VER=$(echo $PKG_VER | grep -oE "[\.0-9]{1,}")

        local PKG_NAME=$(awk -F"=" '/PKG_NAME:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE=$(awk -F"=" '/PKG_SOURCE:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE_URL=$(awk -F"=" '/PKG_SOURCE_URL:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\{\}\?\.a-zA-Z0-9]{1,}")
        local PKG_GIT_URL=$(awk -F"=" '/PKG_GIT_URL:=/ {print $NF}' $mk_path)
        local PKG_GIT_REF=$(awk -F"=" '/PKG_GIT_REF:=/ {print $NF}' $mk_path)

        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_GIT_URL\)/$PKG_GIT_URL}
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_GIT_REF\)/$PKG_GIT_REF}
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE_URL=$(echo "$PKG_SOURCE_URL" | sed "s/\${PKG_VERSION}/$PKG_VER/g; s/\$(PKG_VERSION)/$PKG_VER/g")
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_VERSION\)/$PKG_VER}

        local PKG_HASH=$(curl -sL "$PKG_SOURCE_URL""$PKG_SOURCE" | sha256sum | cut -b -64)

        sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:='$PKG_VER'/g' $mk_path
        sed -i 's/^PKG_HASH:=.*/PKG_HASH:='$PKG_HASH'/g' $mk_path

        echo "Update Package $1 to $PKG_VER $PKG_HASH"
    fi
}
# 定义更新软件包版本的函数：
# 参数：包名、分支名、可选的版本号
# 1. 查找包的目录
# 2. 如果目录不存在则返回
# 3. 设置默认分支为releases
# 4. 获取Makefile路径
# 5. 如果Makefile存在：
#    a. 从Makefile中提取GitHub仓库地址
#    b. 如果没找到，尝试从PKG_SOURCE_URL中提取
#    c. 如果还是没找到则返回
#    d. 从GitHub API获取最新版本号（或使用指定的版本号）
#    e. 获取该版本的提交哈希（前7位）
#    f. 更新Makefile中的提交哈希
#    g. 提取版本号中的数字和点
#    h. 从Makefile中提取包名、源文件名、源URL等
#    i. 替换URL中的变量（如PKG_GIT_URL、PKG_GIT_REF等）
#    j. 计算源文件的SHA256哈希值
#    k. 更新Makefile中的版本号和哈希值
#    l. 打印更新信息

# 添加系统升级时的备份信息
function add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"

    if [ -f "$conf_path" ]; then
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
    fi
}
# 定义添加系统升级时的备份信息的函数：
# 如果sysupgrade.conf文件存在：
# 覆盖文件内容，添加三个路径：
# 1. AdGuardHome的配置文件
# 2. easytier的配置目录
# 3. lucky的配置目录
# 这些文件在系统升级时会被备份

# 更新启动顺序
function update_script_priority() {
    # 更新qca-nss驱动的启动顺序
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then
        sed -i 's/START=.*/START=88/g' "$qca_drv_path"
    fi

    # 更新pbuf服务的启动顺序
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then
        sed -i 's/START=.*/START=89/g' "$pbuf_path"
    fi

    # 更新mosdns服务的启动顺序
    local mosdns_path="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}
# 定义更新启动顺序的函数：
# 1. 将qca-nss驱动的启动顺序设置为88
# 2. 将pbuf服务的启动顺序设置为89
# 3. 将mosdns服务的启动顺序设置为94
# 数字越小启动越早，这里调整启动顺序以确保服务按正确顺序启动

# 更新Mosdns配置
update_mosdns_deconfig() {
    local mosdns_conf="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}
# 定义更新Mosdns配置的函数：
# 如果Mosdns配置文件存在：
# 1. 将端口8000改为300
# 2. 将端口5335改为5336
# 可能是为了避免端口冲突

# 修复Quickstart
fix_quickstart() {
    local file_path="$BUILD_DIR/feeds/small8/luci-app-quickstart/luasrc/controller/istore_backend.lua"
    # 下载新的istore_backend.lua文件并覆盖
    if [ -f "$file_path" ]; then
        \rm -f "$file_path"
        curl -L https://gist.githubusercontent.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa/raw/istore_backend.lua \
            -o "$file_path"
    fi
}
# 定义修复Quickstart的函数：
# 如果istore_backend.lua文件存在：
# 1. 删除旧文件
# 2. 从GitHub下载新文件

# 更新OAF配置
update_oaf_deconfig() {
    local conf_path="$BUILD_DIR/feeds/small8/open-app-filter/files/appfilter.config"
    local uci_def="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0"
    local disable_path="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/99_disable_oaf"

    if [ -d "${conf_path%/*}" ] && [ -f "$conf_path" ]; then
        sed -i \
            -e "s/record_enable '1'/record_enable '0'/g" \
            -e "s/disable_hnat '1'/disable_hnat '0'/g" \
            -e "s/auto_load_engine '1'/auto_load_engine '0'/g" \
            "$conf_path"
    fi

    if [ -d "${uci_def%/*}" ] && [ -f "$uci_def" ]; then
        sed -i '/\(disable_hnat\|auto_load_engine\)/d' "$uci_def"

        # 禁用脚本
        cat >"$disable_path" <<-EOF
#!/bin/sh
[ "\$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
        chmod +x "$disable_path"
    fi
}
# 定义更新OAF配置的函数：
# 1. 如果appfilter.config存在：
#    a. 将record_enable从1改为0（禁用记录）
#    b. 将disable_hnat从1改为0（启用硬件加速）
#    c. 将auto_load_engine从1改为0（禁用自动加载引擎）
# 2. 如果94_feature_3.0文件存在：
#    a. 删除包含disable_hnat或auto_load_engine的行
#    b. 创建禁用脚本（99_disable_oaf）：
#       - 如果appfilter被禁用，则停止并禁用服务
#    c. 给脚本添加执行权限

# 支持FW4和AdGuardHome
support_fw4_adg() {
    local src_path="$BASE_PATH/patches/AdGuardHome"
    local dst_path="$BUILD_DIR/package/feeds/small8/luci-app-adguardhome/root/etc/init.d/AdGuardHome"
    # 验证源路径是否文件存在且是文件，目标路径目录存在且脚本路径合法
    if [ -f "$src_path" ] && [ -d "${dst_path%/*}" ] && [ -f "$dst_path" ]; then
        # 使用 install 命令替代 cp 以确保权限和备份处理
        install -Dm 755 "$src_path" "$dst_path"
        echo "已更新AdGuardHome启动脚本"
    fi
}
# 定义支持FW4和AdGuardHome的函数：
# 如果源文件和目标文件都存在：
# 使用install命令将AdGuardHome的启动脚本从补丁目录复制到目标目录
# 并设置权限为755（所有者可读写执行，其他用户可读执行）

# 添加时间控制插件
add_timecontrol() {
    local timecontrol_dir="$BUILD_DIR/package/luci-app-timecontrol"
    # 删除旧的目录（如果存在）
    rm -rf "$timecontrol_dir" 2>/dev/null
    git clone --depth 1 https://github.com/sirpdboy/luci-app-timecontrol.git "$timecontrol_dir"
}
# 定义添加时间控制插件的函数：
# 1. 设置时间控制插件的目录路径
# 2. 删除旧目录（如果存在）
# 3. 从GitHub克隆时间控制插件


# ====== Mary定制包Full======

# 添加smaba4用户管理插件smbuser
add_smbuser() {
    local smbuser_dir="$BUILD_DIR/package/luci-app-smbuser"
    # 删除旧的目录（如果存在）
    rm -rf "$smbuser_dir" 2>/dev/null
    git clone --depth 1 https://github.com/sbwml/luci-app-smbuser.git "$smbuser_dir"
}

# 添加测速插件netspeedtest
add_netspeedtest() {
    local netspeedtest_dir="$BUILD_DIR/package/luci-app-netspeedtest"
    # 删除旧的目录（如果存在）
    rm -rf "$netspeedtest_dir" 2>/dev/null
    git clone --depth 1 https://github.com/sirpdboy/luci-app-netspeedtest.git "$netspeedtest_dir"
}

# 添加磁盘分区挂载插件partexp
add_partexp() {
    local partexp_dir="$BUILD_DIR/package/luci-app-partexp"
    # 删除旧的目录（如果存在）
    rm -rf "$partexp_dir" 2>/dev/null
    git clone --depth 1 https://github.com/sirpdboy/luci-app-partexp.git "$partexp_dir"
}

# 添加定时任务插件taskplan
add_taskplan() {
    local taskplan_dir="$BUILD_DIR/package/luci-app-taskplan"
    # 删除旧的目录（如果存在）
    rm -rf "$taskplan_dir" 2>/dev/null
    git clone --depth 1 https://github.com/sirpdboy/luci-app-taskplan.git "$taskplan_dir"
}

# 添加定时重启插件timewol
add_timewol() {
    local timewol_dir="$BUILD_DIR/package/luci-app-timewol"
    # 删除旧的目录（如果存在）
    rm -rf "$timewol_dir" 2>/dev/null
    git clone --depth 1 https://github.com/VIKINGYFY/luci-app-timewol.git "$timewol_dir"
}

# 添加定时重启插件wolplus
add_wolplus() {
    local wolplus_dir="$BUILD_DIR/package/luci-app-wolplus"
    # 删除旧的目录（如果存在）
    rm -rf "$wolplus_dir" 2>/dev/null
    git clone --depth 1 https://github.com/VIKINGYFY/luci-app-wolplus.git "$wolplus_dir"
}

# ====== Mary定制包Full======


# 添加GecoosAC
add_gecoosac() {
    local gecoosac_dir="$BUILD_DIR/package/openwrt-gecoosac"
    # 删除旧的目录（如果存在）
    rm -rf "$gecoosac_dir" 2>/dev/null
    git clone --depth 1 https://github.com/lwb1978/openwrt-gecoosac.git "$gecoosac_dir"
}
# 定义添加GecoosAC的函数：
# 1. 设置GecoosAC的目录路径
# 2. 删除旧目录（如果存在）
# 3. 从GitHub克隆GecoosAC项目

# 修复Easytier
fix_easytier() {
    local easytier_path="$BUILD_DIR/package/feeds/small8/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -d "${easytier_path%/*}" ] && [ -f "$easytier_path" ]; then
        sed -i 's/util/xml/g' "$easytier_path"
    fi
}
# 定义修复Easytier的函数：
# 如果easytier.lua文件存在：
# 将文件中的"util"替换为"xml"（可能是修复模块引用问题）

# 更新GeoIP数据库
update_geoip() {
    local geodata_path="$BUILD_DIR/package/feeds/small8/v2ray-geodata/Makefile"
    if [ -d "${geodata_path%/*}" ] && [ -f "$geodata_path" ]; then
        local GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' $geodata_path | grep -oE "[0-9]{1,}")
        if [ -n "$GEOIP_VER" ]; then
            local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
            # 下载旧的geoip.dat和新的geoip-only-cn-private.dat文件的校验和
            local old_SHA256=$(wget -qO- "$base_url/geoip.dat.sha256sum" | awk '{print $1}')
            local new_SHA256=$(wget -qO- "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}')
            # 更新Makefile中的文件名和校验和
            if [ -n "$old_SHA256" ] && [ -n "$new_SHA256" ]; then
                if grep -q "$old_SHA256" "$geodata_path"; then
                    sed -i "s|=geoip.dat|=geoip-only-cn-private.dat|g" "$geodata_path"
                    sed -i "s/$old_SHA256/$new_SHA256/g" "$geodata_path"
                fi
            fi
        fi
    fi
}
# 定义更新GeoIP数据库的函数：
# 如果v2ray-geodata的Makefile存在：
# 1. 提取GeoIP版本号
# 2. 如果版本号存在：
#    a. 构建基础URL
#    b. 下载旧文件（geoip.dat）和新文件（geoip-only-cn-private.dat）的SHA256校验和
#    c. 如果校验和存在且Makefile中包含旧校验和：
#       - 将文件名从geoip.dat改为geoip-only-cn-private.dat
#       - 将旧校验和替换为新校验和

# 更新Lucky
update_lucky() {
    # 从补丁文件名中提取版本号
    local version
    version=$(find "$BASE_PATH/patches" -name "lucky_*.tar.gz" -printf "%f\n" | head -n 1 | sed -n 's/^lucky_\(.*\)_Linux.*$/\1/p')
    if [ -z "$version" ]; then
        echo "Warning: 未找到 lucky 补丁文件，跳过更新。" >&2
        return 1
    fi

    local makefile_path="$BUILD_DIR/feeds/small8/lucky/Makefile"
    if [ ! -f "$makefile_path" ]; then
        echo "Warning: lucky Makefile not found. Skipping." >&2
        return 1
    fi

    echo "正在更新 lucky Makefile..."
    # 使用本地补丁文件，而不是下载
    local patch_line="\\t[ -f \$(TOPDIR)/../patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz ] && install -Dm644 \$(TOPDIR)/../patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz \$(PKG_BUILD_DIR)/\$(PKG_NAME)_\$(PKG_VERSION)_Linux_\$(LUCKY_ARCH).tar.gz"

    # 确保 Build/Prepare 部分存在，然后在其后添加我们的行
    if grep -q "Build/Prepare" "$makefile_path"; then
        sed -i "/Build\\/Prepare/a\\$patch_line" "$makefile_path"
        # 删除任何现有的 wget 命令
        sed -i '/wget/d' "$makefile_path"
        echo "lucky Makefile 更新完成。"
    else
        echo "Warning: lucky Makefile 中未找到 'Build/Prepare'。跳过。" >&2
    fi
}
# 定义更新Lucky的函数：
# 1. 从补丁文件名中提取版本号
# 2. 如果没找到补丁文件，打印警告并返回
# 3. 如果Makefile不存在，打印警告并返回
# 4. 打印更新信息
# 5. 构建补丁行：如果本地补丁文件存在，则安装它
# 6. 如果Makefile中有Build/Prepare部分：
#    a. 在Build/Prepare后添加补丁行
#    b. 删除所有wget命令（不再从网络下载）
#    c. 打印完成信息
# 7. 如果没有Build/Prepare部分，打印警告

# 修复Rust编译错误
fix_rust_compile_error() {
    if [ -f "$BUILD_DIR/feeds/packages/lang/rust/Makefile" ]; then
        sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$BUILD_DIR/feeds/packages/lang/rust/Makefile"
    fi
}
# 定义修复Rust编译错误的函数：
# 如果Rust的Makefile存在：
# 将download-ci-llvm从true改为false（禁用下载CI LLVM）

# 更新Smartdns
update_smartdns() {
    # smartdns 仓库地址
    local SMARTDNS_REPO="https://github.com/pymumu/openwrt-smartdns.git"
    local SMARTDNS_DIR="$BUILD_DIR/feeds/packages/net/smartdns"
    # luci-app-smartdns 仓库地址
    local LUCI_APP_SMARTDNS_REPO="https://github.com/pymumu/luci-app-smartdns.git"
    local LUCI_APP_SMARTDNS_DIR="$BUILD_DIR/feeds/luci/applications/luci-app-smartdns"

    echo "正在更新 smartdns..."
    rm -rf "$SMARTDNS_DIR"
    git clone --depth=1 "$SMARTDNS_REPO" "$SMARTDNS_DIR"

    install -Dm644 "$BASE_PATH/patches/100-smartdns-optimize.patch" "$SMARTDNS_DIR/patches/100-smartdns-optimize.patch"
    sed -i '/define Build\/Compile\/smartdns-ui/,/endef/s/CC=\$(TARGET_CC)/CC="\$(TARGET_CC_NOCACHE)"/' "$SMARTDNS_DIR/Makefile"

    echo "正在更新 luci-app-smartdns..."
    rm -rf "$LUCI_APP_SMARTDNS_DIR"
    git clone --depth=1 "$LUCI_APP_SMARTDNS_REPO" "$LUCI_APP_SMARTDNS_DIR"
}
# 定义更新Smartdns的函数：
# 1. 设置smartdns和luci-app-smartdns的仓库地址和目录
# 2. 打印更新smartdns的信息
# 3. 删除旧目录并克隆新的smartdns源码
# 4. 安装优化补丁
# 5. 修改Makefile中的编译命令（使用不缓存的编译器）
# 6. 打印更新luci-app-smartdns的信息
# 7. 删除旧目录并克隆新的luci-app-smartdns源码

# 更新Diskman
update_diskman() {
    local path="$BUILD_DIR/feeds/luci/applications/luci-app-diskman"
    if [ -d "$path" ]; then
        cd "$BUILD_DIR/feeds/luci/applications" || return # 显式路径避免歧义
        \rm -rf "luci-app-diskman"                        # 直接删除目标目录

        git clone --filter=blob:none --no-checkout https://github.com/lisaac/luci-app-diskman.git diskman || return
        cd diskman || return

        git sparse-checkout init --cone
        git sparse-checkout set applications/luci-app-diskman || return # 错误处理

        git checkout --quiet # 静默检出避免冗余输出

        mv applications/luci-app-diskman ../luci-app-diskman || return # 添加错误检查
        cd .. || return
        \rm -rf diskman
        cd "$BUILD_DIR"

        sed -i 's/fs-ntfs /fs-ntfs3 /g' "$path/Makefile"
        sed -i '/ntfs-3g-utils /d' "$path/Makefile"
    fi
}
# 定义更新Diskman的函数：
# 如果luci-app-diskman目录存在：
# 1. 进入applications目录
# 2. 删除luci-app-diskman目录
# 3. 克隆luci-app-diskman仓库（不下载文件内容）
# 4. 进入克隆的目录
# 5. 初始化稀疏检出
# 6. 设置只检出applications/luci-app-diskman
# 7. 静默检出文件
# 8. 将luci-app-diskman移动到上级目录
# 9. 返回上级目录并删除临时目录
# 10. 返回构建目录
# 11. 修改Makefile：将fs-ntfs改为fs-ntfs3
# 12. 删除ntfs-3g-utils

# 添加Quickfile
add_quickfile() {
    local repo_url="https://github.com/sbwml/luci-app-quickfile.git"
    local target_dir="$BUILD_DIR/package/emortal/quickfile"
    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
    fi
    git clone --depth 1 "$repo_url" "$target_dir"

    local makefile_path="$target_dir/quickfile/Makefile"
    if [ -f "$makefile_path" ]; then
        sed -i '/\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-\$(ARCH_PACKAGES)/c\
\tif [ "\$(ARCH_PACKAGES)" = "x86_64" ]; then \\\
\t\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-x86_64 \$(1)\/usr\/bin\/quickfile; \\\
\telse \\\
\t\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-aarch64_generic \$(1)\/usr\/bin\/quickfile; \\\
\tfi' "$makefile_path"
    fi
}
# 定义添加Quickfile的函数：
# 1. 设置仓库地址和目标目录
# 2. 如果目标目录存在则删除
# 3. 克隆仓库
# 4. 如果Makefile存在：
#    a. 修改安装部分：根据架构选择安装不同的二进制文件
#       - x86_64架构安装quickfile-x86_64
#       - 其他架构安装quickfile-aarch64_generic

# 设置Nginx默认配置
set_nginx_default_config() {
    local nginx_config_path="$BUILD_DIR/feeds/packages/net/nginx-util/files/nginx.config"
    if [ -f "$nginx_config_path" ]; then
        # 使用 cat 和 heredoc 覆盖写入 nginx.config 文件
        cat > "$nginx_config_path" <<EOF
config main 'global'
        option uci_enable 'true'

config server '_lan'
        list listen '443 ssl default_server'
        list listen '[::]:443 ssl default_server'
        option server_name '_lan'
        list include 'restrict_locally'
        list include 'conf.d/*.locations'
        option uci_manage_ssl 'self-signed'
        option ssl_certificate '/etc/nginx/conf.d/_lan.crt'
        option ssl_certificate_key '/etc/nginx/conf.d/_lan.key'
        option ssl_session_cache 'shared:SSL:32k'
        option ssl_session_timeout '64m'
        option access_log 'off; # logd openwrt'

config server 'http_only'
        list listen '80'
        list listen '[::]:80'
        option server_name 'http_only'
        list include 'conf.d/*.locations'
        option access_log 'off; # logd openwrt'
EOF
    fi

    local nginx_template="$BUILD_DIR/feeds/packages/net/nginx-util/files/uci.conf.template"
    if [ -f "$nginx_template" ]; then
        # 检查是否已存在配置，避免重复添加
        if ! grep -q "client_body_in_file_only clean;" "$nginx_template"; then
            sed -i "/client_max_body_size 128M;/a\\
\tclient_body_in_file_only clean;\\
\tclient_body_temp_path /mnt/tmp;" "$nginx_template"
        fi
    fi
}
# 定义设置Nginx默认配置的函数：
# 1. 如果nginx.config文件存在：
#    a. 使用heredoc覆盖文件内容，设置：
#       - 全局启用UCI配置
#       - _lan服务器：监听443端口（SSL），使用自签名证书，包含位置配置
#       - http_only服务器：监听80端口，包含位置配置
# 2. 如果uci.conf.template文件存在：
#    a. 如果还没有client_body_in_file_only配置：
#       - 在client_max_body_size 128M;后添加两行：
#         - client_body_in_file_only clean;（将请求体保存到文件）
#         - client_body_temp_path /mnt/tmp;（设置临时文件路径）

# 更新uWSGI限制
update_uwsgi_limit_as() {
    # 更新 uwsgi 的 limit-as 配置，将其值更改为 8192
    local cgi_io_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-cgi_io.ini"
    local webui_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini"

    if [ -f "$cgi_io_ini" ]; then
        # 将 luci-cgi_io.ini 文件中的 limit-as 值更新为 8192
        sed -i 's/^limit-as = .*/limit-as = 8192/g' "$cgi_io_ini"
    fi

    if [ -f "$webui_ini" ]; then
        # 将 luci-webui.ini 文件中的 limit-as 值更新为 8192
        sed -i 's/^limit-as = .*/limit-as = 8192/g' "$webui_ini"
    fi
}
# 定义更新uWSGI限制的函数：
# 1. 设置两个uWSGI配置文件的路径
# 2. 如果luci-cgi_io.ini存在，将limit-as值改为8192
# 3. 如果luci-webui.ini存在，将limit-as值改为8192
# limit-as是uWSGI的地址空间限制（单位为MB），8192MB=8GB

# 移除调整过的包
remove_tweaked_packages() {
    local target_mk="$BUILD_DIR/include/target.mk"
    if [ -f "$target_mk" ]; then
        # 检查目标行是否未被注释
        if grep -q "^DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)" "$target_mk"; then
            # 如果未被注释，则添加注释
            sed -i 's/DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/# DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/g' "$target_mk"
        fi
    fi
}
# 定义移除调整过的包的函数：
# 如果target.mk文件存在：
# 如果DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)行未被注释：
# 将其注释掉（移除tweak包）

# 更新Argon主题
update_argon() {
    local repo_url="https://github.com/jjm2473/luci-theme-argon.git"
    local dst_theme_path="$BUILD_DIR/feeds/luci/themes/luci-theme-argon"
    local tmp_dir=$(mktemp -d)

    echo "正在更新 argon 主题..."

    git clone --depth 1 "$repo_url" "$tmp_dir"

    rm -rf "$dst_theme_path"
    rm -rf "$tmp_dir/.git"
    mv "$tmp_dir" "$dst_theme_path"

    echo "luci-theme-argon 更新完成"
    echo "Argon 更新完毕。"
}
# 定义更新Argon主题的函数：
# 1. 设置仓库地址和目标主题路径
# 2. 创建临时目录
# 3. 打印更新信息
# 4. 克隆仓库到临时目录
# 5. 删除旧主题目录
# 6. 删除临时目录的.git文件夹
# 7. 将临时目录移动到目标路径
# 8. 打印完成信息

# 主函数
main() {
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    remove_unwanted_packages
    remove_tweaked_packages
    update_homeproxy
    fix_default_set
    fix_miniupnpd
    update_golang
    change_dnsmasq2full
    fix_mk_def_depends
    add_wifi_default_set
    update_default_lan_addr
    remove_something_nss_kmod
    update_affinity_script
    update_ath11k_fw
    # fix_mkpkg_format_invalid
    change_cpuusage
    update_tcping
    add_ax6600_led
    set_custom_task
    apply_passwall_tweaks
    install_opkg_distfeeds
    update_nss_pbuf_performance
    set_build_signature
    update_nss_diag
    update_menu_location
    fix_compile_coremark
    update_dnsmasq_conf
    add_backup_info_to_sysupgrade
    update_mosdns_deconfig
    fix_quickstart
    update_oaf_deconfig
    add_timecontrol
    add_gecoosac
    add_quickfile
    update_lucky
    fix_rust_compile_error
    update_smartdns
    update_diskman
    set_nginx_default_config
    update_uwsgi_limit_as
    update_argon
    install_feeds
    apply_hash_fixes # 调用哈希修正函数
    support_fw4_adg
    update_script_priority
    fix_easytier
    update_geoip
    update_package "runc" "releases" "v1.2.6"
    update_package "containerd" "releases" "v1.7.27"
    update_package "docker" "tags" "v28.2.2"
    update_package "dockerd" "releases" "v28.2.2"
}

main "$@"