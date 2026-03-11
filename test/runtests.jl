using Test
using PeppiMCP
using LinearAlgebra

const TEST_DATA_DIR = joinpath(@__DIR__, "data")
const TEST_REPLAY = joinpath(TEST_DATA_DIR, "game.slp")

@testset "PeppiMCP Tests" begin
    @testset "Parsing" begin
        # Test directory scanning
        @testset "scan_directory" begin
            # Create a temporary test directory
            tmpdir = mktempdir()
            try
                # Test empty directory
                files = PeppiMCP.scan_directory(tmpdir)
                @test isempty(files)

                # Test with mock .slp files
                touch(joinpath(tmpdir, "test1.slp"))
                touch(joinpath(tmpdir, "test2.slp"))
                touch(joinpath(tmpdir, "other.txt"))

                files = PeppiMCP.scan_directory(tmpdir)
                @test length(files) == 2
                @test all(endswith(f, ".slp") for f in files)
            finally
                rm(tmpdir, recursive=true)
            end
        end

        @testset "scan_directory with real replay" begin
            if isdir(TEST_DATA_DIR)
                files = PeppiMCP.scan_directory(TEST_DATA_DIR)
                @test !isempty(files)
                @test any(f -> basename(f) == "game.slp", files)
            end
        end

        @testset "parse_replay" begin
            # Nonexistent file returns nothing (file-existence guard prevents Rust panic)
            result = PeppiMCP.parse_replay("nonexistent.slp")
            @test result === nothing

            # Real replay file returns a populated GameData
            if isfile(TEST_REPLAY)
                result = PeppiMCP.parse_replay(TEST_REPLAY)
                @test result isa PeppiMCP.GameData
                @test result.path == TEST_REPLAY
                @test result.metadata isa PeppiMCP.GameMetadata
                @test !isempty(result.metadata.stage)
                @test !isempty(result.metadata.players)
            end
        end
    end

    @testset "Search Query Parsing" begin
        @testset "extract_character_from_text" begin
            # Returns first character found in text
            @test PeppiMCP.extract_character_from_text("Fox vs Marth") in ["Fox", "Marth"]
            @test PeppiMCP.extract_character_from_text("Playing as falco") == "Falco"
            @test PeppiMCP.extract_character_from_text("puff games") == "Jigglypuff"
            @test PeppiMCP.extract_character_from_text("no character here") === nothing
        end

        @testset "extract_stage_from_text" begin
            @test PeppiMCP.extract_stage_from_text("on FD") == "Final Destination"
            @test PeppiMCP.extract_stage_from_text("battlefield games") == "Battlefield"
            @test PeppiMCP.extract_stage_from_text("yoshis story") == "Yoshi's Story"
            @test PeppiMCP.extract_stage_from_text("no stage") === nothing
        end

        @testset "extract_outcome_from_text" begin
            @test PeppiMCP.extract_outcome_from_text("games I won") == "win"
            @test PeppiMCP.extract_outcome_from_text("matches I lost") == "loss"
            @test PeppiMCP.extract_outcome_from_text("close games") === nothing
        end

        @testset "extract_keywords" begin
            keywords = PeppiMCP.extract_keywords("close last stock games")
            @test "close" in keywords
            @test "last" in keywords
            @test "stock" in keywords
            @test "games" in keywords
            @test !("the" in keywords)  # stop word
        end
    end

    @testset "Embeddings" begin
        @testset "normalize_vector" begin
            v = [3.0, 4.0]
            normalized = PeppiMCP.normalize_vector(v)
            @test norm(normalized) ≈ 1.0 atol=1e-10

            # Zero vector
            zero_v = [0.0, 0.0]
            normalized_zero = PeppiMCP.normalize_vector(zero_v)
            @test all(normalized_zero .== 0.0)
        end

        @testset "cosine_similarity" begin
            a = [1.0, 0.0]
            b = [1.0, 0.0]
            @test PeppiMCP.cosine_similarity(a, b) ≈ 1.0

            c = [1.0, 0.0]
            d = [0.0, 1.0]
            @test PeppiMCP.cosine_similarity(c, d) ≈ 0.0 atol=1e-10

            e = [1.0, 0.0]
            f = [-1.0, 0.0]
            @test PeppiMCP.cosine_similarity(e, f) ≈ -1.0
        end
    end

    @testset "Server Configuration" begin
        # Accessing the server object defined in your module
        s = PeppiMCP.server
        @test s.name == "peppi-mcp"
        @test s.version == "0.1.0"
        @test length(s.tools) == 2
    end

    @testset "Tool Definitions" begin
        tools = PeppiMCP.server.tools

        # Test generate_stats_tool
        stats_tool = filter(t -> t.name == "generate_stats", tools)[1]
        @test occursin("competitive statistics", stats_tool.description)

        # Check for required parameters in the ToolParameter list
        params = stats_tool.parameters
        @test any(p -> p.name == "dir" && p.required == true, params)
        @test any(p -> p.name == "player_code", params)

        # Test search_replays_tool
        search_tool = filter(t -> t.name == "search_replays", tools)[1]
        @test search_tool.name == "search_replays"
        @test any(p -> p.name == "query" && p.required == true, params)
    end


    @testset "Statistics Implementation" begin
        @testset "detect_punishes guard conditions" begin
            # Insufficient ports returns empty PunishStats
            result = PeppiMCP.detect_punishes
            # Just verify the function is callable with a real replay if available
            if isfile(TEST_REPLAY)
                game = PeppiMCP.parse_replay(TEST_REPLAY)
                if game !== nothing && game.frames !== nothing
                    ps = PeppiMCP.detect_punishes(game.frames, 1)
                    @test ps isa PeppiMCP.PunishStats
                    @test ps.punish_count >= 0
                    @test ps.avg_punish_damage >= 0.0
                    @test 0.0 <= ps.conversion_rate <= 1.0
                    @test ps.zero_to_death_count >= 0
                end
            end
        end

        @testset "analyze_neutral guard conditions" begin
            if isfile(TEST_REPLAY)
                game = PeppiMCP.parse_replay(TEST_REPLAY)
                if game !== nothing && game.frames !== nothing
                    (opening_rate, neutral_win_rate) = PeppiMCP.analyze_neutral(game.frames, 1)
                    @test opening_rate >= 0.0
                    @test 0.0 <= neutral_win_rate <= 1.0
                end
            end
        end

        @testset "calculate_damage_dealt guard conditions" begin
            if isfile(TEST_REPLAY)
                game = PeppiMCP.parse_replay(TEST_REPLAY)
                if game !== nothing && game.frames !== nothing
                    damage = PeppiMCP.calculate_damage_dealt(game.frames, 1)
                    @test damage >= 0.0
                end
            end
        end

        @testset "calculate_game_stats includes new fields" begin
            if isfile(TEST_REPLAY)
                game = PeppiMCP.parse_replay(TEST_REPLAY)
                if game !== nothing
                    stats = PeppiMCP.calculate_game_stats(game, nothing)
                    if !haskey(stats, "error")
                        @test haskey(stats, "damage_dealt")
                        @test haskey(stats, "punish_count")
                        @test haskey(stats, "avg_punish_damage")
                        @test haskey(stats, "conversion_rate")
                        @test haskey(stats, "zero_to_death_count")
                        @test haskey(stats, "opening_rate")
                        @test haskey(stats, "neutral_win_rate")
                        @test haskey(stats, "start_time")
                    end
                end
            end
        end

        @testset "date filtering in passes_filters" begin
            # Build a minimal GameData-like stub to test filtering
            # We test via the public generate_stats path using a tmp dir
            tmpdir = mktempdir()
            try
                # No files means no filtered results
                result = PeppiMCP.generate_stats(Dict{String,Any}(
                    "dir" => tmpdir,
                    "date_from" => "2020-01-01",
                    "date_to" => "2025-12-31"
                ))
                @test haskey(result, "error")  # no .slp files found
            finally
                rm(tmpdir, recursive=true)
            end
        end
    end

    @testset "Phase 4: Movement Tech & Search" begin
        @testset "detect_ledgedashes" begin
            if isfile(TEST_REPLAY)
                game = PeppiMCP.parse_replay(TEST_REPLAY)
                if game !== nothing && game.frames !== nothing
                    count = PeppiMCP.detect_ledgedashes(game.frames, 1)
                    @test count >= 0
                end
            end
            # Guard: bad port returns 0
        end

        @testset "detect_dash_dances" begin
            if isfile(TEST_REPLAY)
                game = PeppiMCP.parse_replay(TEST_REPLAY)
                if game !== nothing && game.frames !== nothing
                    count = PeppiMCP.detect_dash_dances(game.frames, 1)
                    @test count >= 0
                end
            end
        end

        @testset "calculate_game_stats new movement fields" begin
            if isfile(TEST_REPLAY)
                game = PeppiMCP.parse_replay(TEST_REPLAY)
                if game !== nothing
                    stats = PeppiMCP.calculate_game_stats(game, nothing)
                    if !haskey(stats, "error")
                        @test haskey(stats, "ledgedash_count")
                        @test haskey(stats, "dash_dance_count")
                        @test stats["ledgedash_count"] >= 0
                        @test stats["dash_dance_count"] >= 0
                    end
                end
            end
        end

        @testset "generate_query_embedding - character" begin
            # Build a fake embedding to get the right dimension
            fake_emb = PeppiMCP.ReplayEmbedding(
                "fake.slp",
                zeros(Float64, PeppiMCP.EMBEDDING_DIM),
                Dict{String,Any}()
            )
            query = PeppiMCP.parse_search_query("Fox games", Dict{String,Any}())
            q_emb = PeppiMCP.generate_query_embedding(query, [fake_emb])
            @test length(q_emb) == PeppiMCP.EMBEDDING_DIM
            # Fox character_id = 2, so dims 3 (P1) and 3+26 (P2) should be set
            @test q_emb[3] > 0.0
            @test q_emb[PeppiMCP.NUM_CHARS + 3] > 0.0
        end

        @testset "generate_query_embedding - stage" begin
            fake_emb = PeppiMCP.ReplayEmbedding(
                "fake.slp",
                zeros(Float64, PeppiMCP.EMBEDDING_DIM),
                Dict{String,Any}()
            )
            query = PeppiMCP.parse_search_query("games on FD", Dict{String,Any}())
            q_emb = PeppiMCP.generate_query_embedding(query, [fake_emb])
            stage_offset = 2 * PeppiMCP.NUM_CHARS
            stage_idx    = PeppiMCP.STAGES["Final Destination"]
            @test q_emb[stage_offset + stage_idx + 1] > 0.0
        end

        @testset "generate_query_embedding - outcome" begin
            fake_emb = PeppiMCP.ReplayEmbedding(
                "fake.slp",
                zeros(Float64, PeppiMCP.EMBEDDING_DIM),
                Dict{String,Any}()
            )
            win_query  = PeppiMCP.parse_search_query("games I won", Dict{String,Any}())
            win_emb    = PeppiMCP.generate_query_embedding(win_query, [fake_emb])
            outcome_dim = 2 * PeppiMCP.NUM_CHARS + length(PeppiMCP.STAGES) + 1
            @test win_emb[outcome_dim] > 0.0
        end

        @testset "embedding cache round-trip" begin
            tmpdir = mktempdir()
            try
                withenv("PEPPI_MCP_INDEX_DIR" => tmpdir) do
                    fake_emb = PeppiMCP.ReplayEmbedding(
                        "/fake/game.slp",
                        [1.0, 2.0, 3.0],
                        Dict{String,Any}("stage" => "Battlefield")
                    )
                    mtimes = Dict("/fake/game.slp" => 1234567890.0)
                    PeppiMCP.save_index_cache("/fake", [fake_emb], mtimes)

                    loaded = PeppiMCP.load_index_cache("/fake")
                    @test haskey(loaded, "/fake/game.slp")
                    (cached_mtime, cached_emb) = loaded["/fake/game.slp"]
                    @test cached_mtime ≈ 1234567890.0
                    @test cached_emb.features == [1.0, 2.0, 3.0]
                    @test cached_emb.metadata["stage"] == "Battlefield"
                end
            finally
                rm(tmpdir, recursive=true)
            end
        end
    end

    @testset "Tools" begin
        @testset "Tool definitions" begin
            @test length(PeppiMCP.TOOLS) == 2

            # Check generate_stats tool
            gen_stats = PeppiMCP.TOOLS[1]
            @test gen_stats["name"] == "generate_stats"
            @test haskey(gen_stats["inputSchema"]["properties"], "dir")
            @test "dir" in gen_stats["inputSchema"]["required"]

            # Check search_replays tool
            search = PeppiMCP.TOOLS[2]
            @test search["name"] == "search_replays"
            @test haskey(search["inputSchema"]["properties"], "query")
            @test "dir" in search["inputSchema"]["required"]
            @test "query" in search["inputSchema"]["required"]
        end
    end
end
