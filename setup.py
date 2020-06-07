import os
import pathlib

from setuptools import find_packages, setup


setup(
    name="lacmus_onboard",
    version="0.1.0",
    packages=find_packages("src"),
    package_dir={"": "src"},
    package_data={
        "lacmus_onboard": ["camera/chdkptp-rpi/*",
                           "camera/chdkptp-rpi/*/*",
                           "camera/chdkptp-rpi/*/*/",
                           "camera/chdkptp-rpi/*/*/*"],
    },
    install_requires=[
        "pymavlink",
        "aiohttp",
    ],
    extras_require={
        "tests": [
            "pytest",
            "pytest-asyncio",
            "pytest-cov",
        ],
    },
    entry_points={
        'console_scripts': [
            'lacmus_onboard = lacmus_onboard.main:run',
        ]
    },
)
