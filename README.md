# peppi-mcp

> Minimal, idiomatic Julia MCP server for Slippi `.slp` replay files

A Model Context Protocol (MCP) server that provides LLM clients with tools to analyze Super Smash Bros. Melee replay files. Built with Julia for high-performance statistical analysis and semantic search.

## Features

### Tools

- **`generate_stats`** — Generate competitive statistics from Slippi replays
  - Core stats: stocks, damage, neutral wins, opening rate
  - Punish analysis: conversion rate, zero-to-deaths, punish efficiency
  - Movement tech: wavedashes, L-cancels, dash dances, ledgedashes
  - Filterable by player, opponent, character, stage, date range

- **`search_replays`** — Semantic search over replay collections
  - Natural language queries ("close last stock games I lost")
  - Structural filters (character, stage, outcome)
  - Replay-level embeddings with cosine similarity ranking

## Installation

### Prerequisites

- Julia 1.9 or later
- Rust toolchain (installed automatically via `RustToolChain.jl`)

The server auto-installs `peppi-slp` from source on startup via `cargo install`.

### Setup

1. Clone this repository:
```bash
cd /path/to/peppi-mcp
```

2. Instantiate Julia dependencies:
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

3. Configure Claude Desktop/Code (see Configuration section)

## Configuration

### Claude Desktop

Add to your `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or equivalent:

```json
{
  "mcpServers": {
    "peppi-mcp": {
      "command": "julia",
      "args": [
        "--project=/path/to/peppi-mcp",
        "/path/to/peppi-mcp/bin/peppi-mcp.jl"
      ]
    }
  }
}
```

### Claude Code

Add to your `~/.claude/mcp.json`:

```json
{
  "peppi-mcp": {
    "command": "julia",
    "args": [
      "--project=/path/to/peppi-mcp",
      "/path/to/peppi-mcp/bin/peppi-mcp.jl"
    ]
  }
}
```

## Usage

Once configured, you can use the tools in your Claude conversations:

```
Generate stats for my replays:
> Use generate_stats with dir="/path/to/replays" and player_code="ABCD#123"

Search for specific game types:
> Use search_replays with dir="/path/to/replays" and query="Fox vs Marth games where I lost last stock"
```

## Implementation Status

✅ **MCP Server** — `ModelContextProtocol.jl`-based server with stdio transport, `generate_stats` and `search_replays` tools

✅ **Replay Parsing** — `.slp` and `.slpp` file support via `PeppiJlrs` (Rust/Julia FFI)

✅ **Statistics Engine** — `stats.jl`: stocks, damage, punish metrics, movement tech

✅ **Search & Embeddings** — `embeddings.jl` + `search.jl`: feature extraction and cosine similarity ranking

⏳ **Distribution** — Yggdrasil `build_tarballs.jl` for peppi, package registration

## Architecture

```
peppi-mcp/
├── Project.toml          # Julia package manifest
├── peppi/
│   ├── parse.jl          # Low-level Rust FFI bindings (PeppiJlrs)
│   └── game.jl           # Game, Frame, Player type definitions
├── src/
│   ├── PeppiMCP.jl       # Main module: MCP server, tool handlers, replay readers
│   ├── Internal.jl       # Internal utilities
│   ├── action_states.jl  # Melee action state definitions
│   ├── parsing.jl        # High-level .slp/.slpp parsing helpers
│   ├── stats.jl          # Statistics calculation
│   ├── embeddings.jl     # Replay-level feature vectors
│   └── search.jl         # Semantic search implementation
└── bin/
    └── peppi-mcp.jl      # Executable entry point
```

## Development

### Running Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Starting the Server

```bash
julia --project=. bin/peppi-mcp.jl
```

The server speaks the MCP protocol over stdio and is managed by `ModelContextProtocol.jl`.

## References

- [MCP Specification](https://spec.modelcontextprotocol.io/specification/2024-11-05)
- [peppi (Rust parser)](https://github.com/hohav/peppi)
- [peppi-jl (Julia wrapper)](https://github.com/jph6366/peppi-jl)
- [Slippi .slp Format](https://github.com/project-slippi/slippi-wiki/blob/master/SPEC.md)

## License

MIT
