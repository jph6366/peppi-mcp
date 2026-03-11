# Implementation Notes

This document tracks implementation progress and next steps for peppi-mcp.

## Current Status

### ✅ Completed

1. **Package Structure**
   - Created src/, bin/ directories
   - Project.toml with core dependencies
   - Module structure following spec

2. **MCP Server Core**
   - JSON-RPC 2.0 protocol implementation
   - stdio transport (readline from stdin, write to stdout)
   - tools/list and tools/call handlers
   - Proper error handling and response formatting

3. **Tool Definitions**
   - `generate_stats` with complete input schema
   - `search_replays` with complete input schema
   - All parameters properly typed and documented

4. **Module Stubs**
   - `parsing.jl` — directory scanning, GameData structures
   - `stats.jl` — statistics structures and calculation outlines
   - `embeddings.jl` — feature extraction and similarity functions
   - `search.jl` — query parsing and ranking logic

5. **Documentation**
   - README.md with usage instructions
   - Configuration examples for Claude Desktop/Code
   - .gitignore for Julia projects

### ⚠️ In Progress / Blocked

#### Critical Path: peppi-jl Integration

**Status:** Blocked on peppi-jl availability

**What's needed:**

1. **Add peppi-jl dependency** to Project.toml
   ```toml
   [deps]
   # Once peppi-jl is registered or via URL:
   # peppi_jl = "..."
   ```

2. **Implement `parse_replay()` in parsing.jl**
   ```julia
   using peppi_jl  # or whatever the package is called

   function parse_replay(path::String)::Union{GameData,Nothing}
       try
           game = peppi_jl.read_game(path)

           # Extract metadata
           metadata = GameMetadata(
               stage = game.start.stage,
               players = [
                   Dict(
                       "port" => p.port,
                       "character" => p.character_id,
                       "connect_code" => p.connect_code
                   )
                   for p in game.start.players
               ],
               start_time = game.start.timestamp,
               duration_frames = length(game.frames.id),
               version = game.start.version,
               winner = determine_winner(game)
           )

           # frames is already an Arrow.Table from peppi-jl
           return GameData(path, metadata, game.frames)
       catch e
           @error "Failed to parse $path" exception=e
           return nothing
       end
   end
   ```

3. **Implement frame data access patterns**

   Need to understand the Arrow schema from peppi-jl:
   ```julia
   # What columns exist in game.frames?
   # - frames.id (frame index)
   # - frames.ports[0].pre.state (action state)
   # - frames.ports[0].pre.position_x, position_y
   # - frames.ports[0].post.percent
   # - frames.ports[0].post.stocks_remaining
   # ... etc
   ```

4. **Map action state constants**

   Import from ssbm-data or peppi's constants:
   ```julia
   const ACTION_STATES = peppi_jl.ActionState
   # or manually maintain Julia const dict
   ```

#### Next Steps After peppi-jl Integration

### Phase 3: Statistics Implementation

**Priority: High**

1. **Core Stats (stats.jl)**
   - Implement `calculate_core_stats()` by iterating frames
   - Track stocks via `post.stocks_remaining` changes
   - Accumulate damage dealt/taken via `post.percent` deltas
   - Detect self-destructs (death while opponent stocks unchanged)

2. **Neutral Game Analysis**
   - Define "neutral interaction": both players in non-hitstun states
   - Opening: transition from neutral to opponent in hitstun
   - Opening rate: openings / neutral interactions
   - Damage efficiency: damage per opening

3. **Punish Detection (stats.jl)**
   - `detect_punishes()`: scan for hitstun → escape sequences
   - Track damage dealt during hitstun window
   - Conversion: punish that ends in stock loss
   - Zero-to-death: opponent at 0% at punish start, dies at end

4. **Movement Tech Detection (stats.jl)**
   - **L-cancel**: `LandingFallSpecial` state, check next frame for reduced lag
     - Requires per-character frame data (build lookup table)
   - **Wavedash**: `JumpF/JumpB` → aerial → airdodge → land sequence
   - **Dash dance**: `Dash` state with rapid direction reversals
   - **Ledgedash**: `CliffCatch` → airdodge → land

5. **Per-Game Granularity**
   - Calculate stats for each game individually
   - Store in `stats.per_game_stats` array
   - Return both aggregated and per-game data

### Phase 4: Search & Embeddings

**Priority: Medium**

1. **Frame Feature Aggregation (embeddings.jl)**
   ```julia
   function aggregate_frame_features(frames::Arrow.Table)
       # Access frames.ports[port].pre.*, frames.ports[port].post.*

       # Position stats
       pos_x = frames.ports[port].pre.position_x
       pos_y = frames.ports[port].pre.position_y
       mean_x, std_x = mean(pos_x), std(pos_x)
       mean_y, std_y = mean(pos_y), std(pos_y)

       # Action state histogram
       states = frames.ports[port].pre.state
       state_counts = countmap(states)  # requires StatsBase
       top_states = sort(collect(state_counts), by=x->x[2], rev=true)[1:20]

       # Damage trajectory
       percents = frames.ports[port].post.percent
       mean_pct, std_pct = mean(percents), std(percents)

       # etc.
       return [mean_x, std_x, mean_y, std_y, ..., histogram..., mean_pct, std_pct, ...]
   end
   ```

2. **Metadata Feature Encoding (embeddings.jl)**
   - Character one-hot: map `game.metadata.players[i].character` to CHARACTERS dict
   - Stage one-hot: map `game.metadata.stage` to STAGES dict
   - Identify player port: match connect code or port index convention
   - Determine outcome: `game.metadata.winner == player_port`

3. **Query Embedding (search.jl v2)**
   - Current: keyword-based, returns zero vector
   - Upgrade: use Anthropic text embeddings API
   ```julia
   using HTTP, JSON3

   function generate_query_embedding(query::SearchQuery)
       # Call Anthropic embedding endpoint (if available)
       # For now, keyword matching is sufficient
   end
   ```

4. **Index Persistence (search.jl)**
   - Cache embeddings to avoid re-parsing
   - Use Arrow file: `Arrow.write("index.arrow", embeddings_table)`
   - Check file hashes to detect changed replays
   - Store in `PEPPI_MCP_INDEX_DIR` env var location

### Phase 5: Distribution

**Priority: Low (post-v0.1.0)**

1. **Yggdrasil Recipe**
   - Write `build_tarballs.jl` for peppi (Rust → libpeppi.so/dylib/dll)
   - Submit PR to JuliaPackaging/Yggdrasil
   - Wait for `peppi_jll` to be generated

2. **Package Registration**
   - Register peppi-jl to Julia General (if not already)
   - Register peppi-mcp to Julia General
   - Update installation instructions to use Pkg.add

## Testing Strategy

### Unit Tests

Create `test/runtests.jl`:

```julia
using Test
using PeppiMCP

@testset "Parsing" begin
    # Test directory scanning
    files = scan_directory("test_replays/")
    @test length(files) > 0
    @test all(endswith(f, ".slp") for f in files)
end

@testset "Statistics" begin
    # Test with known replay
    # (requires test fixture .slp file)
end

@testset "Embeddings" begin
    # Test feature dimension consistency
    # Test normalization
end

@testset "Search" begin
    # Test query parsing
    @test extract_character_from_text("Fox vs Marth") == "Fox"
    @test extract_stage_from_text("on FD") == "Final Destination"
end
```

### Integration Tests

1. **MCP Protocol Test**
   - Send JSON-RPC requests via stdin
   - Verify response format
   - Check error handling

2. **End-to-End Test**
   - Place test replays in `test_replays/`
   - Call `generate_stats` with dir
   - Verify stats structure

## Known Issues

1. **peppi-jl unavailable**: Blocking progress on actual .slp parsing
2. **ModelContextProtocol.jl**: May need to use ClaudeMCPTools.jl instead if MCP.jl not available
3. **Arrow schema unknown**: Need to inspect peppi-jl output to understand column names
4. **Action state constants**: Need to import or vendor ssbm-data mappings

## Future Enhancements

- **Streaming stats**: Incremental updates as replays are parsed
- **Real-time index updates**: Watch directory for new replays
- **Advanced queries**: Boolean operators, date ranges, matchup filters
- **Visualizations**: Return matplotlib/Makie plots as ImageContent
- **Replay comparison**: Compare two sets of replays
- **Improvement tracking**: Time-series analysis of skill progression
- **Database backend**: SQLite for persistent stats storage

## Questions for Spec Author

1. Is peppi-jl API stable enough to depend on?
2. What is the exact Arrow schema from peppi-jl.read_game()?
3. Should we vendor peppi-jl source or wait for package registry?
4. Is ModelContextProtocol.jl the preferred MCP library, or should we use ClaudeMCPTools.jl?
