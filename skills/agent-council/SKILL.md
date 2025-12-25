---
name: agent-council
description: Collect and synthesize opinions from multiple AI Agents. Use when users say "summon the council", "ask other AIs", or want multiple AI perspectives on a question.
---

# Agent Council

> Collect and synthesize opinions from multiple AI Agents
> Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)

## Overview

Agent Council gathers opinions from multiple AI Agents across a **3-stage deliberation process**:

1. **Technical Council** (7 members) - Unfiltered expert analysis from diverse cognitive perspectives
2. **Ethical Sub-Chairs** (6 members) - Synthesize technical input through ethical frameworks
3. **Chairman** - Final synthesis with "What The Chairman Might Have Missed" transparency section

## Architecture

```
THE CHAIRMAN (Opus 4.5) - Final Arbiter [HIGHEST REASONING]
    │
    ├── Stage 1: TECHNICAL COUNCIL (7 experts) [DIVERSE PERSPECTIVES]
    │   ├── The Architect (GPT-5.2) - Strategic systems thinking
    │   ├── The Scholar (Codex-Max) - Deep technical analysis
    │   ├── The Sprinter (Codex-Mini) - Pragmatic speed
    │   ├── The Diplomat (Sonnet 4) - Balanced human factors
    │   ├── The Monk (Haiku 4.5) - First principles
    │   ├── The Oracle (Gemini Pro) - Research synthesis
    │   └── The Scout (Gemini Flash) - Pattern recognition
    │
    ├── Stage 2: ETHICAL SUB-CHAIRS (6 frameworks) [HIGH REASONING]
    │   ├── The Utilitarian (GPT-4o) - Consequentialism
    │   ├── The Kantian (o3-mini) - Deontology
    │   ├── The Aristotelian (o3) - Virtue Ethics
    │   ├── The Pragmatist (GPT-4.1) - What works
    │   ├── The Guardian (GPT-4.1-mini) - Care Ethics
    │   └── The Machiavelli (GPT-4o-mini) - Realpolitik
    │
    └── Stage 3: CHAIRMAN SYNTHESIS
        └── Verdict + Dissenting Views + "What Might Be Missed"
```

## Trigger Conditions

This skill activates when:
- "Let's hear opinions from other AIs"
- "Summon the council"
- "Review this from multiple perspectives"
- "Ask codex and gemini for their opinions"
- "council"

## Usage

### Direct Script Execution

```bash
./skills/agent-council/scripts/council.sh "your question here"
```

### CLI Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show usage information |
| `-v, --verbose` | Show detailed error output including stderr from agents |
| `-n, --dry-run` | Preview what would be executed without running agents |
| `-b, --no-blind` | Disable blind mode (show real agent names to chairman) |
| `-r, --report FILE` | Save combined report to specific file (disables auto-output) |
| `-o, --output-dir DIR` | Save auto-generated reports to directory |

### Output Files

By default, the council generates **THREE markdown files** in the current directory:
- `council-minutes_TIMESTAMP.md` - Full deliberation with technical + ethical statements
- `council-ethics_TIMESTAMP.md` - Ethical sub-chair synthesis only
- `council-chairman-report_TIMESTAMP.md` - Chairman's verdict with dissenting views

### Examples

```bash
./council.sh --help
./council.sh -v "Compare React vs Vue"
./council.sh -o ./reports "Should we use microservices?"
./council.sh --dry-run "test prompt"
./council.sh --no-blind "test with real names"
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `COUNCIL_CONFIG` | Override the config file path |

Example:
```bash
COUNCIL_CONFIG=/path/to/custom.yaml ./council.sh "prompt"
```

## Ethical Frameworks

The council applies 6 distinct ethical lenses:

| Framework | Focus | Questions Asked |
|-----------|-------|-----------------|
| **Consequentialism** | Outcomes | Greatest good for greatest number? |
| **Deontology** | Duties | What rules apply regardless of outcome? |
| **Virtue Ethics** | Character | What would excellent character do? |
| **Pragmatism** | What works | What has actually worked before? |
| **Care Ethics** | Harm prevention | Who could be harmed? |
| **Realpolitik** | Power dynamics | What's the self-interested optimal move? |

## Chairman's Report Structure

The Chairman produces a structured report with:

1. **Battle Lines** - Where council members disagree
2. **Ethical Spectrum Analysis** - Which framework fits best
3. **Pressure Test** - Challenging the strongest arguments
4. **Uncomfortable Truths** - What's being avoided
5. **The Verdict** - Clear recommendation
6. **Dissenting Views** - Positions not adopted
7. **What The Chairman Might Have Missed** - Transparency section
8. **Confidence Assessment** - HIGH/MEDIUM/LOW
9. **Open Items** - Questions remaining

## Configuration

Edit `council.config.yaml` to customize:

```yaml
council:
  members:
    - name: gpt-5.2
      codename: "The Architect"
      command: "codex exec -m gpt-5.2"
      emoji: "🧠"
      color: "BLUE"
      strengths: "strategic planning, system design"
      persona: "You are a strategic thinker..."

  sub_chairs:
    - name: utilitarian
      codename: "The Utilitarian"
      command: "codex exec -m gpt-4o"
      emoji: "📊"
      color: "BLUE"
      framework: "Consequentialism"
      prompt: "You are a UTILITARIAN ethical advisor..."

  chairman:
    command: "claude -p --model claude-opus-4-5"

  settings:
    parallel: true
    timeout: 180
```

## Cost Considerations

- **Technical Council**: 7 API calls (parallel)
- **Ethical Sub-Chairs**: 6 API calls (parallel)
- **Chairman**: 1 API call (sequential, larger context)
- **Total**: ~14 API calls per council session

## File Structure

```
skills/agent-council/
├── SKILL.md              # This document
├── council.config.yaml   # Council configuration
├── .gitignore            # Ignores mapping file
└── scripts/
    └── council.sh        # Council execution script
```

## Requirements

CLI tools must be installed and authenticated:

```bash
codex --version   # OpenAI Codex CLI
gemini --version  # Google Gemini CLI
claude --version  # Anthropic Claude CLI
```

## Notes

- API costs incurred for each Agent call (~14 calls per session)
- Response time depends on the slowest Agent (timeout configurable)
- Do not share sensitive information with the council
- All models process in parallel where possible
