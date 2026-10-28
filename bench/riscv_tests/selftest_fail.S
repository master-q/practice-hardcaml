# Negative test for run.exe: test case 2 expects 1 but computes 2, so the
# runner must report "test case 2 failed".
#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  TEST_CASE(2, a0, 1, li a0, 2)
  TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
