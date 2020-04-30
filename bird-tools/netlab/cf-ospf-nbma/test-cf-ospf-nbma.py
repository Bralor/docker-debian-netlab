import pytest
import tests.kernel as tk

LIMIT = 60


@pytest.mark.skipif(
    tk.cf.save == False,
    reason="No need to verify time of convergence during the check mode",
)
def test_wait():
    """Wait until the time (limit) runs out"""
    tk.wait(LIMIT)


@pytest.mark.parametrize(
    "expected_device", ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"],
)
def test_krt_routes(expected_device):
    """
    Test kernel routes:
    -------------------
         - default parametr :limit: set to the value 60 seconds
    """
    tk.test_krt_routes("krt", expected_device)
