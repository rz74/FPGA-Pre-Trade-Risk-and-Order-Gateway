class GoldenRiskModel:
    """Python reference model for pre-trade risk checks (placeholder)."""
    def __init__(self, cfg=None):
        self.cfg = cfg or {}

    def evaluate(self, order, nbbo):
        """Return (allow: bool, reason: str)."""
        # TODO: implement size/notional, collars, credit/position, throttle, dupID, STP
        return True, "OK"
