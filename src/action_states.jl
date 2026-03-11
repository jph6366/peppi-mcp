"""
Action state constants from Melee
Based on ssbm-data and Slippi documentation
"""

# Common action states
const ACTION_WAIT = 14
const ACTION_DASH = 20
const ACTION_RUN = 22
const ACTION_JUMP_F = 24
const ACTION_JUMP_B = 25
const ACTION_JUMP_AERIAL_F = 26
const ACTION_JUMP_AERIAL_B = 27

# Landing
const ACTION_LANDING = 43
const ACTION_LANDING_FALL_SPECIAL = 44

# Damage/Hitstun
const ACTION_DAMAGE_START = 75
const ACTION_DAMAGE_AIR = 76
const ACTION_DAMAGE_FLY_HIGH = 77
const ACTION_DAMAGE_FLY_N = 78
const ACTION_DAMAGE_FLY_TOP = 79
const ACTION_DAMAGE_FLY_ROLL = 80

# Cliff
const ACTION_CLIFF_CATCH = 252
const ACTION_CLIFF_WAIT  = 253
const ACTION_CLIFF_WAIT2 = 254

# Shield
const ACTION_GUARD_ON = 178
const ACTION_GUARD = 179
const ACTION_GUARD_OFF = 180

# Attacks
const ACTION_ATTACK_100_START = 50
const ACTION_ATTACK_AIR_N = 65
const ACTION_ATTACK_AIR_F = 66
const ACTION_ATTACK_AIR_B = 67
const ACTION_ATTACK_AIR_HI = 68
const ACTION_ATTACK_AIR_LW = 69

# Grounded attacks
const ACTION_ATTACK_S3 = 52  # Forward tilt
const ACTION_ATTACK_HI3 = 53  # Up tilt
const ACTION_ATTACK_LW3 = 54  # Down tilt
const ACTION_ATTACK_S4 = 55  # Forward smash
const ACTION_ATTACK_HI4 = 56  # Up smash
const ACTION_ATTACK_LW4 = 57  # Down smash

# Special moves (character-specific)
const ACTION_SPECIAL_N = 341
const ACTION_SPECIAL_S = 345
const ACTION_SPECIAL_HI = 349
const ACTION_SPECIAL_LW = 353

# Grab
const ACTION_GRAB = 212
const ACTION_GRAB_PULLING = 214

# Helpers
"""
Check if action state is a cliff-hang state (ledge grab or hang)
"""
function is_cliff_hang(state::Integer)::Bool
    return state == ACTION_CLIFF_CATCH ||
           state == ACTION_CLIFF_WAIT  ||
           state == ACTION_CLIFF_WAIT2
end

"""
Check if action state is in hitstun/tumble
"""
function is_hitstun(state::Integer)::Bool
    return state in (
        ACTION_DAMAGE_START,
        ACTION_DAMAGE_AIR,
        ACTION_DAMAGE_FLY_HIGH,
        ACTION_DAMAGE_FLY_N,
        ACTION_DAMAGE_FLY_TOP,
        ACTION_DAMAGE_FLY_ROLL
    )
end

"""
Check if action state is grounded
"""
function is_grounded(state::Integer)::Bool
    # Simple heuristic: states < 330 are mostly grounded
    # More precise: check specific state ranges
    return state < 14 ||  # Wait and below
           (state >= 14 && state <= 43) ||  # Wait through landing
           (state >= 50 && state <= 62) ||  # Ground attacks
           (state >= 178 && state <= 182)   # Shield states
end

"""
Check if action state is aerial
"""
function is_aerial(state::Integer)::Bool
    return (state >= 24 && state <= 42) ||  # Jumps and aerial movement
           (state >= 65 && state <= 69)      # Aerial attacks
end

"""
Check if action state is an attack
"""
function is_attack(state::Integer)::Bool
    return (state >= 44 && state <= 81) ||   # Ground attacks + aerials
           (state >= 341 && state <= 366)     # Special moves
end
