""" setup.py """

from setuptools import setup, find_packages
from vm.version import __version__

with open('requirements.txt') as f:
    REQUIREMENTS = f.read().splitlines()

setup(
    name='vm',
    version=__version__,
    description='Simple VirtualBox CentOS VM Manager',
    long_description=open('README.md').read(),
    author='Lenny Capellan',
    author_email='lenny@tek.uno',
    url='https://github.com/lencap/vm',
    packages=find_packages(exclude=['tests*']),
    package_dir={'vm': 'vm'},
    license="MIT",
    py_modules=['vm'],
    install_requires=REQUIREMENTS,
    entry_points = {
        'console_scripts': [
            'vm = vm.vm:main'
        ],
    }
)
