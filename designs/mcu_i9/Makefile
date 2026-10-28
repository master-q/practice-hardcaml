PROJECT := designs/mcu_i9
# 32 DP16KD = 64 KiB RAM (the register file uses distributed RAM).
EXPECT_BRAM := 32
# 1419-1491 TRELLIS_COMB on 2026-10-28 (varies with packing); raise
# deliberately and note why in HISTORY.md.
MAX_LC := 1600
FIRMWARE := sw/dhrystone_rv32i.bin
include ../../mk/ecp5.mk
