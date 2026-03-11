push!(LOAD_PATH, joinpath(pwd(), "src"))
using PeppiMCP
println("Module loaded successfully!")
println("Available tools: ", length(PeppiMCP.TOOLS))
