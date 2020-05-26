# settings.py
import argparse
import pathlib
import os

from trafaret_config import commandline

from lacmus_onboard.utils import TRAFARET


BASE_DIR = pathlib.Path(__file__).parent.parent
PROJECT_ROOT = BASE_DIR / 'lacmus_onboard'
DEFAULT_CONFIG_PATH = BASE_DIR / 'config' / 'polls.yaml'


if os.uname().machine == 'x86_64':  # ubuntu on PC
	CHDKPTP_BASE_PATH = pathlib.Path(__file__) / 'chdkptp'
elif os.uname().machine == 'armv7l': # raspbertty pi
	CHDKPTP_BASE_PATH = pathlib.Path(__file__) / 'chdkptp-rpi'

def get_config(argv=None):
    ap = argparse.ArgumentParser()
    commandline.standard_argparse_options(
        ap,
        default_config=DEFAULT_CONFIG_PATH
    )

    # ignore unknown options
    options, unknown = ap.parse_known_args(argv)

    config = commandline.config_from_options(options, TRAFARET)
    return config
