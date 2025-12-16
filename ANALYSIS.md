# Agent Council - Repository Analysis

## 1. Purpose

Multi-AI consensus tool for Claude Code. Gathers opinions from AI CLIs (Codex, Gemini) and synthesizes via Claude as "Chairman". Key value: uses subscription CLIs instead of API calls = no extra costs.

## 2. Architecture

```
User Question
     │
     ▼
┌─────────────┐     ┌─────────────┐
│ council.sh  │────▶│  Parallel   │
│  (entry)    │     │  CLI calls  │
└─────────────┘     └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         ┌────────┐   ┌────────┐   ┌────────┐
         │ Codex  │   │ Gemini │   │  ...   │
         └───┬────┘   └───┬────┘   └───┬────┘
              │            │            │
              └────────────┼────────────┘
                           ▼
                    ┌─────────────┐
                    │   Claude    │
                    │ (Chairman)  │
                    └─────────────┘
```

**Entry Points:**
- `bin/install.js` - NPX installation
- `skills/agent-council/scripts/council.sh` - Core execution

**Data Flow:**
1. User triggers via Claude or direct script
2. `council.sh` parses `council.config.yaml`
3. Spawns parallel CLI processes
4. Collects responses to temp files
5. Formats output for Claude synthesis

## 3. Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Core script | Bash | Council execution |
| Installer | Node.js | NPX distribution |
| Config | YAML | Member definitions |
| Skill def | Markdown | Claude integration |

**Runtime Dependencies:** None (shell only)
**Build Dependencies:** Node.js (install only)
**External CLIs:** codex, gemini (user-provided)

## 4. Bloat Assessment

| Item | Path | Size | Verdict |
|------|------|------|---------|
| KFC agents | `.claude/agents/kfc/` | 1104 lines | **BLOAT** - unrelated to council |
| KFC settings | `.claude/settings/kfc-settings.json` | 24 lines | **BLOAT** |
| KFC prompts | `.claude/system-prompts/` | 306 lines | **BLOAT** |
| Korean README | `README.ko.md` | ~169 lines | Keep (i18n) |
| Marketplace | `.claude-plugin/` | 16 lines | Keep (distribution) |

**Dead Code:** None in core
**Unused Deps:** None (zero deps)

## 5. Complexity Hotspots

| File | Lines | Issue | Risk |
|------|-------|-------|------|
| `council.sh:53-88` | 35 | AWK YAML parser | Medium - fragile, breaks on edge cases |
| `council.sh:98-117` | 19 | `eval` command execution | **HIGH** - command injection risk |
| `council.sh:127-133` | 6 | Bash array handling | Low - macOS compatible but verbose |

**Security Risks:**
1. **Line 111**: `eval "$command \"\$PROMPT\""` - User config controls execution
2. No input sanitization on YAML values
3. Temp files in `/tmp` with predictable names

## 6. MVP Core

Minimum files for function:

| File | Lines | Required |
|------|-------|----------|
| `skills/agent-council/scripts/council.sh` | 169 | Yes |
| `skills/agent-council/SKILL.md` | 126 | Yes (Claude trigger) |
| `council.config.yaml` | 36 | Yes (default config) |
| **Total** | **331** | |

Optional but valuable:
- `bin/install.js` (86 lines) - for NPX distribution
- `README.md` (169 lines) - documentation

## 7. Cut List

Files to delete:

| Path | Lines | Reason |
|------|-------|--------|
| `.claude/agents/kfc/*` | 774 | Unrelated spec framework |
| `.claude/settings/kfc-settings.json` | 24 | KFC config |
| `.claude/system-prompts/spec-workflow-starter.md` | 306 | KFC orchestration |
| `.claude/settings.local.json` | ? | Local dev artifact |

**Total deletable:** ~1104 lines (50%+ of non-doc content)

## 8. Refactor Targets

| Location | Current | Proposed | Impact |
|----------|---------|----------|--------|
| `council.sh:53-88` | AWK YAML parser | Use `yq` or simplify to JSON | Reliability++ |
| `council.sh:111` | `eval` execution | Direct command array | Security++ |
| `council.sh:50` | `mktemp -d` | Add trap cleanup | Reliability+ |
| `install.js:21-38` | Recursive copy | Use `fs.cpSync` (Node 16+) | Simplicity+ |
| `council.config.yaml` | Separate file | Embed in SKILL.md or JSON | Fewer files |

## 9. Action Plan

### Quick Wins (< 30 min each)

1. **Delete KFC bloat** - Remove `.claude/agents/kfc/`, `.claude/settings/`, `.claude/system-prompts/`
2. **Fix temp cleanup** - Add `trap "rm -rf $TEMP_DIR" EXIT` after line 50
3. **Update package.json** - Change repo URL from `team-attention` to `beauNate`

### Medium Effort

4. **Harden command execution** - Replace `eval` with safer pattern:
   ```bash
   # Instead of: eval "$command \"\$PROMPT\""
   # Use: $command "$PROMPT" (if command is simple)
   # Or: bash -c "$command" -- "$PROMPT" (with proper escaping)
   ```

5. **Simplify YAML parsing** - Options:
   - Switch to JSON config (native bash parsing)
   - Require `yq` dependency
   - Inline defaults, make config optional

### Feature Additions

6. **Add timeout enforcement** - Config has `timeout: 120` but unused
   ```bash
   timeout ${TIMEOUT}s $command "$PROMPT"
   ```

7. **Add response caching** - Cache identical queries to avoid re-calling
8. **Add retry logic** - Retry failed CLI calls once
9. **Add --dry-run flag** - Show what would be called without executing
10. **Add JSON output mode** - For programmatic consumption

### Nice-to-Have

11. **Add more default agents** - Grok, Perplexity, local Ollama
12. **Add voting/scoring** - Let agents rate each other's responses
13. **Add session history** - Save past council sessions

---

## Summary Stats

| Metric | Value |
|--------|-------|
| Total files | 20 |
| Core files | 4 |
| Lines of code | 255 (core) |
| Lines of bloat | 1104 (KFC) |
| Security issues | 1 (eval) |
| Zero dependencies | ✓ |
