"""Shared helpers: read the link configs with dotbot's own vendored PyYAML."""
import os
from pathlib import Path
import platform
import sys

REPO = Path(__file__).resolve().parents[2]
DOTBOT = REPO / 'dotbot' / 'bin' / 'dotbot'
sys.path.insert(0, str(REPO / 'dotbot' / 'lib' / 'pyyaml' / 'lib'))
import yaml  # noqa: E402  (vendored by the dotbot submodule)

COMMON = 'install.conf.yaml'
PER_OS = {'Darwin': 'install.macos.yaml', 'Linux': 'install.linux.yaml'}
CONFIGS = [COMMON] + sorted(PER_OS.values())


def load(name):
    with open(REPO / name, encoding='utf-8') as handle:
        return yaml.safe_load(handle) or []


def links(name):
    """(destination, source) for every link a config file declares."""
    found = []
    for task in load(name):
        for directive, data in task.items():
            if directive != 'link':
                continue
            for dest, spec in data.items():
                source = spec.get('path') if isinstance(spec, dict) else spec
                found.append((dest, source))
    return found


def links_for_this_os():
    names = [COMMON] + ([PER_OS[platform.system()]] if platform.system() in PER_OS else [])
    return [pair for name in names for pair in links(name)]


def expand(dest, home, xdg=None):
    """A destination as dotbot would expand it for this HOME and XDG_CONFIG_HOME."""
    xdg = xdg or os.path.join(home, '.config')
    dest = dest.replace('$XDG_CONFIG_HOME', xdg)
    if dest == '~' or dest.startswith('~/'):
        dest = str(home) + dest[1:]
    return Path(dest)
