push!(LOAD_PATH, joinpath(pwd(), "peppi"))
try
    using Peppi
    println("✓ Peppi module loaded successfully")
catch e
    println("✗ Failed to load Peppi:")
    println(sprint(showerror, e, catch_backtrace()))
end
