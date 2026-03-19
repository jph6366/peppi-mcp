"""
analyze_replays.jl — Explore personal replays in test/replays/

Usage:
    julia --project=. analyze_replays.jl

Outputs:
  1. Player/character discovery (all unique connect codes + characters seen)
  2. Full aggregate statistics (auto-detects your connect code as the majority player)
  3. Per-game breakdown sorted by performance score
  4. Search results: games where you performed best (high damage dealt, high L-cancel rate)
"""

using PeppiMCP

const REPLAY_DIR = joinpath(@__DIR__, "test", "replays")

# ── 1. Parse all replays ──────────────────────────────────────────────────────

println("Scanning $REPLAY_DIR ...")
files = PeppiMCP.scan_directory(REPLAY_DIR)
println("Found $(length(files)) replay files.\n")

games = filter(!isnothing, map(files) do f
    PeppiMCP.parse_replay(f)
end)
println("Successfully parsed $(length(games)) replays.\n")

# ── 2. Discover players ───────────────────────────────────────────────────────

player_freq = Dict{String,Int}()   # connect_code → game count
char_by_code = Dict{String,Dict{String,Int}}()  # code → char → count

for g in games
    for p in g.metadata.players
        code = get(p, "connect_code", nothing)
        char = get(p, "character", "Unknown")
        code === nothing && continue
        player_freq[code]  = get(player_freq, code, 0) + 1
        chars = get!(char_by_code, code, Dict{String,Int}())
        chars[char] = get(chars, char, 0) + 1
    end
end

println("═══════════════════════════════════════════════════════")
println("  PLAYERS FOUND")
println("═══════════════════════════════════════════════════════")
for (code, cnt) in sort(collect(player_freq), by=x->x[2], rev=true)
    chars = char_by_code[code]
    main_char = argmax(chars)
    println("  $code  —  $cnt games  |  main: $main_char")
end
println()

# Auto-detect: most frequent code = likely you
your_code = argmax(player_freq)
println("► Auto-detected your connect code: $your_code\n")

# ── 3. Stage breakdown ────────────────────────────────────────────────────────

stage_freq = Dict{String,Int}()
for g in games
    s = g.metadata.stage
    stage_freq[s] = get(stage_freq, s, 0) + 1
end

println("═══════════════════════════════════════════════════════")
println("  STAGE BREAKDOWN  ($(length(games)) games)")
println("═══════════════════════════════════════════════════════")
for (stage, cnt) in sort(collect(stage_freq), by=x->x[2], rev=true)
    bar = "█" ^ cnt
    println("  $(lpad(stage, 22))  $cnt  $bar")
end
println()

# ── 4. Per-game stats for your port ──────────────────────────────────────────

per_game = Dict{String,Any}[]
for g in games
    raw_port = PeppiMCP.get_player_port(g, your_code)
    player_port = raw_port !== nothing ? raw_port + 1 : nothing
    stats = PeppiMCP.calculate_game_stats(g, player_port)
    haskey(stats, "error") && continue
    push!(per_game, stats)
end

println("Computed per-game stats for $(length(per_game)) games as $your_code.\n")

# ── 5. Aggregate stats ────────────────────────────────────────────────────────

wins   = count(g["won"]  for g in per_game)
losses = count(!g["won"] for g in per_game)
n      = length(per_game)

function avg(key)
    vals = [g[key] for g in per_game if g[key] isa Number]
    isempty(vals) ? 0.0 : sum(vals) / length(vals)
end
function total(key)
    sum(g[key] for g in per_game if g[key] isa Number; init=0)
end

println("═══════════════════════════════════════════════════════")
println("  AGGREGATE STATISTICS  ($your_code, $n games)")
println("═══════════════════════════════════════════════════════")
# Using string interpolation and rounding for formatting
println("  Win/Loss:           ", wins, " W  /  ", losses, " L  (", round(wins/max(n,1)*100, digits=1), "%)")
println("  Avg damage dealt:    ", round(avg("damage_dealt"), digits=1), "  per game")
println("  Avg damage taken:    ", round(avg("damage_taken"), digits=1), "  per game")
println("  Avg stocks lost:     ", round(avg("stocks_lost"), digits=2), " per game")
println("  L-cancel rate:       ", round(avg("l_cancel_rate"), digits=1), "%")
println("  Total wavedashes:    ", total("wavedash_count"), "  (", round(avg("wavedash_count"), digits=1), "/game)")
println("  Total ledgedashes:   ", total("ledgedash_count"), "  (", round(avg("ledgedash_count"), digits=1), "/game)")
println("  Total dash dances:   ", total("dash_dance_count"), "  (", round(avg("dash_dance_count"), digits=1), "/game)")
println("  Total punishes:      ", total("punish_count"), "  (", round(avg("punish_count"), digits=1), "/game)")
println("  Avg punish damage:   ", round(avg("avg_punish_damage"), digits=1))
println("  Avg conversion rate: ", round(avg("conversion_rate"), digits=1), "%")
println("  Zero-to-deaths:      ", total("zero_to_death_count"), " total")
println("  Avg opening rate:    ", round(avg("opening_rate"), digits=2), " / 60s neutral")
println("  Avg neutral win %:   ", round(avg("neutral_win_rate"), digits=1), "%")
println()

# ── 6. Best performances ─────────────────────────────────────────────────────

# Performance score: damage_dealt - damage_taken + 50*(won) + 20*conversion_rate
function perf_score(g)
    g["damage_dealt"] - g["damage_taken"] +
    (g["won"] ? 50.0 : 0.0) +
    20.0 * (g["conversion_rate"] / 100.0) +
    5.0  * g["neutral_win_rate"] / 100.0
end

sorted_games = sort(per_game, by=perf_score, rev=true)

println("═══════════════════════════════════════════════════════")
println("  TOP 10 BEST PERFORMANCES")
println("═══════════════════════════════════════════════════════")
println("  $(lpad("File",36))  W/L  Dealt  Taken  LC%   WD   Pun   Conv%  Score")
println("  " * "─"^95)
for g in sorted_games[1:min(10, end)]
    outcome = g["won"] ? " W " : " L "
    println(
    "  ",
    rpad(g["path"][1:min(36, end)], 36), "  ",
    rpad(outcome, 7), "  ",
    lpad(round(g["damage_dealt"], digits=0), 5), "  ",
    lpad(round(g["damage_taken"], digits=0), 5), "  ",
    lpad(round(g["l_cancel_rate"], digits=1), 4), "  ",
    lpad(g["wavedash_count"], 3), "  ",
    lpad(g["punish_count"], 3), "   ",
    lpad(round(g["conversion_rate"], digits=1), 4), "  ",
    lpad(round(perf_score(g), digits=1), 5)
)
end
println()

println("═══════════════════════════════════════════════════════")
println("  TOP 10 WORST PERFORMANCES")
println("═══════════════════════════════════════════════════════")
println("  $(lpad("File",36))  W/L  Dealt  Taken  LC%   WD   Pun   Conv%  Score")
println("  " * "─"^95)
for g in sorted_games[max(1,end-9):end]
    outcome = g["won"] ? " W " : " L "
    println(
    "  ",
    rpad(g["path"][1:min(36, end)], 36), "  ",
    rpad(outcome, 7), "  ", # outcome width estimated based on 'outcome' string length
    lpad(round(g["damage_dealt"], digits=0), 5), "  ",
    lpad(round(g["damage_taken"], digits=0), 5), "  ",
    lpad(round(g["l_cancel_rate"], digits=1), 4), "  ",
    lpad(g["wavedash_count"], 3), "  ",
    lpad(g["punish_count"], 3), "    ",
    lpad(round(g["conversion_rate"], digits=1), 4), "  ",
    lpad(round(perf_score(g), digits=1), 5)
    )
end
println()

# ── 7. Session-level breakdown (by date) ─────────────────────────────────────

session_stats = Dict{String, NamedTuple}()
for g in per_game
    date = something(g["start_time"], "unknown")[1:min(10,end)]
    ss = get(session_stats, date, (wins=0, losses=0, dealt=0.0, taken=0.0, n=0))
    session_stats[date] = (
        wins   = ss.wins   + (g["won"] ? 1 : 0),
        losses = ss.losses + (g["won"] ? 0 : 1),
        dealt  = ss.dealt  + g["damage_dealt"],
        taken  = ss.taken  + g["damage_taken"],
        n      = ss.n      + 1,
    )
end

println("═══════════════════════════════════════════════════════")
println("  SESSION BREAKDOWN")
println("═══════════════════════════════════════════════════════")
println("  $(lpad("Date",12))  Games  W/L      AvgDealt  AvgTaken  Net")
println("  " * "─"^60)
for (date, ss) in sort(collect(session_stats), by=x->x[1])
    net = (ss.dealt - ss.taken) / max(ss.n, 1)
    println(
    "  ",
    rpad(date, 12), "  ",
    lpad(ss.n, 5), "  ",
    ss.wins, "W/", ss.losses, "L  ",
    lpad(round(ss.dealt / max(ss.n, 1), digits=1), 8), "  ",
    lpad(round(ss.taken / max(ss.n, 1), digits=1), 8), "  ",
    lpad((net >= 0 ? "+" : "") * string(round(net, digits=1)), 6)
)
end
println()

# ── 8. Semantic search ────────────────────────────────────────────────────────

println("═══════════════════════════════════════════════════════")
println("  SEARCH: \"games where I performed best\"")
println("═══════════════════════════════════════════════════════")
search_result = PeppiMCP.search_replays(Dict{String,Any}(
    "dir"   => REPLAY_DIR,
    "query" => "games I won with high damage",
    "top_k" => 10
))
if haskey(search_result, "results")
    for (i, r) in enumerate(search_result["results"])
        println("  ", lpad(i, 2), ". ", basename(r["path"]), "  (score=", round(r["score"], digits=4), ")")
    end
else
    println("  ", get(search_result, "error", "unknown error"))
end
println()

println("═══════════════════════════════════════════════════════")
println("  SEARCH: \"close last stock losses\"")
println("═══════════════════════════════════════════════════════")
search_result2 = PeppiMCP.search_replays(Dict{String,Any}(
    "dir"   => REPLAY_DIR,
    "query" => "close last stock games I lost",
    "top_k" => 10,
    "filters" => Dict{String,Any}("outcome" => "loss")
))
if haskey(search_result2, "results")
    for (i, r) in enumerate(search_result2["results"])
        println("  ", lpad(i, 2), ". ", basename(r["path"]), "  (score=", round(r["score"], digits=4), ")")
    end
else
    println("  ", get(search_result2, "error", "unknown error"))
end
println()

println("Done.")
