# SPDX-License-Identifier: GPL-2.0-only

GCOV_PROFILE := y

# Resident SDDC (similarity/delta) layer: enabled for every object of this
# module so struct zram layout stays identical across translation units.
ccflags-y += -DCONFIG_CRYSTAL_HYBRIDSWAP_SDDC=1

obj-$(CONFIG_HYBRIDSWAP_ZRAM) += oplus_bsp_hybridswap_zram.o

obj-$(CONFIG_CRYPTO_ZSTDN) += zstd/
obj-$(CONFIG_CRYPTO_LZ4K) += lz4k/

oplus_bsp_hybridswap_zram-y	:=	zcomp.o zram_drv.o
oplus_bsp_hybridswap_zram-$(CONFIG_KCOMPRESSD)	+=	kcompressd.o
oplus_bsp_hybridswap_zram-$(CONFIG_HYBRIDSWAP) += hybridswap/hybridmain.o
oplus_bsp_hybridswap_zram-$(CONFIG_HYBRIDSWAP_SWAPD) += hybridswap/hybridswapd.o
oplus_bsp_hybridswap_zram-$(CONFIG_HYBRIDSWAP_CORE) += hybridswap/hybridswap.o

obj-$(CONFIG_HYBRID_ZSMALLOC)	+= hybrid_zsmalloc.o
oplus_bsp_hybridswap_zram-y += hybridswap/display.o
oplus_bsp_hybridswap_zram-y += lz4kd/lz4kd_encode.o lz4kd/lz4kd_decode.o
oplus_bsp_hybridswap_zram-y += lz4kd/lz4kd_encode_delta.o
oplus_bsp_hybridswap_zram-y += sddc/crystal_sddc_codec.o sddc/crystal_sddc.o
ifeq ($(CONFIG_ARM64)$(CONFIG_KERNEL_MODE_NEON),yy)
oplus_bsp_hybridswap_zram-y += lz4kd/lz4kd_neon.o
CFLAGS_REMOVE_lz4kd/lz4kd_neon.o += -mgeneral-regs-only
CFLAGS_lz4kd/lz4kd_neon.o += -ffreestanding -isystem $(shell $(CC) -print-file-name=include)
endif
