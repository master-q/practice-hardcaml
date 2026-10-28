PROJECT := designs/mcu_i9
# 32 DP16KD = 64 KiB RAM (the register file uses distributed RAM).
EXPECT_BRAM := 32
# 1419-1571 TRELLIS_COMB with the cloud/CI toolchain on 2026-10-28, 1631
# with the start-up hold and LED logic of #16 (varies
# with packing; other Yosys/nextpnr releases differ further, B-0015).
# Raise deliberately and note why in HISTORY.md.
MAX_LC := 1700
FIRMWARE := sw/dhrystone_rv32i.bin
# The board simulation runs the 50-run image (the 500-run one takes minutes).
BOARD_SIM_FIRMWARE := sw/dhrystone_sim.bin
include ../../mk/ecp5.mk
