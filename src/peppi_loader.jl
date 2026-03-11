"""
Load the Peppi module from the peppi/ directory.
This works around the dependency issue by loading Peppi in a way that
finds JlrsCore and peppi_jlrs_jll from the global environment.
"""

# Add the peppi directory to LOAD_PATH temporarily
peppi_dir = joinpath(@__DIR__, "..", "peppi")
if !(peppi_dir in LOAD_PATH)
    pushfirst!(LOAD_PATH, peppi_dir)
end

# Now load Peppi - it will find JlrsCore from the global environment
try
    @eval using Peppi
    global Peppi_loaded = true
catch e
    @error "Failed to load Peppi module" exception=(e, catch_backtrace())
    global Peppi_loaded = false
end

# Remove from LOAD_PATH after loading
if peppi_dir in LOAD_PATH
    filter!(x -> x != peppi_dir, LOAD_PATH)
end
