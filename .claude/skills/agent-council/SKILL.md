---
name: agent-council
description: Collect and synthesize opinions from multiple AI Agents. Use when users say "summon the council", "ask other AIs", or want multiple AI perspectives on a question.
---

# Agent Council

> Collect and synthesize opinions from multiple AI Agents
> Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)

## Overview

Agent Council gathers opinions from multiple AI Agents (Codex, Gemini, etc.) when facing difficult questions or decisions, with Claude acting as Chairman to synthesize the final response.

## Trigger Conditions

This skill activates when:
- "Let's hear opinions from other AIs"
- "Summon the council"
- "Review this from multiple perspectives"
- "Ask codex and gemini for their opinions"
- "council"

## 3-Stage Process (LLM Council Method)

### Stage 1: Initial Opinions
Send the same question to each council member to collect initial opinions

### Stage 2: Response Collection
Collect and display each Agent's response to the user

### Stage 3: Chairman Synthesis
Claude (Chairman) synthesizes all responses and presents the final opinion

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

Examples:
```bash
./council.sh --help
./council.sh -v "Compare React vs Vue"
./council.sh --dry-run "test prompt"
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `COUNCIL_CONFIG` | Override the config file path |

Example:
```bash
COUNCIL_CONFIG=/path/to/custom.yaml ./council.sh "prompt"
```

### Execution via Claude

1. Request council summon from Claude
2. Claude executes the script to collect each Agent's opinion
3. Claude synthesizes as Chairman and presents final recommendation

## Examples

### Technical Decision Making

```
User: "React vs Vue - which fits this project better? Summon the council"

Claude:
1. Execute council.sh to collect Codex, Gemini opinions
2. Organize each Agent's perspective
3. Recommend based on project context
```

### Architecture Review

```
User: "Let's hear other AIs' opinions on this design"

Claude:
1. Summarize current design and query the council
2. Collect feedback from each Agent
3. Analyze commonalities/differences and provide synthesis
```

## Council Members

Council members are configured in `council.config.yaml`. Default members:

| Agent | CLI Command | Characteristics |
|-------|-------------|-----------------|
| OpenAI Codex | `codex exec` | Code-focused, pragmatic approach |
| Google Gemini | `gemini` | Broad knowledge, diverse perspectives |
| Claude (Chairman) | - | Synthesis and final judgment |

## Requirements

- Each configured CLI must be installed and authenticated
- Default: OpenAI Codex CLI, Google Gemini CLI

### Verify Installation

```bash
codex --version
gemini --version
```

## Configuration

Edit `council.config.yaml` to customize council members:

```yaml
council:
  members:
    - name: codex
      command: "codex exec"
      emoji: "🤖"
      color: "BLUE"
    - name: gemini
      command: "gemini"
      emoji: "💎"
      color: "GREEN"
```

## File Structure

```
skills/agent-council/
├── SKILL.md              # This document
└── scripts/
    └── council.sh        # Council execution script
```

## Notes

- API costs incurred for each Agent call
- Response time depends on the slowest Agent
- Do not share sensitive information with the council
