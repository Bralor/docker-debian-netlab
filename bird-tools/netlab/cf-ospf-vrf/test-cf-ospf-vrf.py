import os
import sys
import pickle
import pytest
from inspect import getsourcefile

import tests.kernel as tk

LIMIT = 60
EXPECTED_DEVICES = ("m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9", "m10")


@pytest.mark.skipif(tk.cf.save == False, reason="mode: save")
def test_wait():
    """Wait until the time (limit) runs out"""
    tk.wait(LIMIT)


@pytest.mark.parametrize("exp_devs", EXPECTED_DEVICES)
def test_krt_tables(exp_devs):
    tk.test_krt_routes("krt", exp_devs)
