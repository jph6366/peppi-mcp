module PeppiMCP

include("Internal.jl")
include("../peppi/parse.jl")
include("../peppi/game.jl")

using .PeppiJlrs: read_slippi as _read_slippi, read_peppi as _read_peppi, get_start, get_end, get_metadata, get_frames_arrow_path
using RustToolChain
run(pipeline(`$(cargo()) install --git https://github.com/hohav/peppi-slp`, stdout=stderr, stderr=stderr))
using JSON
using Tar
using CodecZstd


function to_enum(EnumType, value)
    # If the value is already the right Enum type, return it
    value isa EnumType && return value
    # If it's nothing, return nothing (assuming the struct field allows it)
    value === nothing && return nothing

    if value isa AbstractString
        # Clean the string: remove spaces/underscores and uppercase
        val_clean = uppercase(replace(value, r"[\s_]" => ""))

        for instance in instances(EnumType)
            inst_str = uppercase(replace(string(instance), r"[\s_]" => ""))
            if inst_str == val_clean
                return instance
            end
        end
    elseif value isa Integer
        return EnumType(value)
    end

    @warn "Could not map value '$value' to Enum $EnumType"
    return nothing
end

function slp_slippi(path)
    arrow_tmp = tempname() * ".arrow"
    try
        # 2. Convert .slp to .slpp (Peppi v2 archive)
        # We point -o to a FILE path, not the directory
        run(pipeline(`slp -f json --verbose -o $arrow_tmp $path`, stdout=stderr, stderr=stderr))
#        g_raw = JSON.parse(rawjson)
        frames = JSON.parsefile(arrow_tmp)
        return frames.frames

    finally
        isfile(arrow_tmp) && rm(arrow_tmp)
        # Cleanup: removes the .slpp file and the extracted arrow/json files
    end
end

function parse_player(p)
    Player(
        port = to_enum(Port, p["port"]),
        character = Int(p["character"]),
        type = to_enum(PlayerType, p["type"]),
        stocks = Int(p["stocks"]),
        costume = Int(p["costume"]),
        team = p["team"] !== nothing ? Team(Int(p["team"]["color"]), Int(p["team"]["shade"])) : nothing,
        handicap = Int(p["handicap"]),
        bitfield = Int(p["bitfield"]),
        cpu_level = p["cpu_level"] !== nothing ? Int(p["cpu_level"]) : nothing,
        offense_ratio = Float64(p["offense_ratio"]),
        defense_ratio = Float64(p["defense_ratio"]),
        model_scale = Float64(p["model_scale"]),
        ucf = p["ucf"] !== nothing ? Ucf(
            to_enum(DashBack, p["ucf"]["dash_back"]),
            to_enum(ShieldDrop, p["ucf"]["shield_drop"])
        ) : nothing,
        name_tag = get(p, "name_tag", ""),
        netplay = (get(p, "netplay", nothing) !== nothing) ? Netplay(
            string(p["netplay"]["name"]),
            string(p["netplay"]["code"]),
            get(p["netplay"], "suid", nothing)
        ) : nothing
    )
end

"""
    read_slippi(path::String; skip_frames::Bool=false) -> Game

Read a Slippi replay file (.slp) and return a Game object.

# Arguments
- `path::String`: Path to the .slp file
- `skip_frames::Bool=false`: If true, skip parsing frame data

# Returns
- `Game`: Parsed game data including start, end, metadata, and frames
"""
function read_slippi(path::String; skip_frames::Bool=false)::Game
    g = _read_slippi(path, Int8(skip_frames))

    start_json = JSON.parse(get_start(g))
    stop_json = JSON.parse(get_end(g))
    metadata = JSON.parse(get_metadata(g))

    game_start = dc_from_json(GameStart, start_json)
    game_stop = isempty(stop_json) ? GameStop(method=UNRESOLVED) : dc_from_json(GameStop, stop_json)

    # Load frames from Arrow file if not skipping
    arrow_path = get_frames_arrow_path(g)
    frames = if isfile(arrow_path)
        open(arrow_path, "r") do io
            frames_table = Arrow.Table(io)
            frames_from_sa(frames_table.frame)
        end
    elseif skip_frames
        nothing
    end

    return Game(
        start=game_start,
        stop=game_stop,
        metadata=metadata,
        frames=frames
    )
end

"""
    read_peppi(path::String; skip_frames::Bool=false) -> Game

Read a Peppi replay file (.slpp) and return a Game object.

# Arguments
- `path::String`: Path to the .slpp file
- `skip_frames::Bool=false`: If true, skip parsing frame data

# Returns
- `Game`: Parsed game data including start, end, metadata, and frames
"""
function read_peppi(path::String; skip_frames::Bool=false)::Game
    g = _read_peppi(path, Int8(skip_frames))

    start_json = JSON.parse(get_start(g))
    end_json = JSON.parse(get_end(g))
    metadata = JSON.parse(get_metadata(g))

    game_start = dc_from_json(GameStart, start_json)
    game_end = isempty(end_json) ? GameStop(method=UNRESOLVED) : dc_from_json(GameStop, end_json)

    # Load frames from Arrow file if not skipping
    local frames
    if skip_frames
        frames = nothing
    else
        arrow_path = get_frames_arrow_path(g)
        if !isempty(arrow_path) && isfile(arrow_path)
            frames_table = Arrow.Table(arrow_path)
            frames = frames_from_sa(frames_table.frame)
        else
            frames = nothing
        end
    end

    return Game(
        start=game_start,
        stop=game_end,
        metadata=metadata,
        frames=frames
    )
end

using ModelContextProtocol
using Arrow
using DataFrames
using Statistics
using LinearAlgebra



# Include submodules
include("action_states.jl")
include("parsing.jl")
include("stats.jl")
include("embeddings.jl")
include("search.jl")

# 2. Define the Handler Functions
# These receive a single argument (usually a Dict or NamedTuple of params)
function handle_generate_stats(params)
    try
        # 'params' contains the arguments sent by the LLM
        stats_result = generate_stats(params)
        # Return a TextContent object (or a list of them)
        return TextContent(text = JSON.json(stats_result))
    catch e
        # Errors should be returned as text to be informative to the model
        return TextContent(text = "Error generating stats: $(sprint(showerror, e))")
    end
end

function handle_search_replays(params)
    try
        search_result = search_replays(params)
        return TextContent(text = JSON.json(search_result))
    catch e
        return TextContent(text = "Error searching replays: $(sprint(showerror, e))")
    end
end

# 3. Construct the MCPTool objects
# This replaces the manual 'const TOOLS' dictionary
generate_stats_tool = MCPTool(
    name = "generate_stats",
    description = "Generate competitive statistics from Slippi .slp replay files. Returns structured stats including stocks, damage, punish metrics, movement tech, and neutral game analysis.",
    parameters = [
        ToolParameter(name = "dir", type = "string", description = "Path to directory containing .slp replay files", required = true),
        ToolParameter(name = "player_code", type = "string", description = "Slippi connect code (e.g., ABCD#123) to filter for"),
        ToolParameter(name = "opponent_code", type = "string", description = "Opponent Slippi connect code to filter for"),
        ToolParameter(name = "stage", type = "string", description = "Stage name to filter for"),
        ToolParameter(name = "character", type = "string", description = "Character name to filter for"),
        ToolParameter(name = "date_from", type = "string", description = "Start date (YYYY-MM-DD)"),
        ToolParameter(name = "date_to", type = "string", description = "End date (YYYY-MM-DD)")
    ],
    handler = handle_generate_stats
)

search_replays_tool = MCPTool(
    name = "search_replays",
    description = "Search for Slippi replay files using natural language queries. Returns ranked list of paths with metadata.",
    parameters = [
        ToolParameter(name = "dir", type = "string", description = "Path to directory containing .slp replay files", required = true),
        ToolParameter(name = "query", type = "string", description = "Natural language search query", required = true),
        ToolParameter(name = "top_k", type = "integer", description = "Number of top results to return")
    ],
    handler = handle_search_replays
)

# 4. Create and Start the Server
# This manages the protocol handshake and JSON-RPC loop automatically
server = mcp_server(
    name = "peppi-mcp",
    version = "0.1.0",
    description = "Slippi Replay Analysis and Search Server",
    tools = [generate_stats_tool, search_replays_tool]
)

# Start the server (defaults to StdioTransport)
# This replaces the manual 'run_server()' function
run_server() = start!(server)

export read_slippi, read_peppi, Game, GameStart, GameStop, Frame, PortData, Data, Pre, Post
export Port, P1, P2, P3, P4
export PlayerType, HUMAN, CPU, DEMO
export Language, JAPANESE, ENGLISH
export DashBack, DASHBACK_UCF, DASHBACK_ARDUINO
export ShieldDrop, SHIELDDROP_UCF, SHIELDDROP_ARDUINO
export EndMethod, UNRESOLVED, TIME, GAME, RESOLVED, NO_CONTEST
export Player, Slippi, Scene, Match, Netplay, Team, Ucf, PlayerEnd

end # module PeppiMCP
