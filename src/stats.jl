"""
Statistics generation module - implements generate_stats tool
Calculates competitive Melee statistics from parsed replay data
"""

using Statistics
using DataFrames
using Dates

include("stats_impl.jl")

# Core statistics structure
struct CoreStats
    games_played::Int
    stocks_taken::Int
    stocks_lost::Int
    damage_dealt::Float64
    damage_taken::Float64
    damage_efficiency::Float64
    opening_rate::Float64
    neutral_wins::Float64
    avg_kill_percent::Float64
    avg_death_percent::Float64
    self_destruct_count::Int
end

# Punish statistics
struct PunishStats
    punish_count::Int
    avg_punish_damage::Float64
    conversion_rate::Float64
    zero_to_death_count::Int
end

# Movement/tech statistics
struct MovementStats
    dash_dance_count::Int
    wavedash_count::Int
    l_cancel_success_rate::Float64
    l_cancel_attempts::Int
    ledgedash_count::Int
    shield_pressure_received::Float64
end

# Aggregated statistics output
struct GameStats
    core::CoreStats
    punish::PunishStats
    movement::MovementStats
    per_game_stats::Vector{Dict{String,Any}}
end

"""
    generate_stats(params::Dict{String,Any}) -> Dict{String,Any}

Main entry point for generate_stats tool.
Scans directory, filters replays, computes statistics.
"""
function generate_stats(params::Dict{String,Any})::Dict{String,Any}
    dir = get(params, "dir", "")
    player_code = get(params, "player_code", nothing)
    opponent_code = get(params, "opponent_code", nothing)
    stage = get(params, "stage", nothing)
    character = get(params, "character", nothing)
    date_from = get(params, "date_from", nothing)
    date_to = get(params, "date_to", nothing)

    # Scan for replays
    replay_files = scan_directory(dir)

    if isempty(replay_files)
        return Dict{String,Any}(
            "error" => "No .slp files found in directory: $dir",
            "stats" => nothing
        )
    end

    # Parse and filter replays
    games = GameData[]
    for path in replay_files
        game = parse_replay(path)
        if game !== nothing
            if passes_filters(game, player_code, opponent_code, stage, character, date_from, date_to)
                push!(games, game)
            end
        end
    end

    if isempty(games)
        return Dict{String,Any}(
            "error" => "No replays matched the specified filters",
            "stats" => nothing,
            "scanned" => length(replay_files),
            "matched" => 0
        )
    end

    # Find player port from player_code if specified (convert to 1-indexed for frame access)
    player_port = nothing
    if player_code !== nothing && !isempty(games)
        raw_port = get_player_port(games[1], player_code)
        player_port = raw_port !== nothing ? raw_port + 1 : nothing
    end

    # Calculate per-game statistics
    per_game_stats = []
    for game in games
        game_stats = calculate_game_stats(game, player_port)
        if !haskey(game_stats, "error")
            push!(per_game_stats, game_stats)
        end
    end

    # Calculate aggregate statistics
    if isempty(per_game_stats)
        return Dict{String,Any}(
            "error" => "Could not calculate stats for any games",
            "scanned" => length(replay_files),
            "matched" => length(games)
        )
    end

    n = length(per_game_stats)
    aggregate_stats = Dict{String,Any}(
        "games_played"          => n,
        "wins"                  => count(g["won"] for g in per_game_stats),
        "losses"                => count(!g["won"] for g in per_game_stats),
        "total_stocks_lost"     => sum(g["stocks_lost"] for g in per_game_stats),
        "total_damage_taken"    => round(sum(g["damage_taken"] for g in per_game_stats), digits=1),
        "avg_damage_taken"      => round(mean(g["damage_taken"] for g in per_game_stats), digits=1),
        "total_damage_dealt"    => round(sum(g["damage_dealt"] for g in per_game_stats), digits=1),
        "avg_damage_dealt"      => round(mean(g["damage_dealt"] for g in per_game_stats), digits=1),
        "l_cancel_rate"         => round(mean(g["l_cancel_rate"] for g in per_game_stats), digits=1),
        "total_wavedashes"        => sum(g["wavedash_count"] for g in per_game_stats),
        "avg_wavedashes_per_game" => round(mean(g["wavedash_count"] for g in per_game_stats), digits=1),
        "total_ledgedashes"       => sum(g["ledgedash_count"] for g in per_game_stats),
        "avg_ledgedashes_per_game" => round(mean(g["ledgedash_count"] for g in per_game_stats), digits=1),
        "total_dash_dances"       => sum(g["dash_dance_count"] for g in per_game_stats),
        "avg_dash_dances_per_game" => round(mean(g["dash_dance_count"] for g in per_game_stats), digits=1),
        "total_punishes"        => sum(g["punish_count"] for g in per_game_stats),
        "avg_punish_damage"     => round(mean(g["avg_punish_damage"] for g in per_game_stats), digits=1),
        "avg_conversion_rate"   => round(mean(g["conversion_rate"] for g in per_game_stats), digits=1),
        "total_zero_to_deaths"  => sum(g["zero_to_death_count"] for g in per_game_stats),
        "avg_opening_rate"      => round(mean(g["opening_rate"] for g in per_game_stats), digits=2),
        "avg_neutral_win_rate"  => round(mean(g["neutral_win_rate"] for g in per_game_stats), digits=1),
    )

    return Dict{String,Any}(
        "success" => true,
        "scanned" => length(replay_files),
        "matched" => length(games),
        "aggregate" => aggregate_stats,
        "per_game" => per_game_stats
    )
end

"""
    passes_filters(game::GameData, ...) -> Bool

Check if game matches filter criteria
"""
function passes_filters(game::GameData, player_code, opponent_code, stage, character, date_from, date_to)::Bool
    # Filter by player code
    if player_code !== nothing
        has_player = any(p -> haskey(p, "connect_code") && p["connect_code"] == player_code,
                         game.metadata.players)
        if !has_player
            return false
        end
    end

    # Filter by opponent code
    if opponent_code !== nothing
        has_opponent = any(p -> haskey(p, "connect_code") && p["connect_code"] == opponent_code,
                           game.metadata.players)
        if !has_opponent
            return false
        end
    end

    # Filter by stage
    if stage !== nothing && !occursin(lowercase(stage), lowercase(game.metadata.stage))
        return false
    end

    # Filter by character
    if character !== nothing
        has_character = any(p -> occursin(lowercase(character), lowercase(p["character"])),
                            game.metadata.players)
        if !has_character
            return false
        end
    end

    # Filter by date (startAt is "YYYY-MM-DDTHH:MM:SSZ" or similar ISO 8601)
    if (date_from !== nothing || date_to !== nothing) && game.metadata.start_time !== nothing
        game_date = try
            Date(game.metadata.start_time[1:10])
        catch
            nothing
        end
        if game_date !== nothing
            if date_from !== nothing
                filter_from = try Date(date_from) catch; nothing end
                if filter_from !== nothing && game_date < filter_from
                    return false
                end
            end
            if date_to !== nothing
                filter_to = try Date(date_to) catch; nothing end
                if filter_to !== nothing && game_date > filter_to
                    return false
                end
            end
        end
    end

    return true
end

"""
    calculate_stats(games::Vector{GameData}, player_code) -> GameStats

Calculate aggregated statistics across all games
"""
function calculate_stats(games::Vector{GameData}, player_code)::GameStats
    # TODO: Implement actual statistics calculation from frame data

    # Stub implementation
    core = CoreStats(
        length(games),  # games_played
        0, 0,          # stocks taken/lost
        0.0, 0.0,      # damage dealt/taken
        0.0,           # damage_efficiency
        0.0,           # opening_rate
        0.0,           # neutral_wins
        0.0, 0.0,      # avg kill/death percent
        0              # self_destructs
    )

    punish = PunishStats(0, 0.0, 0.0, 0)
    movement = MovementStats(0, 0, 0.0, 0, 0, 0.0)

    return GameStats(core, punish, movement, Dict{String,Any}[])
end

"""
    serialize_stats(stats::GameStats) -> Dict{String,Any}

Convert stats structures to JSON-serializable dictionary
"""
function serialize_stats(stats::GameStats)::Dict{String,Any}
    return Dict{String,Any}(
        "core" => Dict{String,Any}(
            "games_played" => stats.core.games_played,
            "stocks_taken" => stats.core.stocks_taken,
            "stocks_lost" => stats.core.stocks_lost,
            "damage_dealt" => stats.core.damage_dealt,
            "damage_taken" => stats.core.damage_taken,
            "damage_efficiency" => stats.core.damage_efficiency,
            "opening_rate" => stats.core.opening_rate,
            "neutral_wins" => stats.core.neutral_wins,
            "avg_kill_percent" => stats.core.avg_kill_percent,
            "avg_death_percent" => stats.core.avg_death_percent,
            "self_destruct_count" => stats.core.self_destruct_count
        ),
        "punish" => Dict{String,Any}(
            "punish_count" => stats.punish.punish_count,
            "avg_punish_damage" => stats.punish.avg_punish_damage,
            "conversion_rate" => stats.punish.conversion_rate,
            "zero_to_death_count" => stats.punish.zero_to_death_count
        ),
        "movement" => Dict{String,Any}(
            "dash_dance_count" => stats.movement.dash_dance_count,
            "wavedash_count" => stats.movement.wavedash_count,
            "l_cancel_success_rate" => stats.movement.l_cancel_success_rate,
            "l_cancel_attempts" => stats.movement.l_cancel_attempts,
            "ledgedash_count" => stats.movement.ledgedash_count,
            "shield_pressure_received" => stats.movement.shield_pressure_received
        ),
        "per_game" => stats.per_game_stats
    )
end

# Action state constants (from ssbm-data)
# TODO: Import complete action state enum when integrating peppi-jl
const ACTION_STATE_WAIT = 14
const ACTION_STATE_DASH = 20
const ACTION_STATE_RUN = 22
const ACTION_STATE_JUMP_F = 24
const ACTION_STATE_JUMP_B = 25
const ACTION_STATE_LANDING = 43
const ACTION_STATE_LANDING_FALL_SPECIAL = 44
const ACTION_STATE_DAMAGE_START = 75
const ACTION_STATE_CLIFF_CATCH = 252
