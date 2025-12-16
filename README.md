# Agent Council

**[한국어 버전 (Korean)](./README.ko.md)**

> Collect and synthesize opinions from multiple AI Agents through a structured deliberation process.
> Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)

## Key Difference from LLM Council

**No additional API costs!**

Unlike Karpathy's LLM Council which directly calls each LLM's API (incurring costs), Agent Council uses CLI tools (Codex CLI, Gemini CLI, Claude CLI). This is especially useful if you have subscription plans for these services.

## Demo

https://github.com/user-attachments/assets/c550c473-00d2-4def-b7ba-654cc7643e9b

## Architecture

Agent Council implements a **3-stage deliberation process** with 14 AI participants:

```
THE CHAIRMAN (Opus 4.5) - Final Arbiter
    │
    ├── Stage 1: TECHNICAL COUNCIL (7 experts)
    │   ├── The Architect (GPT-5.2) - Strategic systems thinking
    │   ├── The Scholar (Codex-Max) - Deep technical analysis
    │   ├── The Sprinter (Codex-Mini) - Pragmatic speed
    │   ├── The Diplomat (Sonnet 4) - Balanced human factors
    │   ├── The Monk (Haiku 4.5) - First principles
    │   ├── The Oracle (Gemini Pro) - Research synthesis
    │   └── The Scout (Gemini Flash) - Pattern recognition
    │
    ├── Stage 2: ETHICAL SUB-CHAIRS (6 frameworks)
    │   ├── The Utilitarian - Consequentialism
    │   ├── The Kantian - Deontology
    │   ├── The Aristotelian - Virtue Ethics
    │   ├── The Pragmatist - What works
    │   ├── The Guardian - Care Ethics
    │   └── The Machiavelli - Realpolitik
    │
    └── Stage 3: CHAIRMAN SYNTHESIS
        └── Verdict + Dissenting Views + "What Might Be Missed"
```

### Blind Deliberation

By default, the Chairman sees only codenames (The Architect, The Scholar, etc.) - not actual model names. This prevents model-name bias and ensures arguments are judged on merit.

## Setup

### 1. Install via npx (Recommended)

```bash
npx github:beauNate/agent-council
```

This copies the skill files to your current project directory.

### 2. Install Agent CLIs

The default configuration requires these CLI tools:

```bash
# OpenAI Codex CLI
# https://github.com/openai/codex

# Google Gemini CLI
# https://github.com/google-gemini/gemini-cli

# Anthropic Claude CLI
# https://github.com/anthropics/claude-code
```

Verify installation:
```bash
codex --version
gemini --version
claude --version
```

## Usage

### Direct Script Execution

```bash
./skills/agent-council/scripts/council.sh "Your question here"
```

### CLI Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show usage information |
| `-v, --verbose` | Show detailed error output including stderr from agents |
| `-n, --dry-run` | Preview what would be executed without running agents |
| `-b, --no-blind` | Disable blind mode (show real agent names to chairman) |
| `-r, --report FILE` | Save combined report to specific file |
| `-o, --output-dir DIR` | Save auto-generated reports to directory |

### Examples

```bash
./skills/agent-council/scripts/council.sh "Compare React vs Vue for a dashboard"
./skills/agent-council/scripts/council.sh -v "Should we use microservices?"
./skills/agent-council/scripts/council.sh --dry-run "test prompt"
./skills/agent-council/scripts/council.sh --no-blind "test with real names"
```

### Via Claude (as a Skill)

Simply ask Claude to summon the council:

```
"Summon the council"
"Let's hear opinions from other AIs"
"Review this from multiple perspectives"
```

## Output Files

The council generates **three markdown files**:

- `council-minutes_TIMESTAMP.md` - Full deliberation with technical + ethical statements
- `council-ethics_TIMESTAMP.md` - Ethical sub-chair synthesis only
- `council-chairman-report_TIMESTAMP.md` - Chairman's verdict with dissenting views

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

Edit `skills/agent-council/council.config.yaml` to customize:

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
      framework: "Consequentialism"
      prompt: "You are a UTILITARIAN ethical advisor..."

  chairman:
    command: "claude -p --model claude-opus-4-5"

  settings:
    parallel: true
    timeout: 180
```

## Ethical Frameworks

The council applies 6 distinct ethical lenses:

| Framework | Focus | Key Question |
|-----------|-------|--------------|
| **Consequentialism** | Outcomes | Greatest good for greatest number? |
| **Deontology** | Duties | What rules apply regardless of outcome? |
| **Virtue Ethics** | Character | What would excellent character do? |
| **Pragmatism** | What works | What has actually worked before? |
| **Care Ethics** | Harm prevention | Who could be harmed? |
| **Realpolitik** | Power dynamics | What's the self-interested optimal move? |

## Cost Considerations

- **Technical Council**: 7 API calls (parallel)
- **Ethical Sub-Chairs**: 6 API calls (parallel)
- **Chairman**: 1 API call (sequential, larger context)
- **Total**: ~14 API calls per council session

With subscription plans (ChatGPT Plus, Claude Pro, Gemini Advanced), there are no additional API costs.

## Project Structure

```
agent-council/
├── skills/
│   └── agent-council/
│       ├── SKILL.md              # Detailed documentation
│       ├── council.config.yaml   # Council configuration
│       └── scripts/
│           └── council.sh        # Execution script
├── README.md                     # This file
├── README.ko.md                  # Korean documentation
└── LICENSE
```

## Notes

- Response time depends on the slowest agent (~2-3 minutes typical)
- Do not share sensitive information with the council
- All agents run in parallel where possible
- Timeout is configurable (default 180 seconds)

## Contributing

Contributions are welcome! Feel free to:
- Add support for new AI agents
- Improve the synthesis process
- Add new ethical frameworks
- Enhance the configuration options

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Credits

- Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)
- Built for use with [Claude Code](https://claude.ai/code)
