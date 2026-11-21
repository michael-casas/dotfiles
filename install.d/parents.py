"""Check the directories dotbot would write into, before dotbot runs.

dotbot follows a symlinked directory and writes into its target. So every
existing directory on the way to a managed destination's parent, and every
cleanup or create root, must be a real directory: below HOME from HOME down, and for an
XDG_CONFIG_HOME outside HOME from the filesystem root down. The paths come from the same config
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


def managed(path):
    """Every path this guard checks goes through here: expanded as dotbot
    does (expandvars, then expanduser), refused when relative or when it has
    a `.` or `..` component, then cleared of redundant slashes. ./install
    already refuses such a HOME or XDG_CONFIG_HOME, and the policy test such
    a declaration, so the raw, lexical and physical readings of a path are
    one and the same, and the walk below is exact."""
    full = os.path.expanduser(os.path.expandvars(path))
    if not os.path.isabs(full):
        raise ValueError(f'not an absolute path: {path!r} -> {full!r}')
    if any(part in (os.curdir, os.pardir) for part in full.split(os.sep)):
        raise ValueError(f'. or .. component in {path!r} -> {full!r}')
    return os.path.normpath(full)


def declared(yaml, configs):
    """(link destinations, cleanup and create roots), each through managed()."""
    links, roots = [], []
    for name in configs:
        with open(name, encoding='utf-8') as handle:
            tasks = yaml.safe_load(handle) or []
        for task in tasks:
            for directive, data in task.items():
                if directive == 'link':
                    links.extend(managed(dest) for dest in data)
                elif directive in ('clean', 'create'):   # list or mapping form
                    roots.extend(managed(root) for root in data)
    return links, roots


def skill_roots(base):
    catalog = os.path.join(base, 'skill-catalog.py')
    if not os.path.isfile(catalog):
        return []
    spec = importlib.util.spec_from_file_location('skill_catalog', catalog)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # module level only defines constants
    return [managed(str(target)) for target in module.TARGETS]


# macOS's own top-level aliases (/tmp -> private/tmp and so on). Rewritten
# before the walk, and only when they are exactly the system's links, so a
# symlink the caller made anywhere is still reported.
DARWIN_ALIASES = ('tmp', 'var', 'etc')


def unalias(path):
    if sys.platform != 'darwin':
        return path
    for name in DARWIN_ALIASES:
        alias = os.sep + name
        if (path == alias or path.startswith(alias + os.sep)) and os.path.islink(alias) \
                and os.readlink(alias) == 'private/' + name:
            return os.sep + 'private' + path
    return path


def walk(path, home):
    """Every directory a write to `path` passes through, in order. Below HOME
    the walk starts at HOME, which is taken as given; anywhere else (an
    XDG_CONFIG_HOME outside HOME) it starts at the filesystem root."""
    top = home.rstrip(os.sep) or os.sep
    if path == top or path.startswith(top + os.sep):
        rest = path[len(top):]
    else:
        top, rest = os.sep, unalias(path)
    current = top
    for part in rest.split(os.sep):
        if part in ('', os.curdir):
            continue
        current = os.path.join(current, part)
        yield current


def problems(path, home):
    """The first bad directory on the way to `path`; stop at the first missing one."""
    for step in walk(path, home):
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
    try:
        home = managed('~')
    except ValueError as error:
        print(f'error\tHOME: {error}')
        return 2
    try:
        links, roots = declared(load_yaml(dotbot), configs)
        roots += skill_roots(base)
    except Exception as error:  # an unreadable config is reported, never guessed at
        print(f'error\t{type(error).__name__}: {error}'.replace('\n', ' '))
        return 2
    seen, bad = set(), []
    for path in [os.path.dirname(link) for link in links] + roots:
        for problem in problems(path, home):
            if problem[1] not in seen:
                seen.add(problem[1])
                bad.append(problem)
    for problem, path in bad:
        print(f'{problem}\t{path}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
