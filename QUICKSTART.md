# peppi-mcp Quick Start Guide

## Overview

peppi-mcp is now ready for Phase 1 deployment. The MCP server implements the protocol correctly and can be connected to Claude Desktop/Code, though full functionality requires peppi-jl integration.

## Quick Validation

### 1. Check Installation
```bash
cd /home/jphardee/Desktop/Julia/JuliaGenAI/PeppiMCP
julia --project=. test_load.jl
```

Expected output:
```
Module loaded successfully!
Available tools: 2
```

### 2. Run Protocol Tests
```bash
julia --project=. test_mcp_protocol.jl
```

Expected output:
```
All protocol tests passed! ✓
```

### 3. Start the Server (Manual Test)
```bash
julia --project=. bin/peppi-mcp.jl
```

The server will start and wait for JSON-RPC input on stdin. Test with:
```json
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
```

Press Ctrl+D to exit.

## Connecting to Claude Desktop

### macOS
1. Edit `~/Library/Application Support/Claude/claude_desktop_config.json`
2. Add:
```json
{
  "mcpServers": {
    "peppi-mcp": {
      "command": "julia",
      "args": [
        "--project=/home/jphardee/Desktop/Julia/JuliaGenAI/PeppiMCP",
        "/home/jphardee/Desktop/Julia/JuliaGenAI/PeppiMCP/bin/peppi-mcp.jl"
      ]
    }
  }
}
```

### Linux
Same as macOS, but config location is typically:
`~/.config/Claude/claude_desktop_config.json`

### Restart Claude Desktop
Close and reopen Claude Desktop. The peppi-mcp tools should appear.

## Testing with Claude

Once connected, try:

```
Can you list the available tools from peppi-mcp?
```

Claude should see two tools:
- `generate_stats` - Generate statistics from Slippi replays
- `search_replays` - Search replays semantically

**Note:** Both tools will return "no .slp files found" errors until peppi-jl is integrated. This is expected behavior.

## Current Limitations

✅ **Working:**
- MCP protocol (initialize, tools/list, tools/call)
- Tool definitions with proper schemas
- Directory scanning for .slp files
- Query parsing (character, stage, outcome extraction)
- Mathematical foundations (embeddings, similarity)

⚠️ **Stubbed (needs peppi-jl):**
- Actual .slp parsing
- Statistics calculation from frame data
- Replay embeddings from actual game data
- Semantic search ranking

## Next Steps

### For Developers
See `IMPLEMENTATION_NOTES.md` for detailed implementation tasks.

**Priority 1:** Integrate peppi-jl
- Add dependency to Project.toml
- Implement `parse_replay()` in `src/parsing.jl`
- Document Arrow schema from peppi-jl

**Priority 2:** Implement statistics
- Frame iteration and filtering
- Stock/damage tracking
- Punish detection
- Tech detection (wavedash, L-cancel, etc.)

### For Users
Wait for peppi-jl integration, or if you have .slp parsing working elsewhere, you can integrate it by:
1. Adding your parser as a dependency
2. Implementing `parse_replay()` to return `GameData` struct
3. Ensuring frames are returned as `Arrow.Table`

## Troubleshooting

### "Module not found" error
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### "No such file or directory" when starting server
Make sure to use absolute paths in claude_desktop_config.json.

### Server starts but tools don't appear in Claude
Check Claude Desktop logs (usually in `~/Library/Logs/Claude/` on macOS).

### Tools return errors about missing directory
This is expected - provide a directory path containing .slp files when calling the tools. The server correctly validates input but can't parse files yet.

## File Reference

- `README.md` - User documentation
- `STATUS.md` - Implementation status
- `IMPLEMENTATION_NOTES.md` - Developer guide
- `peppi-mcp-spec.md` - Original specification
- `src/` - All source code
- `test/` - Unit and integration tests

## Support

Report issues at: https://github.com/anthropics/claude-code/issues (for MCP protocol issues)

For peppi-jl integration questions, see: https://github.com/jph6366/peppi-jl
