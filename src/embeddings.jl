"""
Embeddings module - generates replay-level feature vectors for semantic search
Aggregates frame-level data into fixed-size embeddings
"""

using Statistics
using LinearAlgebra

# Stage IDs (common competitive stages)
const STAGES = Dict(
    "Fountain of Dreams" => 0, "Pokémon Stadium" => 1, "Yoshi's Story" => 2,
    "Dream Land" => 3, "Battlefield" => 4, "Final Destination" => 5
)

# Number of Melee character IDs (0–25)
const NUM_CHARS = 26

# Total embedding dimension: 2*26 chars + 6 stages + 2 scalar + 38 frame = 98
const EMBEDDING_DIM = 2 * NUM_CHARS + 6 + 2 + 38

"""
Replay embedding structure
Fixed-size feature vector for semantic search
"""
struct ReplayEmbedding
    path::String
    features::Vector{Float64}
    metadata::Dict{String,Any}
end

"""
    generate_embedding(game::GameData) -> ReplayEmbedding

Generate a replay-level embedding from parsed game data.
Combines structural metadata with aggregated frame statistics.
"""
function generate_embedding(game::GameData)::ReplayEmbedding
    meta_features = extract_metadata_features(game.metadata)
    frame_features = aggregate_frame_features(game.frames)
    features = vcat(meta_features, frame_features)
    features = normalize_vector(features)

    return ReplayEmbedding(
        game.path,
        features,
        Dict{String,Any}(
            "stage" => game.metadata.stage,
            "duration_frames" => game.metadata.duration_frames,
            "winner" => game.metadata.winner
        )
    )
end

"""
    extract_metadata_features(metadata::GameMetadata) -> Vector{Float64}

Convert structured metadata to feature vector:
- Character one-hot (NUM_CHARS dims per port, 2 ports = 2*NUM_CHARS total)
- Stage one-hot (6 dims)
- Outcome (1 dim: win=1.0, loss=0.0, unknown=0.5)
- Duration (1 dim, normalized to ~5 min = 18000 frames)

Total: 2*26 + 6 + 1 + 1 = 60 features
"""
function extract_metadata_features(metadata::GameMetadata)::Vector{Float64}
    features = Float64[]

    # Character one-hot encoding for ports 1 and 2 using character_id (0-indexed Melee IDs)
    for port_idx in 1:2
        char_vec = zeros(Float64, NUM_CHARS)
        if port_idx <= length(metadata.players)
            char_id = get(metadata.players[port_idx], "character_id", -1)
            if 0 <= char_id < NUM_CHARS
                char_vec[char_id + 1] = 1.0
            end
        end
        append!(features, char_vec)
    end

    # Stage one-hot
    stage_vec = zeros(Float64, length(STAGES))
    stage_idx = get(STAGES, metadata.stage, -1)
    if 0 <= stage_idx < length(STAGES)
        stage_vec[stage_idx + 1] = 1.0
    end
    append!(features, stage_vec)

    # Outcome from port 1 player's perspective
    p1_port_val = length(metadata.players) > 0 ? get(metadata.players[1], "port", -1) : -1
    outcome = if metadata.winner !== nothing && metadata.winner == p1_port_val
        1.0
    elseif metadata.winner !== nothing
        0.0
    else
        0.5
    end
    push!(features, outcome)

    # Duration normalized to ~5 min = 18000 frames
    duration_norm = min(metadata.duration_frames / 18000.0, 2.0)
    push!(features, duration_norm)

    return features
end

"""
    aggregate_frame_features(frames::Union{Frame,Nothing}) -> Vector{Float64}

Aggregate frame-level data into statistical features per port:
- Position stats (mean_x, std_x, mean_y, std_y) × 2 ports  →  8
- Action state histogram (top 20 states for port 1)          → 20
- Damage stats (mean_pct, std_pct) × 2 ports                 →  4
- Mean stocks remaining × 2 ports                            →  2
- Joystick magnitude stats (mean, std) × 2 ports             →  4

Total: 38 features
"""
function aggregate_frame_features(frames::Union{Frame,Nothing})::Vector{Float64}
    features = Float64[]

    if frames === nothing || isempty(frames.ports)
        return zeros(Float64, 38)
    end

    # Position stats per port (4 per port × 2 = 8)
    for port_idx in 1:2
        if port_idx <= length(frames.ports)
            pos = frames.ports[port_idx].leader.pre.position
            append!(features, _arr_mean_std(pos.x))
            append!(features, _arr_mean_std(pos.y))
        else
            append!(features, zeros(Float64, 4))
        end
    end

    # Action state histogram for port 1 (20 features)
    append!(features, calculate_action_state_histogram(frames, 1, 20))

    # Damage and stock stats per port (3 per port × 2 = 6)
    for port_idx in 1:2
        if port_idx <= length(frames.ports)
            post = frames.ports[port_idx].leader.post
            append!(features, _arr_mean_std(post.percent))
            push!(features, _arr_mean(post.stocks))
        else
            append!(features, zeros(Float64, 3))
        end
    end

    # Joystick magnitude stats per port (2 per port × 2 = 4)
    for port_idx in 1:2
        if port_idx <= length(frames.ports)
            joy = frames.ports[port_idx].leader.pre.joystick
            push!(features, _joystick_mean_mag(joy))
            push!(features, _joystick_std_mag(joy))
        else
            append!(features, zeros(Float64, 2))
        end
    end

    return features
end

"""
    calculate_action_state_histogram(frames::Union{Frame,Nothing}, port::Int, top_k::Int=20) -> Vector{Float64}

Calculate normalized frequency histogram of the top_k most common action states for a port.
"""
function calculate_action_state_histogram(frames::Union{Frame,Nothing}, port::Int, top_k::Int=20)::Vector{Float64}
    if frames === nothing || port < 1 || port > length(frames.ports)
        return zeros(Float64, top_k)
    end

    state_arr = frames.ports[port].leader.pre.state
    if state_arr === nothing
        return zeros(Float64, top_k)
    end

    state_counts = Dict{Int,Int}()
    for s in skipmissing(state_arr)
        k = Int(s)
        state_counts[k] = get(state_counts, k, 0) + 1
    end

    if isempty(state_counts)
        return zeros(Float64, top_k)
    end

    total = sum(values(state_counts))
    sorted = sort(collect(state_counts), by=x -> x[2], rev=true)

    hist = zeros(Float64, top_k)
    for i in 1:min(top_k, length(sorted))
        hist[i] = sorted[i][2] / total
    end
    return hist
end

"""
    normalize_vector(v::Vector{Float64}) -> Vector{Float64}

Normalize vector to unit length (L2 norm).
"""
function normalize_vector(v::Vector{Float64})::Vector{Float64}
    norm_val = norm(v)
    return norm_val > 0 ? v ./ norm_val : v
end

"""
    cosine_similarity(a::Vector{Float64}, b::Vector{Float64}) -> Float64

Calculate cosine similarity between two vectors.
"""
function cosine_similarity(a::Vector{Float64}, b::Vector{Float64})::Float64
    if length(a) != length(b)
        return 0.0
    end
    return dot(a, b) / (norm(a) * norm(b) + 1e-10)
end

"""
    _cache_path(replay_dir::String) -> String

Return the Arrow cache file path for the given replay directory.
Respects the PEPPI_MCP_INDEX_DIR environment variable (default: ~/.peppi_mcp/).
"""
function _cache_path(replay_dir::String)::String
    cache_root = get(ENV, "PEPPI_MCP_INDEX_DIR",
                     joinpath(homedir(), ".peppi_mcp"))
    mkpath(cache_root)
    # Sanitize the absolute dir path into a safe filename
    key = replace(abspath(replay_dir), r"[^a-zA-Z0-9]" => "_")
    # Trim to avoid filesystem limits (keep the tail which is most unique)
    key = length(key) > 180 ? key[end-179:end] : key
    return joinpath(cache_root, key * ".arrow")
end

"""
    load_index_cache(replay_dir::String) -> Dict{String, Tuple{Float64, ReplayEmbedding}}

Load the Arrow embedding cache for replay_dir.
Returns a dict mapping file path → (mtime, ReplayEmbedding).
"""
function load_index_cache(replay_dir::String)::Dict{String, Tuple{Float64, ReplayEmbedding}}
    cache_file = _cache_path(replay_dir)
    result = Dict{String, Tuple{Float64, ReplayEmbedding}}()
    isfile(cache_file) || return result
    try
        tbl = Arrow.Table(cache_file)
        for (path, mt, feat, meta_json) in
                zip(tbl.path, tbl.mtime, tbl.features, tbl.metadata_json)
            meta = try JSON.parse(String(meta_json)) catch; Dict{String,Any}() end
            emb  = ReplayEmbedding(String(path), Vector{Float64}(feat), meta)
            result[String(path)] = (Float64(mt), emb)
        end
    catch e
        @warn "Failed to load embedding cache from $cache_file: $e"
    end
    return result
end

"""
    save_index_cache(replay_dir::String, embeddings::Vector{ReplayEmbedding},
                     mtimes::Dict{String,Float64})

Persist embeddings to the Arrow cache file for replay_dir.
"""
function save_index_cache(replay_dir::String,
                          embeddings::Vector{ReplayEmbedding},
                          mtimes::Dict{String,Float64})
    cache_file = _cache_path(replay_dir)
    try
        tbl = (
            path          = [e.path              for e in embeddings],
            mtime         = [get(mtimes, e.path, 0.0) for e in embeddings],
            features      = [e.features          for e in embeddings],
            metadata_json = [JSON.json(e.metadata) for e in embeddings],
        )
        Arrow.write(cache_file, tbl)
    catch e
        @warn "Failed to save embedding cache to $cache_file: $e"
    end
end

"""
    build_index(games::Vector{GameData}, replay_dir::String="") -> Vector{ReplayEmbedding}

Build embedding index from parsed games, using an Arrow cache to avoid re-embedding
unchanged files. Pass replay_dir to enable caching (leave empty to skip cache).
"""
function build_index(games::Vector{GameData}, replay_dir::String="")::Vector{ReplayEmbedding}
    # Load existing cache when a directory is provided
    cache = isempty(replay_dir) ?
        Dict{String, Tuple{Float64, ReplayEmbedding}}() :
        load_index_cache(replay_dir)

    embeddings    = ReplayEmbedding[]
    mtimes        = Dict{String,Float64}()
    cache_changed = false

    for game in games
        file_mtime = try Float64(mtime(game.path)) catch; 0.0 end
        mtimes[game.path] = file_mtime

        cached = get(cache, game.path, nothing)
        if cached !== nothing && abs(cached[1] - file_mtime) < 1.0
            push!(embeddings, cached[2])
        else
            try
                emb = generate_embedding(game)
                push!(embeddings, emb)
                cache_changed = true
            catch e
                @warn "Failed to generate embedding for $(game.path): $e"
            end
        end
    end

    # Persist cache if anything changed
    if cache_changed && !isempty(replay_dir)
        save_index_cache(replay_dir, embeddings, mtimes)
    end

    return embeddings
end

# --- Internal helpers ---

function _arr_mean_std(arr)::Vector{Float64}
    if arr === nothing
        return [0.0, 0.0]
    end
    vals = [Float64(x) for x in skipmissing(arr)]
    if isempty(vals)
        return [0.0, 0.0]
    end
    m = mean(vals)
    s = length(vals) > 1 ? std(vals) : 0.0
    return [m, s]
end

function _arr_mean(arr)::Float64
    if arr === nothing
        return 0.0
    end
    vals = [Float64(x) for x in skipmissing(arr)]
    return isempty(vals) ? 0.0 : mean(vals)
end

function _joystick_mean_mag(joy::Position)::Float64
    if joy.x === nothing || joy.y === nothing
        return 0.0
    end
    xs = [Float64(x) for x in skipmissing(joy.x)]
    ys = [Float64(y) for y in skipmissing(joy.y)]
    n = min(length(xs), length(ys))
    n == 0 && return 0.0
    return mean(sqrt.(xs[1:n].^2 .+ ys[1:n].^2))
end

function _joystick_std_mag(joy::Position)::Float64
    if joy.x === nothing || joy.y === nothing
        return 0.0
    end
    xs = [Float64(x) for x in skipmissing(joy.x)]
    ys = [Float64(y) for y in skipmissing(joy.y)]
    n = min(length(xs), length(ys))
    n < 2 && return 0.0
    mags = sqrt.(xs[1:n].^2 .+ ys[1:n].^2)
    return std(mags)
end
