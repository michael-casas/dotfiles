# One GitHub review per critic round

The verdict is one pull-request review on the pinned head: line comments at every anchor, the body carrying the score table, the path to 5/5 and the ledger. Issue comments, several reviews, or a review on a later head are not the verdict.

## Pin the head

```bash
gh pr view <n> --repo <owner>/<repo> --json headRefOid,baseRefName,isDraft,url,title
```

Review only `headRefOid`. If it moves before you post, post against the pinned SHA (`commit_id`) and say so in the body.

## Build the review

`review.json` (the body is the report's "Verdict", "Score", "Path to 5/5" and "Findings" sections; one comment per finding):

```json
{
  "commit_id": "<head sha>",
  "event": "REQUEST_CHANGES",
  "body": "## 3/5 at <head>\n\n| # | Dimension | Point | Evidence |\n|...|\n\n## Path to 5/5\n\n| Dimension | Point now | Requirements | Evidence the owner checks |\n|...|\n\n## Findings\n\n...",
  "comments": [
    {
      "path": "tools/frontline/needs-attention/hooks/register.tsx",
      "line": 201,
      "side": "RIGHT",
      "body": "PR31-F1 BLOCKING (dimension 3). <exact comment text>\n\nRequirement: <exact requirement>\nValidator: <command or test>"
    }
  ]
}
```

- `event`: `REQUEST_CHANGES` below 5/5; `APPROVE` at 5/5; `COMMENT` when the authenticated account cannot do either (its own PR, a host restriction): the body then carries BLOCKED or ESCALATED and never means approval. A host that then requires an independent approval on the Correct head is a stop for the owner, not a second critic review.
- `line` is a line of the diff at the head; use `start_line`/`line` for a range. A finding on an unchanged line goes in the body with its permalink and, if GitHub refuses the anchor, the comment is repeated there.
- Multi-line `body` text is JSON-escaped; build the file with a script, not by hand.

## Post it

```bash
gh api --method POST repos/<owner>/<repo>/pulls/<n>/reviews --input review.json
```

Record the returned `id` and `html_url` in the report.

## Check it

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews --jq '.[] | select(.commit_id=="<head>") | {id,state,user:.user.login,html_url}'
gh api repos/<owner>/<repo>/pulls/<n>/comments --jq 'map(select(.pull_request_review_id==<id>)) | length'
```

Exactly one review by the critic on that head; the comment count equals the ledger's non-advisory findings (advisories may be line comments too, prefixed `ADVISORY`). Fix a wrong review by posting a correcting review on the same head that names the superseded one; never delete history.

## Owner's merge check

```bash
gh pr view <n> --json headRefOid,reviewDecision,statusCheckRollup
```

The verification checklist (process.md §7) is done on `headRefOid`; the merge happens on that SHA only.
