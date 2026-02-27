---
name: commit
description: Stage, commit, and optionally push changes. Use after completing a task.
disable-model-invocation: true
---

# Commit Changes

## Workflow

### 1. Review Changes
```bash
git status
git diff --staged
git diff
```

### 2. Stage Files
Stage specific files (never `git add .` or `git add -A`):
```bash
git add <specific-files>
```

### 3. Create Commit
```bash
git commit -m "$(cat <<'EOF'
feat: add TRC20 token transfer support

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### 4. Push (if requested)
```bash
git push
```

## Rules
- Keep the first line under 72 characters
- Add body for complex changes
- Always include `Co-Authored-By` trailer
- Never commit `.env`, credentials, or secrets
- Never use `--no-verify` unless explicitly asked
