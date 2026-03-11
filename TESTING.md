# peppi-mcp Testing Guide

## Test Status

### ✅ All Tests Passing (43/43)

```bash
cd /home/jphardee/Desktop/Julia/JuliaGenAI/PeppiMCP
julia --project=. -e 'using Pkg; Pkg.test()'
```

**Test Summary:**
```
Test Summary:  | Pass  Total  Time
PeppiMCP Tests |   43     43  1.8s
```

## Test Structure

### 1. Unit Tests (`test/runtests.jl`)

**Parsing Tests (7 tests)**
- Directory scanning (empty, mock files, real replay)
- File detection and filtering (.slp vs other files)
- parse_replay stub behavior

**Search Query Parsing Tests (16 tests)**
- Character extraction from natural language
  - "Fox vs Marth" → extracts character
  - "puff games" → "Jigglypuff"
  - "Playing as falco" → "Falco"
- Stage extraction
  - "on FD" → "Final Destination"
  - "battlefield games" → "Battlefield"
  - "yoshis story" → "Yoshi's Story"
- Outcome extraction
  - "games I won" → "win"
  - "matches I lost" → "loss"
- Keyword extraction with stop word filtering

**Embeddings Tests (5 tests)**
- Vector normalization (unit length)
- Cosine similarity calculation
- Edge cases (zero vectors, orthogonal, opposite)

**MCP Protocol Tests (7 tests)**
- JSON-RPC response formatting
- Error response handling
- Request routing

**Tool Definition Tests (8 tests)**
- Tool count verification
- Input schema validation
- Required parameter checking

### 2. Integration Tests (`test/test_with_real_replay.jl`)

**With Real Replay Data (`test/data/game.slp` - 988 KB)**

Tests the full workflow with actual .slp file:

1. **Directory Scanning** ✅
   - Finds game.slp in test/data/
   - Correctly identifies .slp extension
   - Returns full path

2. **Tool Invocation** ✅
   - generate_stats with real directory
   - search_replays with real directory
   - Proper error handling when parsing is stubbed

3. **Query Parsing** ✅
   - "Fox vs Marth on Battlefield" → Character: Marth, Stage: Battlefield
   - "games where I won with Falco" → Character: Falco, Outcome: win
   - "close last stock matches on FD" → Stage: Final Destination
   - "puff games on Dreamland" → Character: Jigglypuff, Stage: Dream Land

4. **MCP Protocol** ✅
   - Correct JSON-RPC formatting
   - Tool content wrapping (TextContent)
   - Error responses when parsing unavailable

### 3. Protocol Tests (`test_mcp_protocol.jl`)

Standalone JSON-RPC protocol validation:
- initialize request/response
- tools/list request/response
- tools/call routing
- Unknown method error handling

## Running Tests

### Quick test (all unit tests)
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Integration test with real replay
```bash
julia --project=. test/test_with_real_replay.jl
```

### MCP protocol test
```bash
julia --project=. test_mcp_protocol.jl
```

### Module load test
```bash
julia --project=. test_load.jl
```

## Expected Behavior

### Phase 1 (Current)
✅ **Working:**
- All 43 unit tests pass
- Directory scanning works
- Query parsing works
- MCP protocol works
- Tool definitions valid

⚠️ **Stubbed (returns appropriate errors):**
- Replay parsing (parse_replay returns nothing)
- Statistics calculation (returns "no replays matched")
- Search ranking (returns "no replays matched")

### Phase 2 (After peppi-jl Integration)

Once peppi-jl is integrated, the same tests will validate:
- ✅ Replay parsing (metadata + frames)
- ✅ Statistics calculation from real frame data
- ✅ Embedding generation from real replays
- ✅ Search ranking with actual similarity scores

## Test Data

### Current Test Replay
- **File:** `test/data/game.slp`
- **Size:** 988 KB (1,011,077 bytes)
- **Date:** Nov 24, 2024
- **Usage:** Integration testing

See `test/data/README.md` for details on test data.

### Adding More Test Data

Simply copy `.slp` files to `test/data/`:
```bash
cp ~/path/to/replay.slp test/data/
```

They will automatically be detected by directory scanning.

## Test Output Example

```
Testing with real replay file...
File: /path/to/PeppiMCP/test/data/game.slp
Size: 1011077 bytes

Test 1: Directory Scanning
========================================
Found 1 .slp file(s):
  - game.slp
✓ Directory scanning works!

Test 2: Parse Replay
========================================
⚠ parse_replay returned nothing (expected - peppi-jl not integrated)
Once peppi-jl is integrated, this will return GameData with:
  - metadata: stage, players, characters, duration, winner
  - frames: Arrow.Table with per-frame data

[... more tests ...]

============================================================
SUMMARY
============================================================
✓ Directory scanning: WORKING
✓ File detection: WORKING (found game.slp)
✓ MCP protocol: WORKING
✓ Tool invocation: WORKING
✓ Query parsing: WORKING

⚠ Replay parsing: BLOCKED (needs peppi-jl)
⚠ Statistics: BLOCKED (needs peppi-jl)
⚠ Search ranking: BLOCKED (needs peppi-jl)

Next step: Integrate peppi-jl to unlock full functionality
```

## Continuous Integration

### Manual Testing Workflow

Before committing changes:
1. Run full test suite: `julia --project=. -e 'using Pkg; Pkg.test()'`
2. Run integration test: `julia --project=. test/test_with_real_replay.jl`
3. Verify module loads: `julia --project=. test_load.jl`
4. Check protocol: `julia --project=. test_mcp_protocol.jl`

### Future CI/CD

Once published, add GitHub Actions workflow:
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: julia-actions/setup-julia@v1
      - uses: julia-actions/julia-runtest@v1
```

## Test Coverage

Current test coverage focuses on:
- ✅ Protocol compliance (MCP spec 2024-11-05)
- ✅ Input validation (required params, types)
- ✅ Error handling (graceful degradation)
- ✅ Query parsing (NLP extraction)
- ✅ Mathematical correctness (embeddings, similarity)

Future coverage after peppi-jl:
- [ ] Frame data accuracy
- [ ] Statistics correctness (compare to ground truth)
- [ ] Embedding quality (search relevance)
- [ ] Performance (large replay collections)

## Debugging Failed Tests

### Module Load Errors
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Parse Errors
Check syntax with:
```bash
julia --project=. -e 'push!(LOAD_PATH, "src"); using PeppiMCP'
```

### Test-Specific Failures
Run individual test sets:
```julia
julia> using Test, PeppiMCP
julia> @testset "Parsing" begin
    # ... copy test code ...
end
```

## Known Warnings

These warnings are expected in Phase 1:

```
⚠ parse_replay not yet implemented - peppi-jl integration pending
```

This is by design - the warning will disappear once peppi-jl is integrated.
