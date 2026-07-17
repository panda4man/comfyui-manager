# Claude Code Agents

Agents that interact with this ComfyUI Manager repo. Each agent is optimized for a class of task.

## Quick Reference

| Agent | Task | Key Files | Use When |
|-------|------|-----------|----------|
| **cavecrew-builder** | 1-2 file edits | install, download, Makefile, config | Modify a specific script or plist template |
| **cavecrew-investigator** | Locate code | All | Find where a function/config is defined, trace dependencies |
| **cavecrew-reviewer** | Review diffs | All | Audit a PR or branch before merge |
| **Explore** | Codebase search | All | Search across files by pattern or keyword, answer "where is X" |
| **general-purpose** | Complex tasks | All | Multi-step: refactor, rewrite, design new features |

---

## cavecrew-builder

**One or two file surgical edits.** Use for isolated changes.

### Good For
- Fix typo in script
- Add new Makefile target
- Update .env.example with new var
- Modify single function in download-models.sh
- Change LaunchAgent plist template

### Example
```
delegate to builder: fix the typo in Makefile line 14 ("LaunchAgent" → "LaunchD")
```

### Not For
- Rewriting download-models.sh (scope too large)
- Adding new features across multiple scripts
- Architectural changes

---

## cavecrew-investigator

**Read-only code locator.** Fast answers to structural questions.

### Good For
- Where is `get_model_dir()` defined?
- What calls conda in install-comfyui.sh?
- List all references to `CIVITAI_API_KEY`
- What model types does download-models.sh support?
- Map the config directory

### Example
```
delegate to investigator: Find all places LISTEN_ADDRESS is used
```

Output: file:line table of matches.

### Not For
- Suggesting fixes (read-only)
- Cross-file analysis (use Explore instead)

---

## cavecrew-reviewer

**Diff auditor.** Severity-tagged findings per line.

### Good For
- Review a PR branch before merge
- Audit changes to install-comfyui.sh
- Check download-models.sh for correctness bugs
- Verify Makefile edits don't break service control
- Spot simplification or reuse opportunities

### Example
```
/code-review high
```

Output: one-line findings, formatted as `path:line: <emoji> <severity>: <problem>. <fix>.`

---

## Explore

**Fast codebase search.** Multi-file pattern matching.

### Good For
- Find all shell scripts (*.sh)
- Search for error handling patterns
- Locate model type definitions
- Find references to specific ports/addresses
- Answer "what all uses PyTorch" or "what all writes to logs"

### Example
```
Use Explore to find all references to "8188" in the repo
```

Specify breadth: "quick" (single lookup), "medium" (targeted), "very thorough" (all corners).

---

## general-purpose

**Anything complex or multi-step.**

### Good For
- Add new model type + download support
- Refactor scripts to reduce duplication
- Design new service (e.g., model server wrapper)
- Multi-file refactor (install → download → Makefile)
- Integrate new external API (e.g., Ollama, vLLM)

### Example
```
Add support for downloading models from a custom S3 bucket.
Changes needed: config vars, download-models.sh arg parsing, docs.
```

---

## Common Workflows

### "Add new Makefile target for model cleanup"
→ Use **cavecrew-builder**: one file edit.

### "I want to see how CivitAI downloads are scraped"
→ Use **cavecrew-investigator**: find `get_civitai_url()` and callers.

### "Audit my branch before pushing"
→ Use **cavecrew-reviewer** with `/code-review high`.

### "Search for all config variables"
→ Use **Explore** with `grep` for `LISTEN_|LOG_|COMFY_|CIVITAI_`.

### "Support new cloud storage for models (GCS, S3)"
→ Use **general-purpose**: multi-file refactor + new deps.

### "Fix broken install on specific macOS version"
→ Use **cavecrew-builder** if single script, **general-purpose** if multi-script debugging.

---

## Agent Invoking Syntax

Via Claude Code CLI or Web:

```bash
# Quick builder fix
delegate to builder: [description]

# Investigator search
delegate to investigator: [description]

# Review current branch
/code-review high

# Explore codebase
Use Explore to [description]

# General complex work
[describe task, agent decides to spawn if needed]
```

Or spawn directly:
```bash
/spawn cavecrew-builder
/spawn cavecrew-investigator
/spawn cavecrew-reviewer
```

---

## Tips

- **Cavecrew output is compressed** (~60% token savings). Main thread reads the summary, not full diffs.
- **Delegate early for scope questions.** Investigator finds dependencies fast.
- **For perf-critical paths** (install, download), use cavecrew-reviewer to catch off-by-one or resource-leak issues.
- **Long refactors** (3+ files) → general-purpose, not builder.
- **Audit before merge** → cavecrew-reviewer, even for small branches.
