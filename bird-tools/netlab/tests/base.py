import os
import pytest

import tests.config as cf


def init(testdir, save):
    cf.testdir = testdir
    cf.save = save

    result = os.system(f"./start -c {testdir}")
    if result != 0:
        return False

    init_dirs()
    init_nodes()
    return True


def run():
    modename = "save" if cf.save else "check"
    print("Running", cf.testdir, "in", modename, "mode")
    return pytest.main(["-x", "-v", f"{cf.testdir}/test-{cf.testdir}.py"]) == 0


def cleanup():
    clean_dirs()
    os.system(f"./stop")


def init_dir(dir):
    if os.path.isdir(dir):
        for _ in os.listdir(dir):
            os.remove(f"{dir}/{_}")
    else:
        os.mkdir(dir)


def init_dirs():
    cf.tempdir = "temp"
    cf.datadir = f"{cf.testdir}/data"

    if cf.save:
        init_dir(cf.datadir)
    else:
        init_dir(cf.tempdir)


def clean_dirs():
    if cf.save:
        return

    for _ in os.listdir(cf.tempdir):
        os.remove(f"{cf.tempdir}/{_}")

    try:
        os.rmdir(cf.tempdir)
    except:
        print("Error in removing temp directory")


def init_nodes():
    cf.nodes = list(filter(lambda n: n[0] == "m", os.listdir(".")))
