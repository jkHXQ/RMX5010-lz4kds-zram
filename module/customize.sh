#!/system/bin/sh
ui_print "- LZ4KDS 内存压缩（LZ4KD + SDDC）"
ui_print "- 算法来源: Crystal HybridSwap (SDDC) / HiSilicon (LZ4KD)"
ui_print "- 驱动骨架: OPPO/realme oplus_bsp_hybridswap_zram"
ui_print "- 默认: 9216 MiB + lz4kds"
ui_print "- 修改: sh /data/adb/modules/lz4kds/zram.sh 8192 lz4kds"
ui_print "- 改后执行 ksud initrc refresh 并重启"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/zram.sh 0 0 0755
set_perm $MODPATH/webroot/webui.sh 0 0 0755
set_perm $MODPATH/webroot/index.html 0 0 0644
set_perm $MODPATH/uninstall.sh 0 0 0755
