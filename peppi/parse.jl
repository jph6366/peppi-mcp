using Arrow

include("frame.jl")

# Helper to convert CamelCase to SCREAMING_SNAKE_CASE for enum lookup
function to_upper_snake_case(s::AbstractString)
    result = replace(s, r"([a-z])([A-Z])" => s"\1_\2")
    return uppercase(result)
end

# Unwrap Union{T, Nothing} to get T
function unwrap_union(::Type{Union{T, Nothing}}) where T
    return T
end

function unwrap_union(::Type{T}) where T
    return T
end

# Get field from Arrow.Struct by name using .data tuple
function arrow_getfield(arr::Arrow.Struct{T, D, S}, fieldname::Symbol) where {T, D, S}
    idx = findfirst(==(fieldname), S)
    if idx === nothing
        return nothing  # Return nothing for missing fields instead of error
    end
    return arr.data[idx]
end

# Get field from Arrow struct array, with default fallback
function arr_field(arr::Arrow.Struct, fieldname::Symbol, default=nothing)
    result = arrow_getfield(arr, fieldname)
    if result === nothing
        return default
    end
    return result
end

# Fallback for non-Arrow.Struct types
function arr_field(arr, fieldname::Symbol, default=nothing)
    try
        return getproperty(arr, fieldname)
    catch e
        if default === nothing
            rethrow(e)
        else
            return default
        end
    end
end

# Parse field from Arrow struct array based on type
function field_from_sa(::Type{T}, arr) where T
    if arr === nothing
        return nothing
    end
    
    unwrapped = unwrap_union(T)
    
    if unwrapped <: Tuple
        return tuple_from_sa(unwrapped, arr)
    elseif isstructtype(unwrapped) && !(unwrapped <: AbstractString) && !(unwrapped <: AbstractVector)
        return dc_from_sa(unwrapped, arr)
    else
        return copy(arr)
    end
end

# Parse dataclass-like struct from Arrow struct array
function dc_from_sa(::Type{T}, arr) where T
    field_names = fieldnames(T)
    field_types = fieldtypes(T)
    
    values = []
    for (fname, ftype) in zip(field_names, field_types)
        # Get default value if field has one
        default = nothing
        try
            default = getfield(T(), fname)
        catch
        end
        
        field_arr = arr_field(arr, fname, default)
        push!(values, field_from_sa(ftype, field_arr))
    end
    
    return T(values...)
end

# Parse tuple from Arrow struct array
function tuple_from_sa(::Type{T}, arr) where T <: Tuple
    type_params = T.parameters
    return Tuple(field_from_sa(type_params[i], arr_field(arr, Symbol(string(i - 1)))) for i in eachindex(type_params))
end

# Handle Vararg tuples
function tuple_from_sa(::Type{Tuple{Vararg{T}}}, arr) where T
    # For variable-length tuples, iterate over available fields
    results = T[]
    for i in 0:100  # reasonable upper bound
        try
            field_arr = arr_field(arr, Symbol(string(i)))
            push!(results, field_from_sa(T, field_arr))
        catch
            break
        end
    end
    return Tuple(results)
end

# Parse frames from Arrow struct array (column-oriented)
function frames_from_sa(arrow_frames)
    if arrow_frames === nothing
        return nothing
    end
    
    ports = PortData[]
    port_arrays = arrow_getfield(arrow_frames, :ports)
    
    for p in (:P1, :P2, :P3, :P4)
        port = arrow_getfield(port_arrays, p)
        if port === nothing
            continue
        end
        
        leader_data = arrow_getfield(port, :leader)
        if leader_data === nothing
            continue
        end
        leader = dc_from_sa(Data, leader_data)
        
        follower_data = arrow_getfield(port, :follower)
        follower = follower_data === nothing ? nothing : dc_from_sa(Data, follower_data)
        
        push!(ports, PortData(leader=leader, follower=follower))
    end
    
    return Frame(id=arrow_getfield(arrow_frames, :id), ports=Tuple(ports))
end

# Parse field from JSON (Dict) based on type
function field_from_json(::Type{T}, json) where T
    if json === nothing
        return nothing
    end
    
    unwrapped = unwrap_union(T)
    
    if unwrapped <: Enum
        return enum_from_json(unwrapped, json)
    elseif unwrapped <: Tuple
        return tuple_from_json(unwrapped, json)
    elseif isstructtype(unwrapped) && !(unwrapped <: AbstractString) && !(unwrapped <: Number)
        return dc_from_json(unwrapped, json)
    else
        return json
    end
end

# Parse enum from JSON string
function enum_from_json(::Type{T}, json::AbstractString) where T <: Enum
    enum_name = Symbol(to_upper_snake_case(json))
    # First, try exact match
    for e in instances(T)
        if Symbol(e) == enum_name
            return e
        end
    end
    # If no exact match, try suffix match (e.g., "UCF" matches "DASHBACK_UCF")
    for e in instances(T)
        e_name_str = String(Symbol(e))
        if endswith(e_name_str, "_" * String(enum_name)) || endswith(e_name_str, String(enum_name))
            return e
        end
    end
    error("Unknown enum value: $json for type $T")
end

function enum_from_json(::Type{T}, json::Integer) where T <: Enum
    return T(json)
end

# Parse dataclass-like struct from JSON (Dict or JSON.Object)
function dc_from_json(::Type{T}, json::AbstractDict) where T
    field_names = fieldnames(T)
    field_types = fieldtypes(T)
    
    values = []
    for (fname, ftype) in zip(field_names, field_types)
        json_value = get(json, string(fname), nothing)
        push!(values, field_from_json(ftype, json_value))
    end
    
    return T(values...)
end

# Parse tuple from JSON
function tuple_from_json(::Type{T}, json) where T <: Tuple
    type_params = T.parameters
    
    if json isa Dict
        items = collect(pairs(json))
    else
        items = collect(enumerate(json))
    end
    
    child_type = type_params[1]
    return Tuple(field_from_json(child_type, val) for (idx, val) in items)
end

# Handle Vararg tuples from JSON
function tuple_from_json(::Type{Tuple{Vararg{T}}}, json) where T
    if json isa Dict
        items = values(json)
    else
        items = json
    end
    
    return Tuple(field_from_json(T, val) for val in items)
end
