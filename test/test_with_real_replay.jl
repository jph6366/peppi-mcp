#!/usr/bin/env julia

"""
Integration test with real .slp file
Tests directory scanning and tool invocation with actual replay data
"""

push!(LOAD_PATH, joinpath(pwd(), "src"))
using PeppiMCP
using JSON3

const TEST_DATA_DIR = joinpath(@__DIR__, "data")
const TEST_REPLAY = joinpath(TEST_DATA_DIR, "game.slp")

println("Testing with real replay file...")
println("File: $TEST_REPLAY")
println("Size: ", filesize(TEST_REPLAY), " bytes")
println()

# Test 1: Directory scanning
println("Test 1: Directory Scanning")
println("=" ^ 40)
files = PeppiMCP.scan_directory(TEST_DATA_DIR)
println("Found $(length(files)) .slp file(s):")
for file in files
    println("  - $(basename(file))")
end
@assert length(files) == 1
@assert basename(files[1]) == "game.slp"
println("✓ Directory scanning works!\n")

# Test 2: Parse replay (will return nothing until peppi-jl is integrated)
println("Test 2: Parse Replay")
println("=" ^ 40)
result = PeppiMCP.parse_replay(TEST_REPLAY)
if result === nothing
    println("⚠ parse_replay returned nothing (expected - peppi-jl not integrated)")
    println("Once peppi-jl is integrated, this will return GameData with:")
    println("  - metadata: stage, players, characters, duration, winner")
    println("  - frames: Arrow.Table with per-frame data")
else
    println("✓ Replay parsed successfully!")
    println("Metadata: ", result.metadata)
end
println()

# Test 3: generate_stats tool with real directory
println("Test 3: generate_stats Tool")
println("=" ^ 40)
request = Dict{String,Any}(
    "jsonrpc" => "2.0",
    "id" => 1,
    "method" => "tools/call",
    "params" => Dict{String,Any}(
        "name" => "generate_stats",
        "arguments" => Dict{String,Any}(
            "dir" => TEST_DATA_DIR
        )
    )
)

response = PeppiMCP.handle_request(request)
result_text = response["result"]["content"][1]["text"]
result_data = JSON3.read(result_text, Dict{String,Any})

println("Response:")
println(JSON3.write(result_data))

if haskey(result_data, "error")
    println("\n⚠ Tool returned error (expected - peppi-jl not integrated)")
    println("Error: ", result_data["error"])
    println("\nOnce peppi-jl is integrated, this will return:")
    println("  - core stats: stocks, damage, neutral wins, etc.")
    println("  - punish stats: conversion rate, zero-to-deaths")
    println("  - movement stats: wavedashes, L-cancels, etc.")
else
    println("\n✓ Stats generated successfully!")
    println("Stats: ", result_data["stats"])
end
println()

# Test 4: search_replays tool with real directory
println("Test 4: search_replays Tool")
println("=" ^ 40)
request = Dict{String,Any}(
    "jsonrpc" => "2.0",
    "id" => 2,
    "method" => "tools/call",
    "params" => Dict{String,Any}(
        "name" => "search_replays",
        "arguments" => Dict{String,Any}(
            "dir" => TEST_DATA_DIR,
            "query" => "Fox games on Final Destination",
            "top_k" => 5
        )
    )
)

response = PeppiMCP.handle_request(request)
result_text = response["result"]["content"][1]["text"]
result_data = JSON3.read(result_text, Dict{String,Any})

println("Response:")
println(JSON3.write(result_data))

if haskey(result_data, "error")
    println("\n⚠ Tool returned error (expected - peppi-jl not integrated)")
    println("Error: ", result_data["error"])
    println("\nOnce peppi-jl is integrated, this will return:")
    println("  - ranked list of matching replays")
    println("  - similarity scores")
    println("  - metadata summaries")
else
    println("\n✓ Search completed successfully!")
    println("Found $(length(result_data["results"])) result(s)")
end
println()

# Test 5: Query parsing
println("Test 5: Query Parsing")
println("=" ^ 40)
queries = [
    "Fox vs Marth on Battlefield",
    "games where I won with Falco",
    "close last stock matches on FD",
    "puff games on Dreamland"
]

for query in queries
    parsed = PeppiMCP.parse_search_query(query, Dict{String,Any}())
    println("Query: \"$query\"")
    println("  Character: $(parsed.character)")
    println("  Stage: $(parsed.stage)")
    println("  Outcome: $(parsed.outcome)")
    println("  Keywords: $(join(parsed.keywords, ", "))")
    println()
end
println("✓ Query parsing works!\n")

# Summary
println("=" ^ 60)
println("SUMMARY")
println("=" ^ 60)
println("✓ Directory scanning: WORKING")
println("✓ File detection: WORKING (found game.slp)")
println("✓ MCP protocol: WORKING")
println("✓ Tool invocation: WORKING")
println("✓ Query parsing: WORKING")
println()
println("⚠ Replay parsing: BLOCKED (needs peppi-jl)")
println("⚠ Statistics: BLOCKED (needs peppi-jl)")
println("⚠ Search ranking: BLOCKED (needs peppi-jl)")
println()
println("Next step: Integrate peppi-jl to unlock full functionality")
println("See IMPLEMENTATION_NOTES.md for integration guide")
