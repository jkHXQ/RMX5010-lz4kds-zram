# RMX5010-lz4kds-zram

在 realme RMX5010（GT7 Pro，内核 `6.6.89-android15-8`）上，为厂商 `oplus_bsp_hybridswap_zram`
驱动接入 **LZ4KD + SDDC** 压缩的 KernelSU 模块与适配源码。

> **本项目是适配与集成层，不包含任何原创压缩算法，也不是 zram 驱动本体。**
> 所有算法与核心实现均来自上游开源项目，归属见下一节。

---

## 1. 来源与致谢（重要）

本项目在 GPL 生态内做集成，以下作者与项目的成果是全部基础：

| 组件 | 原作者 / 项目 | 许可证 | 本仓库位置 |
|---|---|---|---|
| zram 驱动骨架、hybridswap core/swapd、回写、memcg 策略 | OPPO / realme 原厂 `oplus_bsp_hybridswap_zram` | Dual BSD/GPL（见各源码头） | `src/` |
| LZ4KD 编解码算法（编码、解码、delta 编码、NEON） | **华为 HiSilicon**（LZ4K / LZ4KD） | 随源码声明 | `src/lz4kd/` |
| SDDC 相似页索引、引用对象、alias/delta、生命周期状态机 | **Crystal HybridSwap**（Wcoom，`drivers/crystalfrostwork/crystal_hybridswap`） | GPL-2.0-or-later | `src/sddc/crystal_sddc.c`、`src/sddc/crystal_sddc.h` |
| SDDC 字节级编解码适配 | Crystal HybridSwap | GPL-2.0-or-later | `src/sddc/crystal_sddc_codec.c` |
| 适配层新增代码（`lz4kd`/`lz4kds` 后端、zram 接点、兼容层、自检、参数、脚本、WebUI） | **codxe**（本仓库） | GPL-2.0 | 见下方“本仓库新增” |

**本仓库新增**：

- `src/zcomp.c`、`src/zcomp.h`：私有压缩后端 `lz4kd` 与 `lz4kds`
- `src/zram_drv.c`、`src/zram_drv.h`：SDDC 读写/free/reset/disksize 接点、开机自检、容量与算法参数
- `src/crystal_sddc_compat.h`：`zs_*` → `zs_*_oplus` 兼容层
- `module/`：KernelSU 模块（preinit 抢载、配置脚本、WebUI）

上游链接：

- Crystal HybridSwap：<https://github.com/Wcoom/oneplus_sm8750_kernel>（`drivers/crystalfrostwork/crystal_hybridswap`）
- 设备内核源码参考：<https://github.com/whitewhale0612/android_kernel_common_oneplus_sm8750-C16>

> 如上游作者对上述归属描述有异议，请以对方声明为准；发现标注错误欢迎提 issue 更正。

---

## 2. 原理（一句话版）

- `lz4kd`：纯华为 LZ4KD 单页压缩流；
- `lz4kds`：在 LZ4KD 之上，用 SDDC 把“内容相同的页”合并为 alias、把“只有少量差异的页”存成 delta；
- 驱动骨架、回写、内存策略全部沿用原厂，本项目只在 `zcomp` / `zram_drv` 上加接点。

---

## 3. 兼容性

| 范围 | 可行性 |
|---|---|
| 同厂家 + 同 BSP 小版本 | 可用，一份 KO 覆盖多机型，需逐机型跑符号闸门 |
| 同厂家 + 跨小版本（6.6.89 → 6.6.x） | 需重新对齐 CRC/符号并重跑自检 |
| 跨大版本 / 跨厂家 | 不支持（私有驱动结构与符号集不同） |

实测环境：realme RMX5010，`6.6.89-android15-8-o-*`，16 GB RAM，Android 15。

---

## 4. 安装

1. 已解锁 Bootloader 并安装 KernelSU；
2. KernelSU Manager 里安装 `dist/lz4kds-zram-v1.0.zip`；
3. 重启。模块通过 KSU `preinit` 在 SELinux 策略加载前抢载 KO。

模块 id：`lz4kds`。默认配置：`zram_size_mb=9216`、`zram_algo=lz4kds`。

回退：KernelSU Manager 禁用/卸载模块后重启，系统自动回到原厂 zram。
卸载脚本会清理 `/metadata/vold/ksu/preinit/lz4kds` 同步副本。

---

## 5. 配置

两种方式，改完都可以立即尝试热切换（swapoff → reset → 设置 → mkswap → swapon），
内存不足时自动退化为“重启生效”。

**方式一：WebUI**（KernelSU Manager → 模块 → lz4kds → 打开）
容量输入 + 快捷 8/16/24 GB，算法分段选择，实时显示 alias/delta/节省/解码失败/自检。

**方式二：命令行**

```sh
sh /data/adb/modules/lz4kds/zram.sh 9216 lz4kds   # 容量 + 算法
sh /data/adb/modules/lz4kds/zram.sh algo zstd     # 只换算法
sh /data/adb/modules/lz4kds/zram.sh show          # 查看配置与运行状态
sh /data/adb/modules/lz4kds/zram.sh off           # 恢复厂商默认
```

持久配置位于 `module/preinit/preinit.conf`：

```
insmod oplus_bsp_zsmalloc.ko
insmod oplus_bsp_hybridswap_zram.ko zram_size_mb=9216 zram_algo=lz4kds
```

| 参数 | 取值 | 说明 |
|---|---|---|
| `zram_size_mb` | 512–65536，`0` = 厂商值 | zram0 逻辑容量（MiB），填多少就是多少，超过 2×RAM 自动钳制 |
| `zram_algo` | `lz4kds` / `lz4kd` / `lz4` / `zstd` / `lzo` / `lzo-rle` / `off` | 新设备默认算法，`off` 交还厂商默认 |

> 只有 `lz4kds` 会启用 SDDC；其它算法为普通单页压缩。

---

## 6. 验证

```sh
cat /sys/block/zram0/disksize
cat /sys/block/zram0/comp_algorithm
cat /sys/block/zram0/sddc_stat          # enabled / aliases / deltas / saved_bytes / decode_failures
cat /sys/module/oplus_bsp_hybridswap_zram/parameters/selftest_codec
cat /sys/module/oplus_bsp_hybridswap_zram/parameters/selftest_io
```

自检语义：

- `selftest_codec=0`：普通流 + delta 流往返通过（否则模块拒绝加载，回退原厂）；
- `selftest_io=0`：设备初始化后真实写入/读回/释放通过（否则仅关闭 SDDC，保留普通压缩）。

实测（单机，非基准）：`lz4kds` 压缩比约 5.0x（1.285 GB → 255 MB），`decode_failures` 0。
样本有限，不构成性能承诺。

---

## 7. 构建

`src/` 需放回厂商内核树的对应位置：

```
vendor/oplus/kernel/mm/hybridswap_zram/
```

然后在该内核树根目录执行（AArch64，LLVM）：

```sh
make -C <kernel-tree> M=vendor/oplus/kernel/mm/hybridswap_zram \
     ARCH=arm64 LLVM=1 KBUILD_MODPOST_WARN=1 modules
```

加载前请做两道闸门（脚本思路见 `docs/LZ4KDS-适配层说明.md`）：

1. **符号闸门**：模块导入符号必须全部存在于设备 `/proc/kallsyms`；
2. **CRC 对齐**：`__versions` 与导出 `__crc_*` 与原厂 KO 逐项对齐，差异必须为 0。

---

## 8. 仓库结构

```
src/      驱动源码（已剔除 .o/.ko 等编译产物）
module/   KernelSU 模块模板（module.prop、service.sh、zram.sh、preinit/、webroot/，含预编译 KO）
dist/     lz4kds-zram-v1.0.zip（可直接安装）
docs/     LZ4KDS 适配层说明（归属、边界、降级、风险）
LICENSE   GPL-2.0
```

---

## 9. 已知降级（相对上游 Crystal 实现）

| 项 | 上游 | 本适配层 | 影响 |
|---|---|---|---|
| per-memcg 记账 | 按 memcg 统计 | no-op | 厂商 memcg 统计不含 SDDC 引用；不影响数据正确性 |
| size-class 判定 | `zs_lookup_class_index` | 按字节近似 | 可能放过极少数低收益 delta |
| native writeback | delta/alias 原样落盘 | 依赖厂商“读回整页再写盘” | 功能正确，无 SDDC 专属优化 |
| prefetch / batch-in / recompress | 有 SDDC 分支 | 未适配 | 这些场景按普通流处理 |

---

## 10. 风险与免责

- 本项目修改内核内存管理路径，**可能导致卡顿、数据损坏或无法开机**；
- 仅在已解锁且装有 KernelSU 的设备上使用，务必保留原厂 KO 与回退手段；
- 首次使用前建议记录：原厂 `zram.ko`、`vermagic`、当前 `disksize`；
- 本项目不提供任何担保，仅供学习与研究，风险自负；
- 请遵守所在地法律法规与设备厂商条款。

---

## 11. 许可证

本仓库整体按 **GPL-2.0** 发布（见 `LICENSE`）。
其中厂商驱动、LZ4KD、Crystal SDDC 代码的版权与许可证以各自源码头声明为准；
本仓库对其只做适配与集成，不改变其原有授权。

---

适配与集成：**codxe**
