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
- peppi-jl (integration pending - see spec)

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
      ],
      "env": {
        "PEPPI_MCP_INDEX_DIR": "~/.peppi-mcp/index"
      }
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

✅ **Phase 1: MCP Server Skeleton**
- JSON-RPC 2.0 stdio transport
- Tool definitions with JSON Schema
- Basic request/response handling

✅ **Phase 2: Core Integrations** (in progress)
- peppi-jl integration pending
- Frame data parsing stubbed
- Statistics calculation outlined

✅ **Phase 3: Statistics Engine**
- Core stats algorithms
- Punish detection
- Movement tech detection

✅ **Phase 4: Search & Embeddings**
- Replay-level feature extraction
- Query parsing
- Similarity ranking

⏳ **Phase 5: Distribution**
- Yggdrasil build_tarballs.jl for peppi
- Package registration

## Architecture

```
peppi-mcp/
├── Project.toml          # Julia package manifest
├── src/
│   ├── PeppiMCP.jl       # Main module, MCP server, JSON-RPC handling
│   ├── parsing.jl        # peppi-jl wrapper, .slp → GameData
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

### Testing the Server Manually

```bash
julia --project=. bin/peppi-mcp.jl
```

Then send JSON-RPC requests via stdin:
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
```

## References

- [MCP Specification](https://spec.modelcontextprotocol.io/specification/2024-11-05)
- [peppi (Rust parser)](https://github.com/hohav/peppi)
- [peppi-jl (Julia wrapper)](https://github.com/jph6366/peppi-jl)
- [Slippi .slp Format](https://github.com/project-slippi/slippi-wiki/blob/master/SPEC.md)

## License

MIT
