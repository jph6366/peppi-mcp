"""
Core statistics implementation - works with real Peppi frame data
"""

"""
    get_frame_value(arr, index) -> value

Safely get a value from an Arrow array at the given index
"""
function get_frame_value(arr, index::Int)
    if arr === nothing || index < 1 || index > length(arr)
        return nothing
    end
    return arr[index]
end
"""
    calculate_stocks_and_damage(frames::Frame, port_idx::Int) -> (stocks_lost, damage_taken, damage_dealt)

Calculate stocks lost and damage using materialized columns to avoid Bus errors.
"""
function calculate_stocks_and_damage(frames::Frame, port_idx::Int)
    # 1. Validation
    if frames === nothing || port_idx < 1 || port_idx > length(frames.ports)
        return (0, 0.0, 0.0)
    end

    port = frames.ports[port_idx]
    if port.leader === nothing || port.leader.post === nothing
        return (0, 0.0, 0.0)
    end

    post = port.leader.post

    # 2. Materialize the columns!
    # This copies the data from the Arrow mmap into Julia's managed RAM.
    # This prevents the "Bus error" because we stop touching the disk/Rust memory.
    stocks_vec = post.stocks !== nothing ? copy(post.stocks) : nothing
    percent_vec = post.percent !== nothing ? copy(post.percent) : nothing

    if stocks_vec === nothing || percent_vec === nothing
        return (0, 0.0, 0.0)
    end

    num_frames = length(stocks_vec)
    if num_frames == 0
        return (0, 0.0, 0.0)
    end

    # 3. Track stocks using standard Julia indexing
    initial_stocks = stocks_vec[1]
    final_stocks = stocks_vec[end]
    stocks_lost = Int(initial_stocks - final_stocks)

    # 4. Calculate damage taken
    damage_taken = 0.0
    prev_percent = Float64(percent_vec[1])

    for i in 2:num_frames
        curr_percent = Float64(percent_vec[i])
        curr_stocks = stocks_vec[i]
        prev_stocks = stocks_vec[i-1]

        # If stocks decreased, the player died:
        # Add the percent they had before dying, then reset.
        if curr_stocks < prev_stocks
            damage_taken += prev_percent
            prev_percent = curr_percent
        # If percent increased, they took a hit
        elseif curr_percent > prev_percent
            damage_taken += (curr_percent - prev_percent)
            prev_percent = curr_percent
        # If percent decreased (healing), just update prev_percent
        elseif curr_percent < prev_percent
            prev_percent = curr_percent
        end
    end

    return (stocks_lost, damage_taken, 0.0)
end

"""
    calculate_damage_dealt(frames::Frame, port_idx::Int) -> Float64

Calculate damage dealt by port_idx to their opponent (requires exactly 2 ports).
"""
function calculate_damage_dealt(frames::Frame, port_idx::Int)::Float64
    if frames === nothing || length(frames.ports) != 2
        return 0.0
    end
    opp_port_idx = 3 - port_idx
    if opp_port_idx < 1 || opp_port_idx > 2
        return 0.0
    end
    (_, opp_damage_taken, _) = calculate_stocks_and_damage(frames, opp_port_idx)
    return opp_damage_taken
end

"""
    count_l_cancels(frames::Frame, port_idx::Int) -> (successes, attempts)

Count L-cancel successes and attempts
"""
function count_l_cancels(frames::Frame, port_idx::Int)
    if frames === nothing || port_idx < 1 || port_idx > length(frames.ports)
        return (0, 0)
    end

    port = frames.ports[port_idx]
    if port.leader === nothing || port.leader.post.l_cancel === nothing
        return (0, 0)
    end

    l_cancel = port.leader.post.l_cancel
    num_frames = length(frames.id)

    successes = 0
    attempts = 0

    for i in 1:num_frames
        lcancel_val = get_frame_value(l_cancel, i)
        if lcancel_val !== nothing && lcancel_val != 0
            attempts += 1
            # L-cancel success is indicated by value 1
            if lcancel_val == 1
                successes += 1
            end
        end
    end

    return (successes, attempts)
end

"""
    detect_wavedashes(frames::Frame, port_idx::Int) -> Int

Detect wavedash count using state transitions
"""
function detect_wavedashes(frames::Frame, port_idx::Int)
    if frames === nothing || port_idx < 1 || port_idx > length(frames.ports)
        return 0
    end

    port = frames.ports[port_idx]
    if port.leader === nothing || port.leader.pre.state === nothing
        return 0
    end

    state = port.leader.pre.state
    num_frames = length(frames.id)

    wavedash_count = 0
    in_jump = false

    for i in 1:num_frames
        curr_state = get_frame_value(state, i)

        if curr_state !== nothing
            # Detect jump start
            if curr_state in (ACTION_JUMP_F, ACTION_JUMP_B)
                in_jump = true
            # Detect landing during jump (potential wavedash)
            elseif in_jump && curr_state == ACTION_LANDING
                wavedash_count += 1
                in_jump = false
            # Reset if grounded without landing
            elseif is_grounded(curr_state)
                in_jump = false
            end
        end
    end

    return wavedash_count
end



const LEDGEDASH_WINDOW = 20  # max frames from cliff exit to landing
"""
    detect_ledgedashes(frames::Frame, port_idx::Int) -> Int

Count ledgedashes: cliff-hang state followed by a landing within LEDGEDASH_WINDOW frames.
"""
function detect_ledgedashes(frames::Frame, port_idx::Int)::Int
    if frames === nothing || port_idx < 1 || port_idx > length(frames.ports)
        return 0
    end

    port = frames.ports[port_idx]
    if port.leader === nothing || port.leader.pre.state === nothing
        return 0
    end

    state = port.leader.pre.state
    num_frames = length(frames.id)

    ledgedash_count = 0
    cliff_frame = -1

    for i in 1:num_frames
        curr_state = get_frame_value(state, i)
        curr_state === nothing && continue
        s = Int(curr_state)

        if is_cliff_hang(s)
            cliff_frame = i
        elseif cliff_frame >= 0
            if (i - cliff_frame) <= LEDGEDASH_WINDOW
                if s == ACTION_LANDING || s == ACTION_LANDING_FALL_SPECIAL
                    ledgedash_count += 1
                    cliff_frame = -1
                end
            else
                # Window expired without landing — not a ledgedash
                cliff_frame = -1
            end
        end
    end

    return ledgedash_count
end

"""
    detect_dash_dances(frames::Frame, port_idx::Int) -> Int

Count dash dances: consecutive frames in Dash state where the facing direction reverses.
"""
function detect_dash_dances(frames::Frame, port_idx::Int)::Int
    if frames === nothing || port_idx < 1 || port_idx > length(frames.ports)
        return 0
    end

    port = frames.ports[port_idx]
    if port.leader === nothing || port.leader.pre.state === nothing ||
       port.leader.pre.direction === nothing
        return 0
    end

    state     = port.leader.pre.state
    direction = port.leader.pre.direction
    num_frames = length(frames.id)

    dash_dance_count = 0

    for i in 2:num_frames
        curr_s   = get_frame_value(state, i)
        prev_s   = get_frame_value(state, i - 1)
        curr_dir = get_frame_value(direction, i)
        prev_dir = get_frame_value(direction, i - 1)

        if curr_s !== nothing && prev_s !== nothing &&
           Int(curr_s) == ACTION_DASH && Int(prev_s) == ACTION_DASH &&
           curr_dir !== nothing && prev_dir !== nothing && curr_dir != prev_dir
            dash_dance_count += 1
        end
    end

    return dash_dance_count
end

"""
    detect_punishes(frames::Frame, port_idx::Int) -> PunishStats

Detect punish sequences: windows where the opponent is in continuous hitstun.
Tracks damage dealt during each window, conversions (stock taken), and zero-to-deaths.
Only meaningful for 1v1 (exactly 2 ports in frames).
"""
function detect_punishes(frames::Frame, port_idx::Int)::PunishStats
    if frames === nothing || port_idx < 1 || port_idx > length(frames.ports) ||
       length(frames.ports) != 2
        return PunishStats(0, 0.0, 0.0, 0)
    end

    opp_port_idx = 3 - port_idx
    opp_leader = frames.ports[opp_port_idx].leader
    if opp_leader === nothing || opp_leader.pre.state === nothing ||
       opp_leader.post.percent === nothing || opp_leader.post.stocks === nothing
        return PunishStats(0, 0.0, 0.0, 0)
    end

    opp_state   = opp_leader.pre.state
    opp_percent = opp_leader.post.percent
    opp_stocks  = opp_leader.post.stocks
    num_frames  = length(frames.id)

    punish_count   = 0
    total_damage   = 0.0
    conversions    = 0
    zero_to_deaths = 0

    in_punish         = false
    punish_start_pct  = 0.0
    punish_start_stks = 4
    punish_peak_pct   = 0.0

    for i in 1:num_frames
        state = get_frame_value(opp_state, i)
        pct   = get_frame_value(opp_percent, i)
        stks  = get_frame_value(opp_stocks, i)
        state === nothing && continue

        hitstun  = is_hitstun(Int(state))
        pct_f    = pct  !== nothing ? Float64(pct)  : 0.0
        stks_i   = stks !== nothing ? Int(stks)     : 4

        stock_lost = in_punish && stks_i < punish_start_stks

        if !in_punish && hitstun
            # Begin punish window
            in_punish         = true
            punish_start_pct  = pct_f
            punish_start_stks = stks_i
            punish_peak_pct   = pct_f
        elseif in_punish
            # Track highest percent reached (not on stock-reset frames)
            if !stock_lost && pct_f > punish_peak_pct
                punish_peak_pct = pct_f
            end

            if stock_lost || !hitstun
                # Finalize punish window
                damage = max(0.0, punish_peak_pct - punish_start_pct)
                if damage > 0.0 || stock_lost
                    punish_count += 1
                    total_damage += damage
                    if stock_lost
                        conversions += 1
                        if punish_start_pct < 10.0
                            zero_to_deaths += 1
                        end
                    end
                end
                in_punish = false
            end
        end
    end

    avg_damage = punish_count > 0 ? total_damage / punish_count : 0.0
    conv_rate  = punish_count > 0 ? Float64(conversions) / punish_count : 0.0
    return PunishStats(punish_count, avg_damage, conv_rate, zero_to_deaths)
end

"""
    analyze_neutral(frames::Frame, port_idx::Int) -> (opening_rate, neutral_win_rate)

Compute neutral game statistics for a 1v1 game.
- opening_rate: openings created per 60 seconds of neutral play
- neutral_win_rate: fraction of total openings created by this player
"""
function analyze_neutral(frames::Frame, port_idx::Int)::Tuple{Float64, Float64}
    if frames === nothing || port_idx < 1 || port_idx > length(frames.ports) ||
       length(frames.ports) != 2
        return (0.0, 0.0)
    end

    opp_port_idx = 3 - port_idx
    my_leader  = frames.ports[port_idx].leader
    opp_leader = frames.ports[opp_port_idx].leader
    if my_leader === nothing || opp_leader === nothing ||
       my_leader.pre.state === nothing || opp_leader.pre.state === nothing
        return (0.0, 0.0)
    end

    my_state  = my_leader.pre.state
    opp_state = opp_leader.pre.state
    num_frames = length(frames.id)

    neutral_frames    = 0
    player_openings   = 0  # player opened the opponent
    opponent_openings = 0  # opponent opened the player

    for i in 1:(num_frames - 1)
        my_s  = get_frame_value(my_state, i)
        opp_s = get_frame_value(opp_state, i)
        (my_s === nothing || opp_s === nothing) && continue

        my_hitstun  = is_hitstun(Int(my_s))
        opp_hitstun = is_hitstun(Int(opp_s))

        # Neutral: neither player in hitstun
        if !my_hitstun && !opp_hitstun
            neutral_frames += 1

            # Check if the next frame an opening occurs
            next_opp = get_frame_value(opp_state, i + 1)
            next_my  = get_frame_value(my_state,  i + 1)
            if next_opp !== nothing && is_hitstun(Int(next_opp))
                player_openings += 1
            end
            if next_my !== nothing && is_hitstun(Int(next_my))
                opponent_openings += 1
            end
        end
    end

    # Opening rate per 60 seconds (3600 frames) of neutral
    opening_rate = neutral_frames > 0 ?
        player_openings / neutral_frames * 3600.0 : 0.0

    total_openings = player_openings + opponent_openings
    neutral_win_rate = total_openings > 0 ?
        Float64(player_openings) / total_openings : 0.0

    return (opening_rate, neutral_win_rate)
end

"""
    calculate_game_stats(game::GameData, player_port::Union{Int,Nothing}) -> Dict{String,Any}

Calculate statistics for a single game
"""
function calculate_game_stats(game::GameData, player_port::Union{Int,Nothing})::Dict{String,Any}
    # Find player port if not specified
    if player_port === nothing && length(game.metadata.players) > 0
        player_port = game.metadata.players[1]["port"] + 1  # Convert to 1-indexed
    end

    if player_port === nothing || game.frames === nothing
        return Dict{String,Any}(
            "error" => "Could not determine player port or no frame data available"
        )
    end

    # Calculate stocks and damage taken
    (stocks_lost, damage_taken, _) = calculate_stocks_and_damage(game.frames, player_port)

    # Calculate damage dealt (opponent's damage taken)
    damage_dealt = calculate_damage_dealt(game.frames, player_port)

    # Calculate L-cancels
    (l_cancel_successes, l_cancel_attempts) = count_l_cancels(game.frames, player_port)
    l_cancel_rate = l_cancel_attempts > 0 ? l_cancel_successes / l_cancel_attempts : 0.0

    # Detect wavedashes
    wavedash_count = detect_wavedashes(game.frames, player_port)

    # Detect ledgedashes
    ledgedash_count = detect_ledgedashes(game.frames, player_port)

    # Detect dash dances
    dash_dance_count = detect_dash_dances(game.frames, player_port)

    # Detect punishes
    punish_stats = detect_punishes(game.frames, player_port)

    # Neutral game analysis
    (opening_rate, neutral_win_rate) = analyze_neutral(game.frames, player_port)

    # Determine outcome
    won = game.metadata.winner !== nothing && game.metadata.winner == (player_port - 1)

    return Dict{String,Any}(
        "path"                => basename(game.path),
        "stage"               => game.metadata.stage,
        "character"           => length(game.metadata.players) >= player_port ?
                                 game.metadata.players[player_port]["character"] : "Unknown",
        "duration_frames"     => game.metadata.duration_frames,
        "won"                 => won,
        "stocks_lost"         => stocks_lost,
        "damage_taken"        => round(damage_taken, digits=1),
        "damage_dealt"        => round(damage_dealt, digits=1),
        "l_cancel_successes"  => l_cancel_successes,
        "l_cancel_attempts"   => l_cancel_attempts,
        "l_cancel_rate"       => round(l_cancel_rate * 100, digits=1),
        "wavedash_count"      => wavedash_count,
        "ledgedash_count"     => ledgedash_count,
        "dash_dance_count"    => dash_dance_count,
        "punish_count"        => punish_stats.punish_count,
        "avg_punish_damage"   => round(punish_stats.avg_punish_damage, digits=1),
        "conversion_rate"     => round(punish_stats.conversion_rate * 100, digits=1),
        "zero_to_death_count" => punish_stats.zero_to_death_count,
        "opening_rate"        => round(opening_rate, digits=2),
        "neutral_win_rate"    => round(neutral_win_rate * 100, digits=1),
        "start_time"          => game.metadata.start_time
    )
end
