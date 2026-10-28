# LZ4KDS zram 适配层说明

> 面向对外发布。本文档说明本项目**做了什么、没做什么**，以及所有算法与代码的来源归属。
> 一句话定位：**本项目是适配与集成层，不是压缩算法实现，也不是 zram 驱动本体。**

---

## 1. 项目定位

在厂商（OPPO / realme）原厂 `oplus_bsp_hybridswap_zram` 驱动之上，以可回退的方式接入
**LZ4KD 压缩 + SDDC 相似页/增量压缩**，通过 KernelSU 模块在开机最早期抢占加载。

设计目标按优先级：

1. **不破坏原厂内存策略**：`fg_protect`、`zram_opt`、`exit_mm_optimize`、hybridswap 回写照旧可用；
2. **随时可回退**：任一环节失败，系统回到原厂 zram，不影响开机；
3. **可配置**：容量与压缩算法由用户设定，不写死在代码里；
4. **可复现**：构建、校验、部署有脚本闸门。

---

## 2. 算法与代码来源（重要）

本项目的算法与核心实现**均非原创**，来源如下：

| 组件 | 来源 | 许可证 | 本项目中的位置 |
|---|---|---|---|
| zram 驱动骨架、hybridswap core/swapd、writeback、memcg 策略 | OPPO / realme 原厂 `oplus_bsp_hybridswap_zram` | Dual BSD/GPL（见源码头） | `vendor/oplus/kernel/mm/hybridswap_zram/` |
| LZ4KD 编解码算法 | 华为（HiSilicon）LZ4K / LZ4KD | 随源码声明 | `lz4kd/`（编码、解码、delta 编码、NEON） |
| SDDC（相似页索引、引用对象、alias/delta、生命周期） | **Crystal HybridSwap**（Wcoom，`drivers/crystalfrostwork/crystal_hybridswap`） | GPL-2.0-or-later | `sddc/crystal_sddc.c`、`sddc/crystal_sddc.h` |
| SDDC 字节级编解码适配 | Crystal HybridSwap | GPL-2.0-or-later | `sddc/crystal_sddc_codec.c` |
| 本适配层（新增代码） | 本项目 | GPL-2.0 | `zcomp.c` 后端、`zram_drv.c` 接点、`crystal_sddc_compat.h`、自检、参数、脚本 |

> 结论：**LZ4KD 算法来自华为，SDDC 设计来自 Crystal HybridSwap，驱动框架来自 OPPO/realme。**
> 本项目只做“把三者安全接起来”的工作。对外发布时请保留以上归属。

---

## 3. 工程贡献边界

### 3.1 本适配层完成的工作

| 项 | 说明 |
|---|---|
| 私有压缩后端 | 在厂商 `zcomp` 中新增 `lz4kd`（纯 LZ4KD）与 `lz4kds`（LZ4KD + SDDC delta），不注册到全局 crypto API，避免污染其他子系统 |
| 数据通路接点 | 在厂商 `zram_drv` 的写、读、free、recompress、reset、disksize 六条路径接入 SDDC 回调 |
| 兼容层 | `crystal_sddc_compat.h`：把 `zs_*` 映射到厂商的 `zs_*_oplus`，补齐日志与记账桩 |
| 启动自检 | `selftest_codec`（普通流 + delta 流往返）；`selftest_io`（初始化后真实写一页、读回比对、释放） |
| 失败回退 | codec 自检失败 → 拒绝加载，回退原厂；IO 自检失败 → 仅关闭 SDDC，保留普通 lz4kds；`lz4kds` 后端创建失败 → 自动降级到 `lz4` |
| 容量配置 | `zram_size_mb`：zram0 逻辑容量，填多少就是多少（512–65536 MiB，钳制到 2×RAM） |
| 算法配置 | `zram_algo`：新设备默认算法；`off` 交还厂商默认；厂商脚本写 `lz4` 时按“拒绝降级”处理 |
| 承载方式 | KernelSU 模块 `preinit`（SELinux 策略加载前）抢载，先 `zsmalloc` 后本模块，失败计入 bootcount 熔断 |
| 构建校验 | 符号闸门（导入符号与设备 `/proc/kallsyms` 全量比对）、CRC 全量对齐（`__versions` + 导出 `__crc_`）、vermagic 核对 |
| 配置工具 | `zram.sh`：一条命令设置容量/算法，自动写入 `preinit.conf` 并 `initrc refresh` |

### 3.2 明确不属于本项目的工作

- **没有实现任何压缩算法**（LZ4KD、delta 编码均为上游实现）；
- **没有设计 SDDC 的状态机、锁序、引用生命周期**（均为 Crystal HybridSwap 的设计）；
- **没有编写 zram 驱动本体、hybridswap、writeback、memcg 策略**（均为厂商代码）；
- **没有做逆向工程**，全部基于公开的 GPL 源码构建。

### 3.3 已知降级（与上游 Crystal 实现相比）

| 项 | 上游行为 | 本适配层 | 影响 |
|---|---|---|---|
| per-memcg 记账 | 按 memcg 统计压缩/回写字节 | 空实现（no-op） | 厂商侧 memcg 统计不包含 SDDC 引用记账；不影响数据正确性 |
| `zs_lookup_class_index` | 按 zsmalloc size class 判定收益 | 设备不导出该 API，退化为按字节比较 | 可能放过极少数“字节更小但同类大小”的 delta，收益略低 |
| native writeback | delta/alias 原样写入 ZMS 并跟踪引用 | 不支持，依赖厂商回写“读回整页再写盘” | 回写路径没有 SDDC 专属优化，但功能正确 |
| prefetch / batch-in / recompress | 有 SDDC 专项分支 | 厂商骨架无这些路径，未适配 | 这些场景下按普通流处理 |

---

## 4. 运行机制

```
开机
 └─ KSU preinit（SELinux 之前）
     ├─ insmod oplus_bsp_zsmalloc.ko      # 提供 zs_*_oplus 导出
     └─ insmod oplus_bsp_hybridswap_zram.ko [zram_size_mb=N] [zram_algo=X]
         ├─ codec 自检（失败 → 模块不加载，系统回退原厂 zram）
         ├─ 创建 zram0..N（默认算法 = zram_algo）
         └─ hybridswap 初始化
 └─ 厂商脚本配置 zram0
     ├─ comp_algorithm 写 lz4 → 被“拒绝降级”忽略，保持用户选择的算法
     └─ disksize 写入 → 若设了 zram_size_mb 则覆盖
 ├─ SDDC 管理器创建（仅当算法支持 delta）
 └─ IO 自检（失败 → 关闭 SDDC，保留普通压缩）
```

关键约束：

- `comp_algorithm` 与 `disksize` 只能在设备**未初始化**时写入，因此所有配置必须在启动脚本之前完成；
- 自检在真实设备初始化后、`swapon` 之前执行，不接触用户数据；
- 任一步失败都收敛到“原厂 zram”，不会导致无 swap 开机。

---

## 5. 配置

配置文件：`/data/adb/modules/lz4kds/preinit/preinit.conf`

```
insmod oplus_bsp_zsmalloc.ko
insmod oplus_bsp_hybridswap_zram.ko zram_size_mb=9216 zram_algo=lz4kds
```

| 参数 | 取值 | 说明 |
|---|---|---|
| `zram_size_mb` | 512–65536，0 = 厂商值 | zram0 逻辑容量（MiB），填多少就是多少 |
| `zram_algo` | `lz4kds` / `lz4kd` / `lz4` / `zstd` / `lzo` / `lzo-rle` / `off` | 新设备默认算法，`off` 交还厂商默认 |

修改后必须 `ksud initrc refresh` 并重启。

便捷工具：

```sh
sh /data/adb/modules/lz4kds/zram.sh 9216 lz4kds   # 容量 + 算法
sh /data/adb/modules/lz4kds/zram.sh algo zstd     # 只换算法
sh /data/adb/modules/lz4kds/zram.sh show          # 查看
sh /data/adb/modules/lz4kds/zram.sh off           # 恢复厂商默认
```

---

## 6. 实测数据（单机，非基准测试）

设备：realme RMX5010，内核 `6.6.89-android15-8`，16 GB RAM。

| 指标 | 纯 lz4kd | lz4kd + SDDC（lz4kds） |
|---|---|---|
| 压缩比（mm_stat） | 约 2.8x | 约 5.0x（1.285 GB → 255 MB） |
| alias / delta 槽 | — | 69k / 42k |
| `saved_bytes` | — | 约 204 MB |
| `decode_failures` | 0 | 0 |

说明：数据来自真实 swap 负载，样本有限，**不构成任何性能承诺**；不同负载、不同机型差异可能很大。

---

## 7. 兼容性范围

| 范围 | 可行性 |
|---|---|
| 同厂家 + 同小版本内核（同 BSP） | 可用；一份 KO 可覆盖多机型，需逐机型做符号闸门 |
| 同厂家 + 跨小版本（如 6.6.89 → 6.6.x） | 需重新对齐 CRC 与符号集，并重跑自检；本仓库提供脚本 |
| 同厂家 + 跨大版本 | 不支持（私有驱动结构与数据格式变化） |
| 跨厂家 | 不支持（私有驱动不同源，符号集不同） |

`vermagic`：Android GKI 的 `same_magic()` 只比对 KMI 段（如 `android15-8`），实测不同 localversion 可加载；但这不意味着跨 KMI 可用。

---

## 8. 风险与免责

- 本项目修改内核内存管理路径，**可能导致卡顿、数据损坏、无法开机**；
- 仅在已解锁并有 KernelSU 的设备上使用，务必保留原厂模块与回退手段；
- 首次使用前建议记录：原厂 `zram.ko`、`vermagic`、当前 `disksize`；
- 本项目**不提供任何担保**，仅供学习与研究，使用风险自负；
- 请遵守所在地法律法规与设备厂商条款。

---

## 9. 文件清单

```
tools/
  crc_align.py       # 全量 CRC 对齐（__versions + 导出 __crc_）
  symgate2.sh        # 导入符号与设备 kallsyms 全量比对
  deploy.sh          # 对齐 → 校验 → 部署 → refresh
  zram.sh            # 容量/算法配置工具
  build.sh           # 模块构建
work/vendor/
  zcomp.c/.h         # lz4kd / lz4kds 私有后端
  zram_drv.c/.h      # 接点、自检、容量/算法参数
  crystal_sddc_compat.h
  sddc/              # Crystal SDDC（上游代码）+ codec
```

---

## 10. 上游链接

- Crystal HybridSwap：`https://github.com/Wcoom/oneplus_sm8750_kernel`（`drivers/crystalfrostwork/crystal_hybridswap`）
- 设备内核源码（参考）：`https://github.com/whitewhale0612/android_kernel_common_oneplus_sm8750-C16`

如上游作者对归属描述有异议，请以对方声明为准。
