# `peppi-mcp` — Developer Handover Specification

> Minimal, idiomatic Julia MCP server for Slippi `.slp` replay files.  
> Two tools: `search_replays`, `generate_stats`.

---

## 1. Background & Context

### Model Context Protocol (MCP)

MCP (spec: `2024-11-05`, stable as of 2025-11-25) is a JSON-RPC 2.0 transport-agnostic protocol for exposing tools, resources, and prompts to LLM clients. For a minimal server you need:

- **`tools/list`** — advertise tools with JSON Schema `inputSchema`
- **`tools/call`** — execute a named tool and return `TextContent` or `ImageContent`
- **stdio transport** — the standard for local MCP servers invoked by Claude Desktop / Claude Code

A tool is defined by:
```json
{
  "name": "tool_name",
  "description": "...",
  "inputSchema": { "type": "object", "properties": {...}, "required": [...] }
}
```
Errors should be returned as tool result errors (`isError: true`), **not** as JSON-RPC protocol errors.

### Julia MCP Libraries (pick one)

Two usable Julia MCP implementations exist as of early 2026:

| Package | Location | Notes |
|---|---|---|
| `ClaudeMCPTools.jl` | `github.com/JuliaBench/ClaudeMCPTools.jl` | Implements spec `2024-11-05`; implement `MCPTool` interface; call `run_stdio_server` |
| `ModelContextProtocol.jl` | `github.com/JuliaSMLM/ModelContextProtocol.jl` | Higher-level DSL; `mcp_server()` + `MCPTool(name, description, parameters, handler)` |

**Recommendation:** Use `ModelContextProtocol.jl` for its concise `MCPTool` + `mcp_server()` + `start!()` pattern. Fall back to `ClaudeMCPTools.jl` if you need lower-level control.

Minimal server skeleton:
```julia
using ModelContextProtocol

search_tool = MCPTool(
    name        = "search_replays",
    description = "Search .slp replay files by semantic query.",
    input_schema = Dict{String,Any}(
        "type" => "object",
        "properties" => Dict(
            "dir"   => Dict("type" => "string", "description" => "Path to replay folder"),
            "query" => Dict("type" => "string", "description" => "Natural language search query"),
            "top_k" => Dict("type" => "integer", "default" => 10)
        ),
        "required" => ["dir", "query"]
    ),
    handler = params -> TextContent(text = JSON3.write(search_replays(params)))
)

server = mcp_server(name="peppi-mcp", version="0.1.0", tools=[search_tool, stats_tool])
start!(server)
```

---

### peppi / peppi-jl

**peppi** (`crates.io/crates/peppi`, v2.1.2) is a Rust parser for `.slp` files. Key data model:

```
game.start          # metadata: stage, players, version, ...
game.frames         # columnar Arrow2 arrays, one column per field per port
game.frames.ports   # Vec<PortData> — indexed by port (0–3)
game.frames.id      # frame indices
game.end            # LRAS/timeout/...
```

Per-frame fields include (per port): `pre.state`, `pre.position`, `pre.direction`, `pre.joystick`, `pre.buttons`, `post.state`, `post.percent`, `post.stocks`, etc.

**peppi-jl** (`github.com/jph6366/peppi-jl`) wraps peppi via `jlrs` (Rust↔Julia FFI) and Apache Arrow, exposing frames as Julia `Arrow.Table`. It is an early prototype. The `ai/` and `db/` subdirectories contain experiments for embedding and database indexing that are directly relevant.

**Integration path for peppi-mcp:**
1. Depend on `peppi-jl` (or vendor it until it stabilises).
2. Call `peppi_jl.read_game(path)` → get `Arrow.Table` of frames + metadata struct.
3. All heavy lifting (parsing, Arrow layout) is done in Rust; Julia only does analytics/embedding.

---

## 2. Package Structure

```
peppi-mcp/
├── Project.toml
├── src/
│   ├── PeppiMCP.jl          # entry point, server definition
│   ├── parsing.jl           # wrap peppi-jl, load .slp → GameData
│   ├── stats.jl             # generate_stats implementation
│   ├── embeddings.jl        # replay-level embedding + indexing
│   └── search.jl            # search_replays implementation
└── bin/
    └── peppi-mcp            # thin script: `julia --project ... PeppiMCP.jl`
```

**`Project.toml` dependencies (minimal):**
```toml
[deps]
ModelContextProtocol = "..."   # or ClaudeMCPTools
JSON3        = "..."
Arrow        = "..."           # for frame data from peppi-jl
DataFrames   = "..."           # optional, for stats output
Statistics   = "..."
LinearAlgebra = "..."
# peppi-jl: add via URL until registered
# vector DB: see §4
```

---

## 3. Tool: `generate_stats`

### Goal

Produce competitive-focused, structured statistics from a set of `.slp` files. Richer and more accurate than `slippi-js`. Output should be DataFrames/Arrow-friendly for downstream data science.

### Input Schema

```json
{
  "dir":          { "type": "string" },
  "player_code":  { "type": "string", "description": "Slippi connect code e.g. ABCD#123" },
  "opponent_code":{ "type": "string" },
  "stage":        { "type": "string" },
  "character":    { "type": "string" },
  "date_from":    { "type": "string", "format": "date" },
  "date_to":      { "type": "string", "format": "date" }
}
```
`dir` is required; all others are optional filters.

### Stat Categories

**Core (per game, aggregated):**

| Stat | Description | Notes |
|---|---|---|
| `stocks_taken` / `stocks_lost` | raw stock differential | — |
| `damage_dealt` / `damage_taken` | total percent dealt/received | — |
| `damage_efficiency` | damage per opening | punish quality |
| `opening_rate` | openings per neutral interaction | — |
| `neutral_wins` | % of neutral interactions won | — |
| `avg_kill_percent` | mean % at which kills occurred | — |
| `avg_death_percent` | mean % at which you died | — |
| `self_destruct_count` | SD / LRAS frames | — |

**Punish / Conversion:**

| Stat | Description |
|---|---|
| `punish_count` | number of punishes |
| `avg_punish_damage` | damage per punish |
| `conversion_rate` | punishes that result in stock |
| `zero_to_death_count` | 0→death combos landed |

**Movement / Neutral:**

| Stat | Description |
|---|---|
| `dash_dance_count` | estimated via position reversals |
| `wavedash_count` | via `JumpF`→aerial→airdodge→land state sequence |
| `l_cancel_success_rate` | `LandingFallSpecial` + shield input timing |
| `ledgedash_count` | ledge regrab → fast-fall airdodge |
| `shield_pressure_received` | frames opponent is pressing shield vs you |

**Improvement tracking (requires multi-session data):**
- All stats above exposed as time-series keyed by `(date, opponent_code, stage)`.
- Rolling averages over last N games per stat.
- Optionally write to a local SQLite or Arrow file for persistence.

### Implementation Notes

- Frame iteration: filter `game.frames.id` to exclude rollback frames (`game.frames.rollbacks(ExceptLast)`).
- Action state enums: use `ssbm_data` constants mapped to integers (they are stable across `.slp` versions). Maintain a Julia `const` dict.
- L-cancel detection: landing lag frames < expected lag → success. Requires per-character frame data (embed a small lookup table).
- Return as `JSON3.write(stats_dict)` or, for bulk output, an Arrow IPC byte buffer that clients can decode with `Arrow.jl`.

---

## 4. Tool: `search_replays`

### Goal

Given a natural-language query (`"games where I lost a close last stock situation"`, `"Fox vs Marth on Battlefield"`), return ranked `.slp` file paths + summary metadata.

### Input Schema

```json
{
  "dir":   { "type": "string" },
  "query": { "type": "string" },
  "top_k": { "type": "integer", "default": 10 },
  "filters": {
    "type": "object",
    "properties": {
      "character": { "type": "string" },
      "stage":     { "type": "string" },
      "outcome":   { "type": "string", "enum": ["win", "loss", "any"] }
    }
  }
}
```

### Architecture

#### 4.1 Parsing pass (index time)

For each `.slp` in `dir`, call peppi-jl to extract:
- Game metadata (stage, characters, connect codes, duration, date, winner)
- Frame-level Arrow table

Cache parsed data to avoid re-parsing on repeated calls. Use a lightweight SQLite table or `.arrow` sidecar files keyed by file hash.

#### 4.2 Replay-level embeddings

The `slippi-ai` project (`github.com/vladfi1/slippi-ai`, `slippi_ai/embed.py`) embeds **individual game states (frames)** for imitation learning. These are not directly usable for replay retrieval, but the feature extraction logic is informative.

**Adaptation strategy — aggregate frame embeddings to replay level:**

```
Frame features (per frame, per port):
  - action state (one-hot or learned embedding)
  - position (x, y), percent, stocks remaining
  - joystick, cstick, buttons (raw)
  - direction, airborne flag

Aggregation options (choose one or combine):
  A. Temporal mean/std pooling over all frames → fixed-size vector
  B. Histogram of action states → ~400-dim sparse vector
  C. Statistics vector: (mean_pos_x, std_pos_y, modal_action_state,
       damage_dealt_ts_mean, ...)  → hand-crafted ~64-dim

Recommendation: Start with (C) — no ML model required, fast, interpretable.
Upgrade to (A) with a small trained encoder later if retrieval quality is insufficient.
```

**Concatenate with structured metadata features:**
```
[character_onehot (26), stage_onehot (6), outcome (1), 
 duration_seconds (1), avg_kill_pct (1), avg_death_pct (1)]
→ total embedding dim ≈ 100–200
```

#### 4.3 Vector index

For a minimal local implementation:

| Option | Julia package | Notes |
|---|---|---|
| Brute-force cosine | none (LinearAlgebra.jl) | Sufficient for <10k replays |
| HNSWlib | `HNSWlib.jl` (if available) | Fast ANN for large collections |
| SQLite + FTS5 | `SQLite.jl` | For structured/keyword queries |

**Start with brute-force** — it's correct, simple, and fast enough for personal replay folders (hundreds to low thousands of files). Store index as an `Arrow.Table` with columns `(path, embedding_vector)`.

#### 4.4 Query embedding

Embed the natural-language query using the same feature space:
- Parse query for known keywords: character names, stage names, outcomes, stats.
- Build a pseudo-feature vector from extracted terms.
- For free-form queries, use the Anthropic API's embeddings endpoint (text-embedding-3 or equivalent) if available, OR keep it keyword/filter-based for a truly minimal v1.

**Recommended v1 approach:** structured query parsing (no external embedding model needed):
```julia
function parse_query(q::String) :: QueryFilter
    # extract: character, stage, outcome, stats keywords
    # return filter struct + optional free-text remainder
end
```

Return: ranked list of `(path, score, metadata_summary)`.

---

## 5. Distribution via Yggdrasil

`peppi-mcp` depends on the peppi Rust library through `peppi-jl` (which uses `jlrs` FFI). This means distributing a prebuilt binary artifact.

### Path 1: peppi_jll (recommended)

1. Write a `build_tarballs.jl` for `peppi` (the Rust crate → `libpeppi.so/dylib/dll`).
2. Open a PR to `github.com/JuliaPackaging/Yggdrasil`.
3. Once merged, a `peppi_jll` package is generated and registered to General.
4. `peppi-jl` (and `peppi-mcp`) declare `peppi_jll` as a dependency.

**`build_tarballs.jl` skeleton:**
```julia
using BinaryBuilder, Pkg

name = "peppi"
version = v"2.1.2"

sources = [
    GitSource("https://github.com/hohav/peppi.git", "<commit-sha>")
]

script = raw"""
cd $WORKSPACE/srcdir/peppi
cargo build --release --lib
install -Dvm 755 target/${rust_target}/release/libpeppi.${dlext} ${libdir}/libpeppi.${dlext}
"""

platforms = supported_platforms()
filter!(p -> !Sys.iswindows(p), platforms)  # Windows support TBD

products = [LibraryProduct("libpeppi", :libpeppi)]

dependencies = [Dependency("Rust_jll")]  # or use cargo toolchain provided by BB

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
    julia_compat="1.6", preferred_gcc_version=v"9")
```

> Note: Rust cross-compilation in BinaryBuilder requires `--experimental` flags and the `Rust_jll` environment. See existing Yggdrasil Rust recipes (e.g., `R/ripgrep/`) for working examples.

### Path 2: ship as a script (interim)

Until Yggdrasil is done, distribute `peppi-mcp` with instructions to `cargo build` peppi locally. Put the resulting `.so` path in an `Artifacts.toml` override or env var. Less ideal but unblocks development.

---

## 6. Claude Desktop / Claude Code Configuration

```json
{
  "mcpServers": {
    "peppi-mcp": {
      "command": "julia",
      "args": ["--project=/path/to/peppi-mcp", "/path/to/peppi-mcp/bin/peppi-mcp.jl"],
      "env": {
        "PEPPI_MCP_INDEX_DIR": "~/.peppi-mcp/index"
      }
    }
  }
}
```

---

## 7. Implementation Sequence (suggested)

1. **Wire the MCP server** — bare stdio server returning hardcoded JSON for both tools. Confirm Claude Desktop sees the tools.
2. **Integrate peppi-jl** — parse a single `.slp`, log the Arrow schema. Confirm round-trip.
3. **Implement `generate_stats`** — start with 5–6 core stats. Write unit tests against a known replay.
4. **Implement `search_replays` v1** — directory scan + structured filter (no embeddings). Return matching files.
5. **Add embedding index** — hand-crafted feature vector, cosine brute-force. Test query quality.
6. **Yggdrasil PR** — package `peppi` as `peppi_jll`. Register `peppi-mcp` to General.

---

## 8. Key References

| Resource | URL |
|---|---|
| MCP Spec (stable) | `spec.modelcontextprotocol.io/specification/2024-11-05` |
| ClaudeMCPTools.jl | `github.com/JuliaBench/ClaudeMCPTools.jl` |
| ModelContextProtocol.jl | `github.com/JuliaSMLM/ModelContextProtocol.jl` |
| peppi (Rust) | `github.com/hohav/peppi` · `docs.rs/peppi/latest/peppi` |
| peppi-jl | `github.com/jph6366/peppi-jl` |
| slippi-ai (frame embeddings) | `github.com/vladfi1/slippi-ai` · `slippi_ai/embed.py` |
| Slippi .slp spec | `github.com/project-slippi/slippi-wiki/blob/master/SPEC.md` |
| BinaryBuilder / Yggdrasil | `docs.binarybuilder.org` · `github.com/JuliaPackaging/Yggdrasil` |
| ssbm-data (action states) | `crates.io/crates/ssbm-data` |

---

## 9. Constraints & Design Principles

- **No novelty stats** (APM, controller inputs per minute, etc.). Focus on competitive fundamentals.
- **No mandatory external services** — embedding index must work offline. Anthropic API embeddings are optional.
- **Minimal dependencies** — avoid pulling in ML frameworks (Flux, etc.) for v1.
- **Arrow-first output** — stats return JSON for MCP, but internally use Arrow/DataFrames so users can pipe into Plots.jl, Makie, R, pandas trivially.
- **Idiomatic Julia** — multiple dispatch for per-character stat variants, struct-typed game data, `@views` over Arrow columns, `nothing` over sentinel values.
- **peppi-jl is a prototype** — be prepared to vendor or patch it. The API may shift.
