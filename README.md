# Piano Teacher Agent

An always-on agent that turns sheet music into a structured, step-by-step practice plan — no chat, no button clicks. Just drop a score on a kanban board, and it plans the practice for you.

**Built for:** AWS Builder Center — "Build an Always-On Agent" Weekend Challenge

## The Problem

Learning a new piano piece from a blank score is overwhelming — you don't know how to break it into a real practice plan. That's what a good teacher does, for a student or themselves. So I built an agent that does it: drop in the sheet music, and it plans the practice, lesson by lesson.

## How It Works

1. Add the sheet music to a local folder, then create a card for the song on the kanban board — title, score attached, assigned to `piano-teacher`.
2. Move the card to **Doing**.
3. The folder syncs to S3, which triggers the agent: a Lambda wakes up, runs a Strands agent that calls Claude Sonnet on Bedrock to read the score and decompose it into lessons.
4. The agent writes the lesson files and new lesson cards back to the bucket.
5. Sync the bucket back down, and everything appears locally — lesson files and board cards, ready to practice.

Each lesson is a bite-sized piece of the song — a phrase, a few bars — building up to the full piece, step by step.

## AWS Services Used

- **Amazon S3** — score input, kanban board file, lesson output storage; event source
- **AWS Lambda** — event handler and agent host
- **Amazon Bedrock (Claude Sonnet)** — multimodal score analysis, lesson decomposition, abc notation generation
- **Strands Agents SDK** — agent orchestration, hosted in-process inside the Lambda
- **MCP (Model Context Protocol)** — tool interface for kanban read/write, PDF read, and lesson-file write
- **IAM** — least-privilege role for Lambda (S3 read/write, Bedrock invoke)

## Obsidian Plugins Used

- [**Fancy Kanban**](https://github.com/robertoallende/fancy-kanban) — renders the `board.md` markdown file as an interactive kanban board, and is what actually gets edited (moving a card = editing the file) to trigger the agent
- [**ABC Music Notation**](https://github.com/abcjs-music/obsidian-plugin-abcjs) — renders and plays back the `abc` notation embedded in each generated lesson file, directly inside Obsidian

## Architecture

```
Local Folder (Obsidian)  ──sync──►  S3 Bucket  ──event──►  Lambda
   scores/  lessons/  board.md         │                  (Strands Agent
        ▲                              │                   + Bedrock Claude)
        │                              │                        │
        └──────────sync back───────────┴────writes lessons──────┘
                                          + updated board.md
```

## Development

This project follows [MMDD (Micromanaged Driven Development)](dev_log/00_mmdd.md) for AI-assisted development tracking. See `dev_log/00_main.md` for current status and unit breakdown.

## License

MIT