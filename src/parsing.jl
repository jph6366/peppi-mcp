"""
Parsing module - wraps peppi_jlrs to load .slp files and return structured game data
"""

using Arrow

# Stage ID to name mapping (from Melee stage list)
const STAGE_NAMES = Dict{Int, String}(
    2 => "Fountain of Dreams",
    3 => "Pokémon Stadium",
    8 => "Yoshi's Story",
    28 => "Dream Land",
    31 => "Battlefield",
    32 => "Final Destination"
)

# Character ID to name mapping
const CHARACTER_NAMES = Dict{Int, String}(
    0 => "Captain Falcon", 1 => "Donkey Kong", 2 => "Fox", 3 => "Mr. Game & Watch",
    4 => "Kirby", 5 => "Bowser", 6 => "Link", 7 => "Luigi",
    8 => "Mario", 9 => "Marth", 10 => "Mewtwo", 11 => "Ness",
    12 => "Peach", 13 => "Pikachu", 14 => "Ice Climbers", 15 => "Jigglypuff",
    16 => "Samus", 17 => "Yoshi", 18 => "Zelda", 19 => "Sheik",
    20 => "Falco", 21 => "Young Link", 22 => "Dr. Mario", 23 => "Roy",
    24 => "Pichu", 25 => "Ganondorf"
)

# Update your struct definition to allow keyword arguments
Base.@kwdef struct GameMetadata
    stage::String
    stage_id::Int
    players::Vector{Dict{String, Any}}
    duration_frames::Int
    version::String
    winner::Union{Int, Nothing}
    is_teams::Bool
    game_start::GameStart
    game_end::GameStop
    start_time::Union{String, Nothing}
end

"""
    GameMetadata(d::Dict, gs::GameStart, ge::GameStop)

Custom constructor to bridge the gap between the JSON Dict and the Metadata struct.
"""
function GameMetadata(d::Dict, gs::GameStart, ge::GameStop)
    # The 'slp' tool provides 'lastFrame' in metadata.
    # Slippi frames usually start at -123, so duration is lastFrame + 123.
    last_frame = get(d, "lastFrame", 0)
    duration = last_frame > 0 ? last_frame + 123 : 0

    # Extract players from metadata dict
    # Note: 'slp' metadata players is a Dict ("0" => {...}), we want a Vector
    meta_players = get(d, "players", Dict())
    players_vec = Dict{String, Any}[]
    for (port_idx, pdata) in meta_players
        push!(players_vec, Dict{String, Any}(
            "port" => port_idx,
            "data" => pdata
        ))
    end

    # Determine winner (simplified logic: check placement in GameStop)
    winner = nothing
    if ge.players !== nothing
        for p in ge.players
            if p.placement == 0
                winner = Int(p.port)
                break
            end
        end
    end
    return GameMetadata(
        stage = string(gs.stage), # Or a mapping function to get stage name "Final Destination"
        stage_id = gs.stage,
        players = players_vec,
        duration_frames = duration,
        version = join(gs.slippi.version, "."),
        winner = winner,
        is_teams = gs.is_teams,
        game_start = gs,
        game_end = ge,
        start_time = get(d, "startAt", nothing)
    )
end

# Complete game data structure
struct GameData
    path::String
    metadata::GameMetadata
    frames::Union{Frame,Nothing}
    raw_game::Game
end

"""
    has_game_end_event(path::String) -> Bool

Scan a .slp file's raw event stream for the GameEnd event (0x39).
peppi_jlrs panics with UnexpectedEOF when this event is missing (in-progress
or aborted games), so we must check before calling into Rust.
"""
function has_game_end_event(path::String)::Bool
    try
        open(path, "r") do io
            # UBJSON header: { U 3 "raw" [ $ U # l <int32 big-endian>
            header = read(io, 15)
            length(header) < 15 && return false
            header[1] == 0x7B || return false  # must start with '{'

            raw_size = (Int(header[12]) << 24) | (Int(header[13]) << 16) |
                       (Int(header[14]) << 8)  | Int(header[15])

            # First event must be Event Payloads (0x35)
            read(io, 1)[1] == 0x35 || return false

            payload_sz = Int(read(io, 1)[1])  # includes itself
            num_entries = (payload_sz - 1) ÷ 3

            event_sizes = Dict{UInt8,Int}()
            for _ in 1:num_entries
                code  = read(io, 1)[1]
                hi    = Int(read(io, 1)[1])
                lo    = Int(read(io, 1)[1])
                event_sizes[code] = (hi << 8) | lo
            end

            GAME_END = UInt8(0x39)
            haskey(event_sizes, GAME_END) || return false

            # Walk the event stream
            bytes_read = 1 + payload_sz  # Event Payloads event consumed
            while bytes_read < raw_size
                code_arr = read(io, 1)
                isempty(code_arr) && return false
                code = code_arr[1]
                bytes_read += 1
                code == GAME_END && return true
                sz = get(event_sizes, code, nothing)
                sz === nothing && return false  # unknown event
                skip(io, sz)
                bytes_read += sz
            end
            return false
        end
    catch
        return false
    end
end

"""
    parse_replay(path::String) -> GameData

Parse a .slp file and return structured game data using peppi_jlrs.
"""
function parse_replay(path::String)::Union{GameData,Nothing}
    if !isfile(path)
        return nothing
    end
    if !has_game_end_event(path)
        @warn "Skipping in-progress/aborted replay (no GameEnd event): $(basename(path))"
        return nothing
    end
    try
        game = read_slippi(path)
        metadata = extract_metadata(game)
        GameData(path, metadata, game.frames, game)
    catch e
        @error "Failed to parse replay: $path" exception=(e, catch_backtrace())
        return nothing
    end
end

"""
    scan_directory(dir::String) -> Vector{String}

Recursively scan directory for .slp files
"""
function scan_directory(dir::String)::Vector{String}
    replay_files = String[]

    if !isdir(dir)
        @error "Directory does not exist: $dir"
        return replay_files
    end

    for (root, dirs, files) in walkdir(dir)
        for file in files
            if endswith(lowercase(file), ".slp")
                push!(replay_files, joinpath(root, file))
            end
        end
    end

    return replay_files
end

"""
    extract_metadata(game::Game) -> GameMetadata

Extract metadata from parsed peppi game object
"""
function extract_metadata(game::Game)::GameMetadata
    start = game.start

    # Get stage name
    stage_name = get(STAGE_NAMES, start.stage, "Unknown ($(start.stage))")

    # Extract player information
    players = Dict{String,Any}[]
    for player in start.players
        player_info = Dict{String,Any}(
            "port" => Int(player.port),
            "character" => get(CHARACTER_NAMES, player.character, "Unknown ($(player.character))"),
            "character_id" => player.character,
            "type" => string(player.type),
            "stocks" => player.stocks,
            "costume" => player.costume
        )

        # Add netplay info if available
        if player.netplay !== nothing
            player_info["netplay_name"] = player.netplay.name
            player_info["connect_code"] = player.netplay.code
        end

        push!(players, player_info)
    end

    # Determine duration (count frames if available)
    duration_frames = if game.frames !== nothing && game.frames.id !== nothing
        length(game.frames.id)
    else
        0
    end

    # Determine winner from game end data (players is nothing when game ended unresolved)
    winner = nothing
    stop = game.stop
    if stop.players !== nothing
        for player_end in stop.players
            if player_end.placement == 0
                winner = Int(player_end.port)
                break
            end
        end
    end

    # Get version string
    version_tuple = start.slippi.version
    version_str = "$(version_tuple[1]).$(version_tuple[2]).$(version_tuple[3])"

    # Extract start timestamp (Slippi stores it as "startAt" in metadata)
    start_time = get(game.metadata, "startAt", nothing)

    return GameMetadata(
        stage_name,          # stage
        start.stage,         # stage_id
        players,             # players
        duration_frames,     # duration_frames
        version_str,         # version
        winner,              # winner
        start.is_teams,      # is_teams
        start,               # game_start
        game.stop,           # game_end (always a GameStop, method=UNRESOLVED if no end data)
        start_time           # start_time
    )
end

"""
    get_player_port(game::GameData, connect_code::Union{String,Nothing}) -> Union{Int,Nothing}

Find the port index for a player by connect code. Returns nothing if not found.
"""
function get_player_port(game::GameData, connect_code::Union{String,Nothing})::Union{Int,Nothing}
    if connect_code === nothing
        return nothing
    end

    for player in game.metadata.players
        if haskey(player, "connect_code") && player["connect_code"] == connect_code
            return player["port"]
        end
    end

    return nothing
end
