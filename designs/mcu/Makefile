PROJECT := designs/mcu
EXPECT_BRAM := 10
# 1079 LCs on 2026-10-28. The budget leaves ~5% for placement variation;
# raise it deliberately (and note why in HISTORY.md) when adding features.
MAX_LC := 1130
FIRMWARE := sw/echo_rv32e.bin
include ../../mk/icestick.mk
