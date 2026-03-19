# Issues Register

**ITGC-SDLC-10: Issues Log**

All issues identified during development, testing, or production must be logged here with resolution tracking. Issues are also tracked in [GitHub Issues](https://github.com/christinacephus-md/claude-model-router/issues).

---

## Issue Template

```
### ISS-[NNN]: [Title]

- **Status**: Open | In Progress | Resolved | Closed
- **Severity**: Critical | High | Medium | Low
- **Reported by**: [name]
- **Reported date**: [YYYY-MM-DD]
- **Assigned to**: [name]
- **Resolved date**: [YYYY-MM-DD]
- **Root cause**: [description]
- **Resolution**: [description]
- **Verified by**: [name]
```

---

## Resolved Issues

### ISS-001: Pre-push hook scanned entire git history on new branches

- **Status**: Resolved
- **Severity**: High
- **Reported by**: Christina Cephus
- **Reported date**: 2026-03-15
- **Assigned to**: Christina Cephus
- **Resolved date**: 2026-03-17
- **Version**: v4.0.1
- **Root cause**: On new branches (remote_sha = 0000...), the hook walked all reachable commits instead of scoping to `origin/{default-branch}..HEAD`
- **Resolution**: Detect new branch push and scope scan to `origin/{default-branch}..{local_sha}`
- **Verified by**: Automated test suite (test_hook.sh)

### ISS-002: Word boundary matching — "plan" matching "explain"

- **Status**: Resolved
- **Severity**: Medium
- **Reported by**: Christina Cephus
- **Reported date**: 2026-03-14
- **Assigned to**: Christina Cephus
- **Resolved date**: 2026-03-14
- **Version**: v4.0.0
- **Root cause**: Keyword matching used simple `in` containment, causing "plan" to match inside "explain"
- **Resolution**: Added `\b` word boundary regex matching for single-word keywords
- **Verified by**: Word boundary test cases in test_hook.sh

### ISS-003: Debugging prompts routing to Haiku

- **Status**: Resolved
- **Severity**: Medium
- **Reported by**: Christina Cephus
- **Reported date**: 2026-03-18
- **Assigned to**: Christina Cephus
- **Resolved date**: 2026-03-18
- **Version**: v5.0.0
- **Root cause**: No debug-specific keyword tier; prompts with "bug", "crash", "stack trace" could be downgraded to Haiku by simple/downgrade keywords
- **Resolution**: Added DEBUG_KEYWORDS tier (28 keywords) with Sonnet floor enforcement in scoring engine
- **Verified by**: Debug routing test cases in test_hook.sh

### ISS-004: PostToolUse matcher missing Agent/Read/Glob/Grep

- **Status**: Resolved
- **Severity**: Medium
- **Reported by**: Christina Cephus
- **Reported date**: 2026-03-18
- **Assigned to**: Christina Cephus
- **Resolved date**: 2026-03-18
- **Version**: v5.0.0
- **Root cause**: v4.0 PostToolUse matcher was `Write|Edit|Bash` — v5.0 added subagent tracking and compaction advisor that require Agent, Read, Glob, Grep triggers
- **Resolution**: Updated settings.json matcher to `Write|Edit|Bash|Agent|Read|Glob|Grep`
- **Verified by**: Manual validation + PostToolUse Agent tracking test

---

## Open Issues

_No open issues at this time._

---

## Process

1. **Report**: Log the issue using the template above
2. **Triage**: Assign severity and owner
3. **Fix**: Develop and test the fix
4. **Verify**: Run test suite, confirm resolution
5. **Close**: Update status, add resolved date and verification
6. **Track**: Cross-reference with GitHub Issues for external visibility
