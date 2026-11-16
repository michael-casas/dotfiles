#!/usr/bin/env python3
"""Read-only fake tool boundary for PR suites; never invokes the real tools."""
import json
import os
import sys
import time

name, args = sys.argv[1], sys.argv[2:]
with open(os.environ['PRS_LOG'], 'a') as log:
    log.write(json.dumps({'tool': name, 'args': args, 'cwd': os.getcwd()}) + '\n')
if os.environ.get('PRS_DELAY'):
    time.sleep(float(os.environ['PRS_DELAY']))
if name == 'gh' and os.environ.get('PRS_ERROR'):
    print(os.environ['PRS_ERROR'], file=sys.stderr)
    sys.exit(1)

def row(n, draft=False, review=False):
    return dict(number=n, title=('Zebra' if n == 3 else 'Fix build') + ' ' + str(n),
                url='https://github.com/acme/repo/pull/' + str(n),
                repository={'nameWithOwner': 'acme/repo'}, author={'login': 'alice'},
                isDraft=draft, updatedAt='2026-11-15T10:00:0' + str(n) + 'Z',
                headRefName='fix/build', baseRefName='main', baseRefOid='base',
                headRefOid=os.environ.get('PRS_HEAD', 'head'), body='## Context\nPR body', state='OPEN',
                additions=120, deletions=34, changedFiles=6, comments=[{}, {}, {}],
                labels=[{'name': 'bug'}], reviewDecision='CHANGES_REQUESTED' if n == 2 else 'APPROVED',
                reviewRequests=[{'login': 'me'}] if review else [],
                latestReviews=[{'author': {'login': 'bob'}, 'state': 'APPROVED'}],
                statusCheckRollup=[{'name': 'unit', 'status': 'COMPLETED', 'conclusion': 'SUCCESS',
                                    'startedAt': '2026-11-15T10:00:00Z', 'completedAt': '2026-11-15T10:01:00Z',
                                    'detailsUrl': 'https://github.com/acme/repo/actions/runs/1'},
                                   {'name': 'lint', 'conclusion': 'FAILURE'},
                                   {'name': 'build', 'status': 'IN_PROGRESS'}])

if name == 'git':
    if 'get-url' in args:
        print('git@github.com:acme/repo.git' if os.environ.get('PRS_LOCAL') == '1' else 'git@github.com:other/repo.git')
    elif 'merge-base' in args:
        print('mergebase')
    elif 'rev-parse' in args:
        print(os.environ.get('PRS_HEAD', 'head'))
    elif 'fetch' not in args:
        sys.exit(1)
elif name == 'hunk':
    if args[:2] == ['session', 'list']:
        print(json.dumps({'sessions': [] if os.environ.get('PRS_EXIT') == '1' else [
            {'sessionId': 'ours', 'cwd': os.getcwd(), 'inputKind': 'patch',
             'terminal': {'locations': [{'sessionId': os.environ.get('PRS_MARKER', '')}]}},
            {'sessionId': 'someone-else', 'terminal': {'locations': [{'sessionId': 'not-ours'}]}}]}))
    elif args[:3] == ['session', 'comment', 'list']:
        if os.environ.get('PRS_EXIT') == '1':
            sys.exit(1)
        print(json.dumps({'comments': json.loads(os.environ.get('PRS_NOTES', '[]'))}))
    elif args[:3] == ['session', 'comment', 'apply']:
        payload = json.load(sys.stdin)
        with open(os.environ['PRS_APPLIED'], 'w') as out:
            json.dump(payload, out)
        print('{}')
    else:
        sys.exit(1)
elif name == 'hc':
    print('{}')
elif args[:2] == ['pr', 'list']:
    print(json.dumps([] if os.environ.get('PRS_EMPTY') == '1' else [row(1, True), row(3), row(2, False, True)]))
elif args[:2] == ['search', 'prs']:
    rows = [row(1, True), row(3), row(2, False, True)]
    # Search really does not return the detail fields.
    print(json.dumps([{k: v for k, v in r.items() if k in ['number', 'title', 'url', 'repository', 'author', 'isDraft', 'updatedAt']} for r in rows]))
elif args[:2] == ['pr', 'view']:
    if '--web' not in args:
        print(json.dumps(row(int(args[2]), int(args[2]) == 1, int(args[2]) == 2)))
elif args[:2] == ['pr', 'diff']:
    print('diff --git a/a.lua b/a.lua\n--- a/a.lua\n+++ b/a.lua\n@@ -1 +1 @@\n-old\n+new')
elif args[:2] == ['repo', 'list']:
    print('[{"nameWithOwner":"acme/repo"}]')
elif args[:2] == ['api', 'user']:
    print('{"login":"me"}')
elif args[0] == 'api' and '/comments' in args[1]:
    print(json.dumps([[{'path': 'a.lua', 'line': 1, 'side': 'RIGHT', 'body': 'Existing note',
                       'user': {'login': 'bob'}, 'html_url': 'https://github.com/comment/1'},
                      {'path': 'a.lua', 'line': None, 'original_line': 99, 'body': 'outdated'}]]))
elif args[0] == 'api' and '/reviews' in args[1]:
    sys.exit('TEST SAFETY: a real-submit path must never run')
else:
    sys.exit('unexpected fake command: ' + repr(args))
