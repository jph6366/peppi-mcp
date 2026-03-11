#!/usr/bin/env julia

"""
peppi-mcp server executable
Launches the MCP stdio server for Slippi replay analysis
"""

# Get the directory containing this script
const SCRIPT_DIR = @__DIR__
const PROJECT_DIR = dirname(SCRIPT_DIR)

# Activate the project environment
import Pkg
Pkg.activate(PROJECT_DIR)

# Load the PeppiMCP module
push!(LOAD_PATH, joinpath(PROJECT_DIR, "src"))
using PeppiMCP

# Run the server
PeppiMCP.run_server()
