# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ExistingChiller` is an optional REopt input with the following keys and default values:
```julia
    loads_kw_thermal::Vector{<:Real},
    cop::Union{Real, Nothing} = nothing,
    max_thermal_factor_on_peak_load::Real=1.25
    retire_in_optimal::Bool = false  # Do NOT use in the optimal case (still used in BAU)
```

!!! note "Max ExistingChiller size" 
    The maximum size [kW] of the `ExistingChiller` will be set based on the peak thermal load as follows:
    ```julia 
    max_kw = maximum(loads_kw_thermal) * max_thermal_factor_on_peak_load
    ```
"""
struct ExistingChiller <: AbstractThermalTech
    max_kw::Real
    cop::Union{Real, Nothing}
    max_thermal_factor_on_peak_load::Real
    retire_in_optimal::Bool
end


function ExistingChiller(;
        loads_kw_thermal::Vector{<:Real},
        cop::Union{Real, Nothing} = nothing,
        max_thermal_factor_on_peak_load::Real=1.25,
        retire_in_optimal::Bool = false
    )
    max_kw = maximum(loads_kw_thermal) * max_thermal_factor_on_peak_load
    ExistingChiller(
        max_kw,
        cop,
        max_thermal_factor_on_peak_load,
        retire_in_optimal
    )
end

