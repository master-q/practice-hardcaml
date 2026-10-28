PROJECT := designs/mcu_i9
# 32 DP16KD = 64 KiB RAM (the register file uses distributed RAM).
EXPECT_BRAM := 32
# 1419-1571 TRELLIS_COMB with the cloud/CI toolchain on 2026-10-28 (varies
# with packing; other Yosys/nextpnr releases differ further, B-0015).
# Raise deliberately and note why in HISTORY.md.
MAX_LC := 1650
FIRMWARE := sw/dhrystone_rv32i.bin
include ../../mk/ecp5.mk
