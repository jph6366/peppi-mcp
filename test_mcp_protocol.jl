#!/usr/bin/env julia

"""
Simple test of MCP protocol handling
Sends sample JSON-RPC requests to test response format
"""

push!(LOAD_PATH, joinpath(pwd(), "src"))
using PeppiMCP
using JSON

function test_initialize()
    request = Dict{String,Any}(
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => Dict{String,Any}()
    )

    response = PeppiMCP.handle_request(request)
    println("✓ Initialize response: ", JSON.write(response))

    @assert response["jsonrpc"] == "2.0"
    @assert response["id"] == 1
    @assert haskey(response["result"], "serverInfo")
    @assert response["result"]["serverInfo"]["name"] == "peppi-mcp"
end

function test_tools_list()
    request = Dict{String,Any}(
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/list",
        "params" => Dict{String,Any}()
    )

    response = PeppiMCP.handle_request(request)
    println("✓ Tools/list response: ", JSON.write(response))

    @assert response["jsonrpc"] == "2.0"
    @assert response["id"] == 2
    @assert haskey(response["result"], "tools")
    @assert length(response["result"]["tools"]) == 2
    @assert response["result"]["tools"][1]["name"] == "generate_stats"
    @assert response["result"]["tools"][2]["name"] == "search_replays"
end

function test_tool_call_generate_stats()
    request = Dict{String,Any}(
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => Dict{String,Any}(
            "name" => "generate_stats",
            "arguments" => Dict{String,Any}(
                "dir" => "/tmp/test_replays"
            )
        )
    )

    response = PeppiMCP.handle_request(request)
    response_str = JSON.write(response)
    preview = length(response_str) > 200 ? response_str[1:200] * "..." : response_str
    println("✓ Generate_stats call response (stub): ", preview)

    @assert response["jsonrpc"] == "2.0"
    @assert response["id"] == 3
    @assert haskey(response["result"], "content")
    @assert response["result"]["content"][1]["type"] == "text"
end

function test_tool_call_search_replays()
    request = Dict{String,Any}(
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => Dict{String,Any}(
            "name" => "search_replays",
            "arguments" => Dict{String,Any}(
                "dir" => "/tmp/test_replays",
                "query" => "close games",
                "top_k" => 5
            )
        )
    )

    response = PeppiMCP.handle_request(request)
    response_str = JSON.write(response)
    preview = length(response_str) > 200 ? response_str[1:200] * "..." : response_str
    println("✓ Search_replays call response (stub): ", preview)

    @assert response["jsonrpc"] == "2.0"
    @assert response["id"] == 4
    @assert haskey(response["result"], "content")
end

function test_unknown_method()
    request = Dict{String,Any}(
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "unknown_method",
        "params" => Dict{String,Any}()
    )

    response = PeppiMCP.handle_request(request)
    println("✓ Unknown method error response: ", JSON.write(response))

    @assert response["jsonrpc"] == "2.0"
    @assert response["id"] == 5
    @assert haskey(response, "error")
    @assert response["error"]["code"] == -32601
end

println("Running MCP Protocol Tests...")
println()

test_initialize()
test_tools_list()
test_tool_call_generate_stats()
test_tool_call_search_replays()
test_unknown_method()

println()
println("All protocol tests passed! ✓")
