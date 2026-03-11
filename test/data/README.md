# Test Replay Data

This directory contains real Slippi `.slp` replay files for testing peppi-mcp.

## Files

### game.slp
- **Size:** 988 KB (1,011,077 bytes)
- **Purpose:** Integration testing with real replay data
- **Usage:** Used by `test_with_real_replay.jl` to validate:
  - Directory scanning
  - File detection
  - Tool invocation
  - Query parsing

## Test Coverage

### Current (Phase 1)
✅ Directory scanning detects game.slp
✅ MCP tools correctly handle directory containing game.slp
✅ Query parsing extracts metadata (character, stage, outcome)
✅ Error messages are appropriate when parsing is stubbed

### After peppi-jl Integration (Phase 2+)
Once peppi-jl is integrated, this replay will be used to test:
- [ ] Replay parsing (metadata extraction)
- [ ] Frame data access (Arrow.Table structure)
- [ ] Statistics calculation (stocks, damage, neutral, punish, movement)
- [ ] Embedding generation
- [ ] Search ranking

## Running Tests

### Full test suite (unit + integration):
```bash
cd /home/jphardee/Desktop/Julia/JuliaGenAI/PeppiMCP
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Integration test with real replay:
```bash
julia --project=. test/test_with_real_replay.jl
```

Expected output shows:
- ✓ Directory scanning works
- ✓ File detection works
- ✓ Query parsing works
- ⚠️ Replay parsing blocked (peppi-jl not integrated)

## Adding More Test Replays

To add more test data:

1. Copy `.slp` files to this directory
2. They will automatically be detected by `scan_directory()`
3. Update tests if needed for specific matchup/character/stage testing

### Recommended Test Coverage

For comprehensive testing after peppi-jl integration:

- **Characters:** Fox, Falco, Marth, Sheik, Jigglypuff (top tiers)
- **Stages:** Battlefield, Final Destination, Yoshi's Story, Dream Land, Pokémon Stadium, Fountain of Dreams
- **Scenarios:**
  - Close game (last stock, high percent)
  - Dominant game (quick 4-stock)
  - Tech showcase (lots of wavedashes, L-cancels)
  - Timeout game (high damage, low stocks taken)
  - Combo-heavy game (punish/conversion testing)

## File Format Notes

`.slp` files are Slippi replay files containing:
- **Header:** Game metadata, player info, character IDs, stage ID
- **Frames:** Per-frame game state (positions, action states, inputs, stocks, percent)
- **Footer:** Game end condition (LRAS, timeout, quit)

Parsing requires peppi (Rust) via peppi-jl (Julia wrapper).
