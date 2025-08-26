class AxilDriver:
    """AXI-Lite config plane driver placeholder."""
    def __init__(self, dut):
        self.dut = dut

    async def write(self, addr, data):
        # TODO: write config
        pass

    async def read(self, addr):
        # TODO: readback
        return 0
