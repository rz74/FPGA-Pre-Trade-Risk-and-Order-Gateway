class AxisDriver:
    """Minimal AXIS-like driver placeholder."""
    def __init__(self, dut, prefix):
        self.dut = dut
        self.prefix = prefix

    async def send(self, words):
        # TODO: drive valid/data/ready handshake
        pass
