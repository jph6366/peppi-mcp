# Note: frame.jl and util.jl are included via parse.jl

@enum Port begin
    P1 = 0
    P2 = 1
    P3 = 2
    P4 = 3
end

@enum PlayerType begin
    HUMAN = 0
    CPU = 1
    DEMO = 2
end

@enum Language begin
    JAPANESE = 0
    ENGLISH = 1
end

@enum DashBack begin
    DASHBACK_UCF = 1
    DASHBACK_ARDUINO = 2
end

@enum ShieldDrop begin
    SHIELDDROP_UCF = 1
    SHIELDDROP_ARDUINO = 2
end

@enum EndMethod begin
    UNRESOLVED = 0
    TIME = 1
    GAME = 2
    RESOLVED = 3
    NO_CONTEST = 7
end

Base.@kwdef struct Scene
    major::Int
    minor::Int
end

Base.@kwdef struct Match
    id::String
    game::Int
    tiebreaker::Int
end

Base.@kwdef struct Slippi
    version::Tuple{Int, Int, Int}
end

Base.@kwdef struct Netplay
    name::String
    code::String
    suid::Union{String, Nothing} = nothing
end

Base.@kwdef struct Team
    color::Int
    shade::Int
end

Base.@kwdef struct Ucf
    dash_back::Union{DashBack, Nothing}
    shield_drop::Union{ShieldDrop, Nothing}
end

Base.@kwdef struct Player
    port::Port
    character::Int
    type::PlayerType
    stocks::Int
    costume::Int
    team::Union{Team, Nothing}
    handicap::Int
    bitfield::Int
    cpu_level::Union{Int, Nothing}
    offense_ratio::Float64
    defense_ratio::Float64
    model_scale::Float64
    ucf::Union{Ucf, Nothing} = nothing
    name_tag::Union{String, Nothing} = nothing
    netplay::Union{Netplay, Nothing} = nothing
end

Base.@kwdef struct GameStart
    slippi::Slippi
    bitfield::Tuple{Int, Int, Int, Int}
    is_raining_bombs::Bool
    is_teams::Bool
    item_spawn_frequency::Int
    self_destruct_score::Int
    stage::Int
    timer::Int
    item_spawn_bitfield::Tuple{Int, Int, Int, Int, Int}
    damage_ratio::Float64
    players::Tuple{Vararg{Player}}
    random_seed::Int
    is_pal::Union{Bool, Nothing} = nothing
    is_frozen_ps::Union{Bool, Nothing} = nothing
    scene::Union{Scene, Nothing} = nothing
    language::Union{Language, Nothing} = nothing
    match::Union{Match, Nothing} = nothing
end

Base.@kwdef struct PlayerEnd
    port::Port
    placement::Int
end

Base.@kwdef struct GameStop
    method::EndMethod
    lras_initiator::Union{Port, Nothing} = nothing
    players::Union{Tuple{Vararg{PlayerEnd}}, Nothing} = nothing
end

Base.@kwdef struct Game
    start::GameStart
    stop::GameStop
    metadata::Dict
    frames::Union{Frame, Nothing}
end
