import os
import sys
import pickle
import pytest
from inspect import getsourcefile

import tests.kernel as tk

LIMIT = 60
EXPECTED_DEVICES = (
    "m11",
    "m12",
    "m13",
    "m14",
    "m21",
    "m22",
    "m23",
    "m24",
    "m31",
    "m32",
    "m33",
    "m34",
    "m41",
    "m42",
    "m43",
    "m44",
)


@pytest.mark.skipif(tk.cf.save == False, reason="mode: save")
def test_wait():
    """Wait until the time (limit) runs out"""
    tk.wait(LIMIT)


@pytest.mark.parametrize("exp_devs", EXPECTED_DEVICES)
def test_krt_tables(exp_devs):
    tk.test_krt_routes("krt", exp_devs)
