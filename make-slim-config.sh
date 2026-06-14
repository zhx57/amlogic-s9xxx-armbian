#!/bin/bash
# 生成精简版 7.0 内核配置
# 策略：用 stable/config-6.18 做 base → olddefconfig 迁移到 7.0 → 砍掉非必要外设模块 + 关掉调试

set -e

KERNEL_DIR="/workspace/compile-kernel/kernel/linux-7.0.y"
BASE_CFG="/workspace/compile-kernel/tools/config/ophub-config/kernel-config/release/stable/config-6.18"
TARGET_CFG="${KERNEL_DIR}/.config"

cd "$KERNEL_DIR"
echo "=== 清理旧产物 ==="
rm -f .config
make -s mrproper 2>/dev/null || true

echo "=== 拷贝 stable/config-6.18 作为基础 ==="
cp -f "$BASE_CFG" "$TARGET_CFG"

echo "=== 批量精简：关掉非必要的外围模块（把 =m 改成 =n，保留 core 类）==="
# 保留 core 的关键字段：保留 =y 和 =m 的核心模块
# 策略：先全部 =m → =n，然后把需要的模块重新开启

# 列出需要保留为 =m 或 =y 的选项（不匹配这些的 =m 选项都会被 =n）
KEEP_PATTERNS=(
    # 核心架构
    "^CONFIG_ARM64"
    "^CONFIG_PM"
    "^CONFIG_CPU"
    "^CONFIG_SMP"
    "^CONFIG_NUMA"
    "^CONFIG_MEMORY"
    "^CONFIG_HAVE"
    "^CONFIG_GENERIC"
    "^CONFIG_ARCH"
    "^CONFIG_KERNEL"
    "^CONFIG_STACK"
    "^CONFIG_COMPAT"

    # SoC 平台核心（amlogic/rockchip/allwinner）
    "^CONFIG_ARCH_MESON"
    "^CONFIG_ARCH_ROCKCHIP"
    "^CONFIG_ARCH_SUNXI"
    "^CONFIG_MFD_AXP"
    "^CONFIG_PINCTRL_MESON"
    "^CONFIG_PINCTRL_ROCKCHIP"
    "^CONFIG_PINCTRL_SUNXI"
    "^CONFIG_CLK_MESON"
    "^CONFIG_CLK_ROCKCHIP"
    "^CONFIG_CLK_SUNXI"
    "^CONFIG_RESET_MESON"
    "^CONFIG_RESET_ROCKCHIP"
    "^CONFIG_RESET_SUNXI"
    "^CONFIG_MESON_GX_SOCINFO"
    "^CONFIG_MESON_GX_PM_DOMAINS"
    "^CONFIG_RK808"
    "^CONFIG_RK8XX"

    # 存储核心（block/MMC/SD/eMMC/NVMe/SATA/USB storage）
    "^CONFIG_BLOCK"
    "^CONFIG_MMC"
    "^CONFIG_MMC_BLOCK"
    "^CONFIG_MMC_CQHCI"
    "^CONFIG_MMC_DW"
    "^CONFIG_MMC_DW_ROCKCHIP"
    "^CONFIG_MMC_MESON_GX"
    "^CONFIG_MMC_SUNXI"
    "^CONFIG_NVME"
    "^CONFIG_NVME_CORE"
    "^CONFIG_SCSI"
    "^CONFIG_BLK_DEV_SD"
    "^CONFIG_BLK_DEV_NVME"
    "^CONFIG_BLK_DEV_LOOP"
    "^CONFIG_BLK_DEV_CRYPTO"

    # 文件系统
    "^CONFIG_EXT4"
    "^CONFIG_BTRFS"
    "^CONFIG_XFS"
    "^CONFIG_F2FS"
    "^CONFIG_VFAT"
    "^CONFIG_NTFS"
    "^CONFIG_EXFAT"
    "^CONFIG_OVERLAY_FS"
    "^CONFIG_TMPFS"
    "^CONFIG_PROC_FS"
    "^CONFIG_SYSFS"
    "^CONFIG_CGROUP"
    "^CONFIG_AUTOFS"

    # 网络核心
    "^CONFIG_NET"
    "^CONFIG_INET"
    "^CONFIG_IPV6"
    "^CONFIG_NETFILTER"
    "^CONFIG_IP_NF"
    "^CONFIG_NF_NAT"
    "^CONFIG_NET_ACT"
    "^CONFIG_NET_SCH"
    "^CONFIG_NETDEV"
    "^CONFIG_ETHERNET"
    "^CONFIG_NET_VENDOR_AMLOGIC"
    "^CONFIG_NET_VENDOR_ROCKCHIP"
    "^CONFIG_NET_VENDOR_REALTEK"
    "^CONFIG_R8169"
    "^CONFIG_STMMAC_ETH"
    "^CONFIG_DWMAC_GENERIC"
    "^CONFIG_DWMAC_MESON"
    "^CONFIG_DWMAC_ROCKCHIP"
    "^CONFIG_DWMAC_SUNXI"

    # USB 核心 + host controller（外设类关闭）
    "^CONFIG_USB"
    "^CONFIG_USB_ANNOUNCE"
    "^CONFIG_USB_OHCI"
    "^CONFIG_USB_EHCI"
    "^CONFIG_USB_XHCI"
    "^CONFIG_USB_XHCI_PLATFORM"
    "^CONFIG_USB_XHCI_PCI"
    "^CONFIG_USB_DWC3"
    "^CONFIG_USB_STORAGE"
    "^CONFIG_USB_UAS"

    # I2C / SPI 核心（外设类关闭）
    "^CONFIG_I2C"
    "^CONFIG_I2C_CHARDEV"
    "^CONFIG_I2C_DESIGNWARE"
    "^CONFIG_I2C_DESIGNWARE_PLATFORM"
    "^CONFIG_I2C_DESIGNWARE_SLAVE"
    "^CONFIG_SPI"
    "^CONFIG_SPI_MASTER"
    "^CONFIG_SPI_ROCKCHIP"
    "^CONFIG_SPI_AMLOGIC"

    # 串口/UART/控制台
    "^CONFIG_SERIAL_8250"
    "^CONFIG_SERIAL_AMBA_PL011"
    "^CONFIG_SERIAL_MESON"
    "^CONFIG_SERIAL_SUNPLUS"
    "^CONFIG_TTY"
    "^CONFIG_UNIX98_PTYS"

    # GPIO / IRQ / PINCTRL
    "^CONFIG_GPIOLIB"
    "^CONFIG_GPIO_SYSFS"
    "^CONFIG_IRQCHIP"
    "^CONFIG_PINCTRL"

    # 显示/帧缓冲（HDMI/DP）
    "^CONFIG_DRM"
    "^CONFIG_DRM_PANEL"
    "^CONFIG_DRM_PANEL_BRIDGE"
    "^CONFIG_DRM_BRIDGE"
    "^CONFIG_DRM_MESON"
    "^CONFIG_DRM_ROCKCHIP"
    "^CONFIG_DRM_SUN4I"
    "^CONFIG_FB"

    # crypto 核心
    "^CONFIG_CRYPTO"
    "^CONFIG_CRYPTO_AES"
    "^CONFIG_CRYPTO_SHA"
    "^CONFIG_CRYPTO_SHA256"
    "^CONFIG_CRYPTO_SHA512"

    # 内核基础选项
    "^CONFIG_PRINTK"
    "^CONFIG_BINFMT_ELF"
    "^CONFIG_BINFMT_SCRIPT"
    "^CONFIG_MODULES"
    "^CONFIG_MODULE_UNLOAD"
    "^CONFIG_MODULES_TREE_LOOKUP"
    "^CONFIG_MODVERSIONS"
    "^CONFIG_MODULE_SRCVERSION_ALL"
    "^CONFIG_KALLSYMS"
    "^CONFIG_KALLSYMS_ALL"
    "^CONFIG_BPF"
    "^CONFIG_BPF_SYSCALL"
    "^CONFIG_EBPF"
    "^CONFIG_KPROBES"
    "^CONFIG_TRACING_SUPPORT"
)

# 先统计
BEFORE=$(grep -c '=m$' "$TARGET_CFG")
echo "  精简前 =m 数: ${BEFORE}"

# 构造 grep 命令：匹配任何需要保留的选项
KEEP_GREP=$(printf "%s|" "${KEEP_PATTERNS[@]}")
KEEP_GREP="${KEEP_GREP%|}"

# 临时文件
TMP=$(mktemp)
while IFS= read -r line; do
    # 非 =m 的行原样保留
    if [[ ! "$line" =~ =m$ ]]; then
        echo "$line" >> "$TMP"
        continue
    fi
    # 提取选项名
    OPTNAME=$(echo "$line" | sed 's/^CONFIG_//;s/=m$//')
    # 检查是否匹配保留模式
    if echo "$line" | grep -qE "$KEEP_GREP"; then
        echo "$line" >> "$TMP"
    else
        echo "# CONFIG_${OPTNAME} is not set" >> "$TMP"
    fi
done < "$TARGET_CFG"
mv -f "$TMP" "$TARGET_CFG"

AFTER=$(grep -c '=m$' "$TARGET_CFG")
echo "  精简后 =m 数: ${AFTER}"
echo "  砍掉: $(( BEFORE - AFTER )) 个模块"

# 关闭所有调试选项（DEBUG_INFO / DEBUG_INFO_BTF / FTRACE / KASAN / UBSAN / LOCKDEP 等）
echo "=== 关闭调试类选项 ==="
DEBUG_OPTS=(
    DEBUG_INFO DEBUG_INFO_DWARF5 DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
    DEBUG_INFO_BTF DEBUG_INFO_BTF_MODULES DEBUG_INFO_REDUCED
    DEBUG_INFO_COMPRESSED_ZLIB DEBUG_INFO_COMPRESSED_NONE
    KASAN KASAN_GENERIC KASAN_OUTLINE KASAN_INLINE
    UBSAN UBSAN_TRAP UBSAN_BOUNDS UBSAN_LOCAL_BOUNDS
    UBSAN_SHIFT UBSAN_DIV_ZERO UBSAN_UNREACHABLE UBSAN_OBJECT_SIZE
    UBSAN_BOOL UBSAN_ENUM UBSAN_ALIGNMENT
    LOCKDEP LOCKDEP_SUPPORT
    FTRACE FUNCTION_TRACER FUNCTION_GRAPH_TRACER
    TRACING_TRACER PERF_EVENTS PM_SLEEP_DEBUG
    KGDB KCOV KCSAN
    DEBUG_KERNEL DEBUG_MM_RU
    DEBUG_PREEMPT DEBUG_RT_MUTEXES
    DEBUG_WW_MUTEX_SLOWPATH DEBUG_LOCK_ALLOC
    PROVE_LOCKING DEBUG_ATOMIC_SLEEP
    DEBUG_LIST DEBUG_PLIST
    DEBUG_BUGVERBOSE
    DEBUG_MEMORY_INIT DEBUG_PAGE_REF TRACEPOINTS
    DEBUG_OBJECTS DEBUG_OBJECTS_FREE DEBUG_OBJECTS_TIMERS
    DEBUG_OBJECTS_WORK DEBUG_OBJECTS_RCU_HEAD DEBUG_OBJECTS_PERCPU_COUNTER
    DEBUG_OBJECTS_ENABLE_DEFAULT
    DEBUG_SLAB DEBUG_SLUB_DEBUG SLUB_DEBUG
    DEBUG_SPINLOCK DEBUG_MUTEXES DEBUG_LOCKING_API_SELFTESTS
    DEBUG_STACK_USAGE DEBUG_VM DEBUG_VM_PGFLAGS
    DEBUG_MEMCG DEBUG_PER_CPU_MAPS
    DEBUG_SHIRQ DEBUG_DEVRES
    DEBUG_KOBJECT_DEBUG
    TEST
)
for opt in "${DEBUG_OPTS[@]}"; do
    # 先清掉 =y，再加 "is not set"
    if grep -qE "^CONFIG_${opt}=(y|m)$" "$TARGET_CFG"; then
        sed -i "s|^CONFIG_${opt}=[ym]|# CONFIG_${opt} is not set|" "$TARGET_CFG"
    fi
    # 确保没有 is not set 的项不重复写
done

# 迁移到 7.0（olddefconfig 会自动处理缺失的符号）
echo "=== make olddefconfig 迁移到 7.0 ==="
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig 2>&1 | tail -10

echo ""
echo "=== 最终统计 ==="
echo "  =y 数量: $(grep -c '=y$' "$TARGET_CFG")"
echo "  =m 数量: $(grep -c '=m$' "$TARGET_CFG")"
echo "  config 总行数: $(wc -l < "$TARGET_CFG")"
echo "  vmlinux 预计大小: ~15-20MB (无 debug 符号)"
echo "  Image 预计大小: ~8-12MB"
echo "  modules 预计: 总 ~30-50MB (几百个 ko)"
echo ""
echo "  配置文件: $TARGET_CFG"
echo "  OK - 可以开始构建"
