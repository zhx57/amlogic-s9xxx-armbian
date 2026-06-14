#!/bin/bash
set -euo pipefail

# =========================== 配置 ===========================
KERNEL_DIR="/workspace/compile-kernel/kernel/linux-7.0.y"
OUTPUT_DIR="/workspace/compile-kernel/output"
CONFIG_SRC="/workspace/compile-kernel/tools/config/config-7.0"
LOCALVERSION="-ophub"
JOBS=$(( $(nproc) ))
ARCH=arm64
CROSS_COMPILE="aarch64-linux-gnu-"

mkdir -p "${OUTPUT_DIR}"/{boot,modules,header,libc_headers,dtb/{allwinner,amlogic,rockchip},deb-7.0.12,7.0.12}

cd "${KERNEL_DIR}"

echo "=====  1/7 拷贝 config-6.18 作为 config-7.0 ====="
cp -f "${CONFIG_SRC}" .config
# 清除签名（与 armbian_compile_kernel.sh 保持一致）
sed -i "s|CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"\"|" .config
echo "  config 行数: $(wc -l < .config)"

echo ""
echo "=====  2/7 make olddefconfig（将 6.18 配置迁移至 7.0） ====="
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} olddefconfig 2>&1 | tail -20
echo "  新 config 行数: $(wc -l < .config)"

echo ""
echo "=====  3/7 开始构建内核（Image / modules / dtbs）====="
START=$(date +%s)
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
     -j${JOBS} --silent \
     Image modules dtbs 2>&1 \
  | tail -30
END=$(date +%s)
echo "  内核构建耗时: $(( (END - START) / 60 )) 分 $(( (END - START) % 60 )) 秒"

echo ""
echo "=====  4/7 安装 modules 到 staging ====="
INSTALL_MOD_PATH="${OUTPUT_DIR}/modules"
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
     INSTALL_MOD_PATH="${INSTALL_MOD_PATH}" \
     --silent modules_install 2>&1 | tail -10

# 读出真实版本号（带 LOCALVERSION）
REAL_VER=$(ls -1 "${INSTALL_MOD_PATH}/lib/modules/" 2>/dev/null | head -1)
echo "  真实内核版本: ${REAL_VER}"

echo ""
echo "=====  5/7 headers + libc headers ====="
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
     --silent headers_install INSTALL_HDR_PATH="${OUTPUT_DIR}/libc_headers" 2>&1 | tail -5

echo ""
echo "=====  6/7 复制 boot 产物 ====="
BOOT="${OUTPUT_DIR}/boot"
cp -f arch/arm64/boot/Image "${BOOT}/vmlinuz-${REAL_VER}"
cp -f .config "${BOOT}/config-${REAL_VER}"
cp -f System.map "${BOOT}/System.map-${REAL_VER}"
echo "  vmlinuz 大小: $(du -h ${BOOT}/vmlinuz-${REAL_VER} | cut -f1)"

echo ""
echo "=====  7/7 生成 deb 包（linux-image / linux-headers / linux-libc-dev / dtbs） ====="
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j${JOBS} \
     bindeb-pkg \
     KDEB_COMPRESS=xz KDEB_SOURCENAME=linux-upstream LOCALVERSION=${LOCALVERSION} 2>&1 | tail -20

# bindeb-pkg 把产物放在 ../
ls -lh ../*.deb 2>/dev/null || true
cp -f ../*.deb "${OUTPUT_DIR}/deb-7.0.12/" 2>/dev/null || true

# ============= 额外：收集 DTB =============
echo ""
echo "=====  收集 DTB（allwinner / amlogic / rockchip） ====="
DTBSRC="arch/arm64/boot/dts"
for SOC in allwinner amlogic rockchip; do
  find "${DTBSRC}/${SOC}" -name '*.dtb' -exec cp -f {} "${OUTPUT_DIR}/dtb/${SOC}/" \; 2>/dev/null
  COUNT=$(ls "${OUTPUT_DIR}/dtb/${SOC}/" 2>/dev/null | wc -l)
  echo "  ${SOC}: ${COUNT} dtbs"
  if [ "$COUNT" -gt 0 ]; then
    # 如果有 overlay，复制一份
    if [ -d "${DTBSRC}/${SOC}/overlay" ]; then
      mkdir -p "${OUTPUT_DIR}/dtb/${SOC}/overlay"
      cp -f "${DTBSRC}/${SOC}/"*.dtbo "${OUTPUT_DIR}/dtb/${SOC}/overlay/" 2>/dev/null || true
    fi
    cd "${OUTPUT_DIR}/dtb/${SOC}/"
    tar -czf "dtb-${SOC}-${REAL_VER}.tar.gz" *.dtb 2>/dev/null
    mv -f "dtb-${SOC}-${REAL_VER}.tar.gz" "${OUTPUT_DIR}/7.0.12/"
    cd "${KERNEL_DIR}"
  fi
done

# ============= 打包 boot / modules / header =============
echo ""
echo "=====  打包 tarball：boot / modules / dtb / 汇总 ====="
cd "${OUTPUT_DIR}/boot"
tar -czf "boot-${REAL_VER}.tar.gz" vmlinuz-${REAL_VER} config-${REAL_VER} System.map-${REAL_VER}
mv -f "boot-${REAL_VER}.tar.gz" "${OUTPUT_DIR}/7.0.12/"

cd "${OUTPUT_DIR}/modules/lib/modules"
tar -czf "modules-${REAL_VER}.tar.gz" ${REAL_VER}/
mv -f "modules-${REAL_VER}.tar.gz" "${OUTPUT_DIR}/7.0.12/"

# header：复制 Makefile/include/scripts 等
HEADERS_DIR="${OUTPUT_DIR}/header"
mkdir -p "${HEADERS_DIR}"
cd "${KERNEL_DIR}"
cp -a Makefile Module.symvers "${HEADERS_DIR}/"
cp -a include scripts "${HEADERS_DIR}/" 2>/dev/null || true
cp -a arch/arm64/include "${HEADERS_DIR}/arch/arm64/" 2>/dev/null || true
cd "${HEADERS_DIR}"
tar -czf "header-${REAL_VER}.tar.gz" .
mv -f "header-${REAL_VER}.tar.gz" "${OUTPUT_DIR}/7.0.12/"

# 汇总一个大 tarball
cd "${OUTPUT_DIR}"
tar -czf "7.0.12.tar.gz" 7.0.12/ deb-7.0.12/

echo ""
echo "==============================================="
echo "  全部产物目录："
echo "    ${OUTPUT_DIR}/boot/          (Image, System.map, config)"
echo "    ${OUTPUT_DIR}/modules/       (已安装的 ko 文件)"
echo "    ${OUTPUT_DIR}/dtb/           (allwinner/amlogic/rockchip)"
echo "    ${OUTPUT_DIR}/header/        (内核头文件)"
echo "    ${OUTPUT_DIR}/libc_headers/  (用户态 libc 头文件)"
echo "    ${OUTPUT_DIR}/7.0.12/        (tarball 合集)"
echo "    ${OUTPUT_DIR}/deb-7.0.12/    (deb 包)"
echo "    ${OUTPUT_DIR}/7.0.12.tar.gz  (总打包)"
echo ""
echo "  产物清单:"
ls -lh "${OUTPUT_DIR}"/7.0.12/*.tar.gz "${OUTPUT_DIR}"/deb-7.0.12/*.deb 2>/dev/null
echo "==============================================="
echo ""
echo "  构建总耗时: $(( ( $(date +%s) - START ) / 60 )) 分钟"
