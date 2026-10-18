# Known issues: build, install and runtime problems with verified solutions

One Markdown file per problem. The point of this folder is to be searchable
with `grep` or with Claude, so everything stays plain text and every entry has
the same shape.

```
issues/
  README.md        this file
  INDEX.md         one line per entry (keep in sync, see below)
  SCANS.md         scan history, one compact entry per scan-carla-logs.sh run (append only)
  _template.md     copy this for a new entry
  NNNN-slug.md     the entries
  reports/         full reports of scan-carla-logs.sh with log context (git-ignored)
```

## Entry format

```markdown
---
id: 0001
title: short, searchable title
status: verified        # verified | open | noise
phase: build            # build | install | run | test
signature: 'ERE regex that matches the log line'
sources: [where the problem shows up]
first_seen: 2026-10-14
fixed_in: 65171332f     # commit hash, or "-" if not fixed in git
---
## Symptom
## Cause
## Solution (verified <date>, commit <hash>)
## How it was verified
## Did not work / untested
```

## Rules

- `status: verified` means the solution was applied and the success was
  proven: a commit plus a green build or test log. Nothing else counts.
- Ideas that were not tested, or that did not work, go only under
  "Did not work / untested". Never into the Solution section, so a search
  for solutions never returns a guess.
- `status: open` means the problem is understood well enough to recognise
  it, but no verified solution exists yet. The Solution section stays empty.
- `status: noise` means the pattern is known and harmless. The scanner counts
  these hits but hides them from the report.
- `signature` is a POSIX extended regex (grep -E). `scan-carla-logs.sh`
  matches every error line against the signatures of all entries, in id
  order, and assigns the line to the first match. Keep signatures specific;
  a bare `error` would swallow everything.
- When a new entry is added, add its line to `INDEX.md`.

## Searching

```sh
grep -l 'status: verified' issues/*.md          # all proven solutions
grep -il 'pthread' issues/*.md                   # by keyword
grep -h '^title:' issues/*.md                    # all titles
```

Or ask Claude: "search issues/ for <symptom> and show only verified solutions".

## Adding an entry from a scan

`./scan-carla-logs.sh` appends a compact entry for every run to `SCANS.md`
(tracked in git, the history of all scans) and writes the full report with log
context to `issues/reports/` (git-ignored). The full report's last section
contains a ready-made template for every unknown error group with the
signature pre-filled. Copy it to `issues/NNNN-slug.md`, set `status: open`,
and change it to `verified` only after the fix is proven.
