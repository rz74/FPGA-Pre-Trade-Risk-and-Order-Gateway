import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def smoke_test(dut):
    """Placeholder smoke test for the risk gateway top."""
    await Timer(1, units="ns")
