"""
Search module - implements search_replays tool
Semantic search over replay embeddings with structured filters
"""

using LinearAlgebra

"""
Query structure for parsed natural language query
"""
struct SearchQuery
    text::String
    character::Union{String,Nothing}
    stage::Union{String,Nothing}
    outcome::Union{String,Nothing}
    keywords::Vector{String}
end

"""
Search result structure
"""
struct SearchResult
    path::String
    score::Float64
    metadata::Dict{String,Any}
end

"""
    search_replays(params::Dict{String,Any}) -> Dict{String,Any}

Main entry point for search_replays tool.
Semantic search with optional structured filters.
"""
function search_replays(params::Dict{String,Any})::Dict{String,Any}
    dir = get(params, "dir", "")
    query_text = get(params, "query", "")
    top_k = get(params, "top_k", 10)
    filters = get(params, "filters", Dict{String,Any}())

    # Scan directory for replays
    replay_files = scan_directory(dir)

    if isempty(replay_files)
        return Dict{String,Any}(
            "error" => "No .slp files found in directory: $dir",
            "results" => []
        )
    end

    # Parse query
    query = parse_search_query(query_text, filters)

    # Parse and embed replays
    games = GameData[]
    for path in replay_files
        game = parse_replay(path)
        if game !== nothing
            # Apply hard filters
            if matches_filters(game, query)
                push!(games, game)
            end
        end
    end

    if isempty(games)
        return Dict{String,Any}(
            "error" => "No replays matched the specified filters",
            "results" => [],
            "scanned" => length(replay_files),
            "matched" => 0
        )
    end

    # Build embedding index (with Arrow cache keyed by replay dir)
    embeddings = build_index(games, dir)

    # Generate query embedding
    query_embedding = generate_query_embedding(query, embeddings)

    # Rank by similarity
    results = rank_replays(embeddings, query_embedding, top_k)

    return Dict{String,Any}(
        "success" => true,
        "query" => query_text,
        "scanned" => length(replay_files),
        "matched" => length(games),
        "top_k" => top_k,
        "results" => serialize_results(results)
    )
end

"""
    parse_search_query(text::String, filters::Dict{String,Any}) -> SearchQuery

Parse natural language query and extract structured information
"""
function parse_search_query(text::String, filters::Dict{String,Any})::SearchQuery
    # Extract keywords from text
    keywords = extract_keywords(text)

    # Get structured filters
    character = get(filters, "character", nothing)
    stage = get(filters, "stage", nothing)
    outcome = get(filters, "outcome", nothing)

    # Try to extract character/stage/outcome from query text if not in filters
    if character === nothing
        character = extract_character_from_text(text)
    end
    if stage === nothing
        stage = extract_stage_from_text(text)
    end
    if outcome === nothing
        outcome = extract_outcome_from_text(text)
    end

    return SearchQuery(text, character, stage, outcome, keywords)
end

"""
    extract_keywords(text::String) -> Vector{String}

Extract relevant keywords from query text
"""
function extract_keywords(text::String)::Vector{String}
    # Simple keyword extraction (split on whitespace, lowercase)
    words = split(lowercase(text))

    # Filter out common stop words
    stop_words = Set(["a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
                      "of", "with", "by", "from", "as", "is", "was", "were", "been", "be",
                      "i", "my", "me", "where", "when", "that", "this"])

    keywords = [String(w) for w in words if !(w in stop_words) && length(w) > 2]

    return keywords
end

"""
    extract_character_from_text(text::String) -> Union{String,Nothing}

Try to identify character name in query text
"""
function extract_character_from_text(text::String)::Union{String,Nothing}
    text_lower = lowercase(text)

    for char_name in values(CHARACTER_NAMES)
        if occursin(lowercase(char_name), text_lower)
            return char_name
        end
    end

    # Check for common abbreviations
    abbreviations = Dict(
        "fox" => "Fox", "falco" => "Falco", "marth" => "Marth",
        "puff" => "Jigglypuff", "peach" => "Peach", "falcon" => "Captain Falcon",
        "sheik" => "Sheik", "ic" => "Popo", "icies" => "Popo"
    )

    for (abbrev, full_name) in abbreviations
        if occursin(abbrev, text_lower)
            return full_name
        end
    end

    return nothing
end

"""
    extract_stage_from_text(text::String) -> Union{String,Nothing}

Try to identify stage name in query text
"""
function extract_stage_from_text(text::String)::Union{String,Nothing}
    text_lower = lowercase(text)

    for (stage_name, _) in STAGES
        if occursin(lowercase(stage_name), text_lower)
            return stage_name
        end
    end

    # Check for common abbreviations
    abbreviations = Dict(
        "fod" => "Fountain of Dreams",
        "stadium" => "Pokémon Stadium",
        "ps" => "Pokémon Stadium",
        "yoshis" => "Yoshi's Story",
        "dreamland" => "Dream Land",
        "battlefield" => "Battlefield",
        "bf" => "Battlefield",
        "fd" => "Final Destination"
    )

    for (abbrev, full_name) in abbreviations
        if occursin(abbrev, text_lower)
            return full_name
        end
    end

    return nothing
end

"""
    extract_outcome_from_text(text::String) -> Union{String,Nothing}

Try to identify desired outcome (win/loss) from query text
"""
function extract_outcome_from_text(text::String)::Union{String,Nothing}
    text_lower = lowercase(text)

    win_keywords = ["won", "win", "victory", "beat"]
    loss_keywords = ["lost", "loss", "defeat", "beaten"]

    has_win = any(kw -> occursin(kw, text_lower), win_keywords)
    has_loss = any(kw -> occursin(kw, text_lower), loss_keywords)

    if has_win && !has_loss
        return "win"
    elseif has_loss && !has_win
        return "loss"
    else
        return nothing  # ambiguous or not specified
    end
end

"""
    matches_filters(game::GameData, query::SearchQuery) -> Bool

Check if game matches hard filters from query
"""
function matches_filters(game::GameData, query::SearchQuery)::Bool
    # Filter by character — check if any player uses this character
    if query.character !== nothing
        has_char = any(
            p -> occursin(lowercase(query.character), lowercase(get(p, "character", ""))),
            game.metadata.players
        )
        if !has_char
            return false
        end
    end

    # Filter by stage
    if query.stage !== nothing
        if !occursin(lowercase(query.stage), lowercase(game.metadata.stage))
            return false
        end
    end

    # Filter by outcome from port 1 player's perspective
    if query.outcome !== nothing && game.metadata.winner !== nothing && !isempty(game.metadata.players)
        p1_port = get(game.metadata.players[1], "port", nothing)
        if p1_port !== nothing
            p1_won = game.metadata.winner == p1_port
            if query.outcome == "win" && !p1_won
                return false
            elseif query.outcome == "loss" && p1_won
                return false
            end
        end
    end

    return true
end

"""
    generate_query_embedding(query::SearchQuery, embeddings::Vector{ReplayEmbedding}) -> Vector{Float64}

Build a keyword-weighted feature vector in the same space as replay embeddings.

Layout mirrors extract_metadata_features + aggregate_frame_features:
  Dims 1–NUM_CHARS        : P1 character one-hot
  Dims NUM_CHARS+1–2*NUM_CHARS : P2 character one-hot
  Next length(STAGES) dims: stage one-hot
  Next dim               : outcome  (win=1.0, loss=0.0, unknown=0.0)
  Next dim               : duration hint from keywords
  Remaining dims         : frame features (left at zero for queries)
"""
function generate_query_embedding(query::SearchQuery, embeddings::Vector{ReplayEmbedding})::Vector{Float64}
    if isempty(embeddings)
        return Float64[]
    end

    dim = length(embeddings[1].features)
    q   = zeros(Float64, dim)

    num_stages = length(STAGES)

    # --- Character (set both P1 and P2 slots so either port matches) ---
    if query.character !== nothing
        char_id = nothing
        for (id, name) in CHARACTER_NAMES
            if name == query.character
                char_id = id
                break
            end
        end
        if char_id !== nothing && 0 <= char_id < NUM_CHARS
            q[char_id + 1]             = 0.7   # P1 slot
            q[NUM_CHARS + char_id + 1] = 0.7   # P2 slot
        end
    end

    # --- Stage ---
    stage_offset = 2 * NUM_CHARS
    if query.stage !== nothing
        stage_idx = get(STAGES, query.stage, -1)
        if 0 <= stage_idx < num_stages
            q[stage_offset + stage_idx + 1] = 1.0
        end
    end

    # --- Outcome ---
    outcome_dim  = stage_offset + num_stages + 1   # 59
    duration_dim = outcome_dim + 1                  # 60
    if outcome_dim <= dim
        if query.outcome == "win"
            q[outcome_dim] = 1.0
        elseif query.outcome == "loss"
            q[outcome_dim] = 0.0   # stays 0; replays with outcome=0 will score higher
        end
    end

    # --- Duration hint from keywords ---
    duration_hints = Dict(
        "quick"   => 0.2, "short"   => 0.2, "fast"   => 0.2,
        "long"    => 1.2, "timeout" => 2.0,
        "close"   => 0.9, "last"    => 0.8, "stock"  => 0.8,
    )
    if duration_dim <= dim
        for kw in query.keywords
            if haskey(duration_hints, kw)
                q[duration_dim] = max(q[duration_dim], duration_hints[kw])
            end
        end
    end

    return normalize_vector(q)
end

"""
    rank_replays(embeddings::Vector{ReplayEmbedding}, query_emb::Vector{Float64}, top_k::Int) -> Vector{SearchResult}

Rank replays by similarity to query embedding
Uses brute-force cosine similarity for v1
"""
function rank_replays(embeddings::Vector{ReplayEmbedding}, query_emb::Vector{Float64}, top_k::Int)::Vector{SearchResult}
    results = SearchResult[]

    # Calculate similarity scores
    for emb in embeddings
        # Cosine similarity
        score = if !isempty(query_emb) && length(query_emb) == length(emb.features)
            cosine_similarity(query_emb, emb.features)
        else
            # Fallback: assign random score for stub
            rand()
        end

        push!(results, SearchResult(emb.path, score, emb.metadata))
    end

    # Sort by score descending
    sort!(results, by = r -> r.score, rev = true)

    # Return top_k
    return results[1:min(top_k, length(results))]
end

"""
    serialize_results(results::Vector{SearchResult}) -> Vector{Dict{String,Any}}

Convert search results to JSON-serializable format
"""
function serialize_results(results::Vector{SearchResult})::Vector{Dict{String,Any}}
    return [
        Dict{String,Any}(
            "path" => r.path,
            "score" => r.score,
            "metadata" => r.metadata
        )
        for r in results
    ]
end
