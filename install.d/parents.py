"""Check the directories dotbot would write into, before dotbot runs.

dotbot follows a symlinked directory and writes into its target. So every
existing directory on the way to a managed destination's parent, and every
cleanup root, must be a real directory. The paths come from the same config
files dotbot reads and from skill-catalog.py's own targets, so the declared
paths and this guard cannot diverge. The leaf itself is dotbot's to judge.

usage: parents.py <dotbot launcher> <link base> <config>...
Prints one `<problem>\t<path>` line per bad directory and exits 1; exits 0
when all are real; exits 2 when the configs cannot be read. Read-only.
"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True  # importing skill-catalog.py must not write __pycache__


def load_yaml(dotbot):
    here = os.path.dirname(os.path.abspath(__file__))
    for top in (os.path.dirname(os.path.dirname(os.path.realpath(dotbot))),
                os.path.join(os.path.dirname(here), 'dotbot')):
        sys.path.insert(0, os.path.join(top, 'lib', 'pyyaml', 'lib'))
    import yaml  # noqa: E402  (dotbot's vendored PyYAML)
    return yaml


def expand(path):
    return os.path.abspath(os.path.expanduser(os.path.expandvars(path)))


def declared(yaml, configs):
    """(link destinations, cleanup roots) as dotbot will expand them."""
    links, roots = [], []
    for name in configs:
        with open(name, encoding='utf-8') as handle:
            tasks = yaml.safe_load(handle) or []
        for task in tasks:
            for directive, data in task.items():
                if directive == 'link':
                    links.extend(expand(dest) for dest in data)
                elif directive == 'clean':
                    roots.extend(expand(root) for root in data)
    return links, roots


def skill_roots(base):
    catalog = os.path.join(base, 'skill-catalog.py')
    if not os.path.isfile(catalog):
        return []
    spec = importlib.util.spec_from_file_location('skill_catalog', catalog)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # module level only defines constants
    return [os.path.abspath(str(target)) for target in module.TARGETS]


def anchor(path, home, xdg):
    """The directory a walk starts below. XDG_CONFIG_HOME outside HOME is a
    managed root, so it is checked itself; HOME is taken as given."""
    for top, checked in ((home, False), (xdg, True)):
        if path == top or path.startswith(top.rstrip(os.sep) + os.sep):
            return top, checked
    return os.sep, False


def problems(path, home, xdg):
    """Walk from the anchor down to `path`; stop at the first missing one."""
    top, checked = anchor(path, home, xdg)
    steps = [top] if checked else []
    rest = os.path.relpath(path, top)
    if rest != os.curdir:
        current = top
        for part in rest.split(os.sep):
            current = os.path.join(current, part)
            steps.append(current)
    for step in steps:
        if os.path.islink(step):
            yield 'symlink', step
            return
        if not os.path.lexists(step):
            return
        if not os.path.isdir(step):
            yield 'not a directory', step
            return


def main(argv):
    if len(argv) < 4:
        print(__doc__.strip().splitlines()[-3], file=sys.stderr)
        return 2
    dotbot, base, configs = argv[1], argv[2], argv[3:]
    home = os.path.abspath(os.path.expanduser('~'))
    xdg = os.path.abspath(os.environ.get('XDG_CONFIG_HOME') or os.path.join(home, '.config'))
    try:
        links, roots = declared(load_yaml(dotbot), configs)
        roots += skill_roots(base)
    except Exception as error:  # an unreadable config is reported, never guessed at
        print(f'error\t{type(error).__name__}: {error}'.replace('\n', ' '))
        return 2
    seen, bad = set(), []
    for path in [os.path.dirname(link) for link in links] + roots:
        for problem in problems(path, home, xdg):
            if problem[1] not in seen:
                seen.add(problem[1])
                bad.append(problem)
    for problem, path in bad:
        print(f'{problem}\t{path}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
