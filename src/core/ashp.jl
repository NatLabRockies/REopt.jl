# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

"""
ASHPSpaceHeater

If a user provides the `ASHPSpaceHeater` key then the optimal scenario has the option to purchase 
this new `ASHP` to meet the heating load in addition to using the `ExistingBoiler`
to meet the heating load. 

ASHPSpaceHeater has the following attributes: 
```julia
    min_kw::Real # Minimum thermal power size
    max_kw::Real # Maximum thermal power size
    min_allowable_kw::Real # Minimum nonzero thermal power size if included
    sizing_factor::Real # Size multiplier of system, relative that of the max load given by dispatch profile
    installed_cost_per_kw::Real # Thermal power-based cost
    om_cost_per_kw::Real # Thermal power-based fixed O&M cost
    macrs_option_years::Int # MACRS schedule for financial analysis. Set to zero to disable
    macrs_bonus_fraction::Real # Fraction of upfront project costs to depreciate under MACRS
    heating_cop::Array{<:Real,1} # COP of the heating (i.e., thermal produced / electricity consumed)
    cooling_cop::Array{<:Real,1} # COP of the cooling (i.e., thermal produced / electricity consumed)
    heating_cf::Array{<:Real,1} # ASHP's heating capacity factor curves
    cooling_cf::Array{<:Real,1} # ASHP's cooling capacity factor curves
    can_serve_cooling::Bool # If ASHP can supply heat to the cooling load
    force_into_system::Bool # force into system to serve all space heating loads if true
    force_dispatch::Bool # force ASHP to meet load or maximize output if true
    back_up_temp_threshold_degF::Real # Degree in F that system switches from ASHP to resistive heater 
    avoided_capex_by_ashp_present_value::Real # avoided capital expenditure due to presence of ASHP system vs. defaults heating and cooling techs
    max_ton::Real # maximum allowable thermal power (tons) 

```
"""
struct ASHP <: AbstractThermalTech
    min_kw::Real
    max_kw::Real
    min_allowable_kw::Real
    sizing_factor::Real
    installed_cost_per_kw::Real
    om_cost_per_kw::Real
    macrs_option_years::Int
    macrs_bonus_fraction::Real
    can_supply_steam_turbine::Bool
    heating_cop::Array{<:Real,1}
    cooling_cop::Array{<:Real,1}
    heating_cf::Array{<:Real,1}
    cooling_cf::Array{<:Real,1}
    can_serve_dhw::Bool
    can_serve_space_heating::Bool
    can_serve_process_heat::Bool
    can_serve_cooling::Bool
    force_into_system::Bool
    force_dispatch::Bool
    back_up_temp_threshold_degF::Real
    avoided_capex_by_ashp_present_value::Real
    max_ton::Real
    installed_cost_per_ton::Real
    om_cost_per_ton::Real
    heating_cop_reference::Array{<:Real,1}
    heating_cf_reference::Array{<:Real,1}
    heating_reference_temps_degF::Array{<:Real,1}
    cooling_cop_reference::Array{<:Real,1}
    cooling_cf_reference::Array{<:Real,1}
    cooling_reference_temps_degF::Array{<:Real,1}
end


"""
ASHPSpaceHeater

If a user provides the `ASHPSpaceHeater` key then the optimal scenario has the option to purchase 
this new `ASHP` to meet the heating load in addition to using the `ExistingBoiler`
to meet the heating load. 

```julia
function ASHPSpaceHeater(;
    min_ton::Real = 0.0, # Minimum thermal power size
    max_ton::Real = BIG_NUMBER, # Maximum thermal power size
    min_allowable_ton::Union{Real, Nothing} = nothing, # Minimum nonzero thermal power size if included
    min_allowable_peak_capacity_fraction::Union{Real, Nothing} = nothing, # minimum allowable fraction of peak heating + cooling load
    sizing_factor::::Union{Real, Nothing} = nothing, # Size multiplier of system, relative that of the max load given by dispatch profile
    om_cost_per_ton::Union{Real, nothing} = nothing, # Thermal power-based fixed O&M cost
    macrs_option_years::Int = 0, # MACRS schedule for financial analysis. Set to zero to disable
    macrs_bonus_fraction::Real = 0.0, # Fraction of upfront project costs to depreciate under MACRS
    can_serve_cooling::Union{Bool, Nothing} = nothing # If ASHP can supply heat to the cooling load
    force_into_system::Bool = false # force into system to serve all space heating loads if true
    force_dispatch::Bool = true # force ASHP to meet load or maximize output if true
    avoided_capex_by_ashp_present_value::Real = 0.0 # avoided capital expenditure due to presence of ASHP system vs. defaults heating and cooling techs

    #The following inputs are used to create the attributes heating_cop and heating cf: 
    heating_cop_reference::Array{<:Real,1}, # COP of the heating (i.e., thermal produced / electricity consumed)
    heating_cf_reference::Array{<:Real,1}, # ASHP's heating capacity factor curves
    heating_reference_temps_degF ::Array{<:Real,1}, # ASHP's reference temperatures for heating COP and CF
    back_up_temp_threshold_degF::Real = 10, # Degree in F that system switches from ASHP to resistive heater
    
    #The following inputs are used to create the attributes cooling_cop and cooling cf: 
    cooling_cop::Array{<:Real,1}, # COP of the cooling (i.e., thermal produced / electricity consumed)
    cooling_cf::Array{<:Real,1}, # ASHP's cooling capacity factor curves
    cooling_reference_temps_degF ::Array{<:Real,1}, # ASHP's reference temperatures for cooling COP and CF
    
    #The following inputs are taken from the Site object:
    ambient_temp_degF::Array{<:Real,1}  #time series of ambient temperature
    heating_load::Array{Real,1} # time series of site space heating load
    cooling_load::Union{Array{Real,1}, Nothing} # time series of site cooling load
)
```
"""
function ASHPSpaceHeater(;
        min_ton::Real = 0.0,
        max_ton::Union{Real, Nothing} = nothing,
        min_allowable_ton::Union{Real, Nothing} = nothing,
        min_allowable_peak_capacity_fraction::Union{Real, Nothing} = nothing, 
        sizing_factor::Union{Real, Nothing} = nothing, 
        installed_cost_per_ton::Union{Real, Nothing} = nothing,
        om_cost_per_ton::Union{Real, Nothing} = nothing,
        macrs_option_years::Int = 0,
        macrs_bonus_fraction::Real = 0.0,
        avoided_capex_by_ashp_present_value::Real = 0.0,
        can_serve_cooling::Union{Bool, Nothing} = nothing,
        force_into_system::Bool = false,
        force_dispatch::Bool = true,
        heating_cop_reference::Array{<:Real,1} = Real[],
        heating_cf_reference::Array{<:Real,1} = Real[],
        heating_reference_temps_degF::Array{<:Real,1} = Real[],
        back_up_temp_threshold_degF::Union{Real, Nothing} = nothing,
        cooling_cop_reference::Array{<:Real,1} = Real[],
        cooling_cf_reference::Array{<:Real,1} = Real[],
        cooling_reference_temps_degF::Array{<:Real,1} = Real[],
        ambient_temp_degF::Array{<:Real,1} = Real[],
        heating_load::Array{<:Real,1} = Real[],
        cooling_load::Array{<:Real,1} = Real[]
    )

    defaults = get_ashp_defaults("SpaceHeating",force_into_system)

    # populate defaults as needed
    if isnothing(installed_cost_per_ton)
        installed_cost_per_ton = defaults["installed_cost_per_ton"]
    end
    if isnothing(om_cost_per_ton)
        om_cost_per_ton = defaults["om_cost_per_ton"]
    end
    if isnothing(can_serve_cooling)
        can_serve_cooling = defaults["can_serve_cooling"]
    end
    if isnothing(force_into_system)
        force_into_system = defaults["force_into_system"]
    end
    if isnothing(back_up_temp_threshold_degF)
        back_up_temp_threshold_degF = defaults["back_up_temp_threshold_degF"]
    end
    if isnothing(sizing_factor)
        sizing_factor = defaults["sizing_factor"]
    end

    if length(heating_cop_reference) != length(heating_cf_reference) || length(heating_cf_reference) != length(heating_reference_temps_degF)
        throw(@error("heating_cop_reference, heating_cf_reference, and heating_reference_temps_degF must all be the same length."))
    else
        if length(heating_cop_reference) == 0
            heating_cop_reference = convert(Vector{Float64}, defaults["heating_cop_reference"])
            heating_cf_reference = convert(Vector{Float64}, defaults["heating_cf_reference"])
            heating_reference_temps_degF = convert(Vector{Float64}, defaults["heating_reference_temps_degF"])
        end
    end
    if length(cooling_cop_reference) != length(cooling_cf_reference) || length(cooling_cf_reference) != length(cooling_reference_temps_degF)
        throw(@error("cooling_cop_reference, cooling_cf_reference, and cooling_reference_temps_degF must all be the same length."))
    else
        if length(cooling_cop_reference) == 0 && can_serve_cooling
            cooling_cop_reference = convert(Vector{Float64}, defaults["cooling_cop_reference"])
            cooling_cf_reference = convert(Vector{Float64}, defaults["cooling_cf_reference"])
            cooling_reference_temps_degF = convert(Vector{Float64}, defaults["cooling_reference_temps_degF"])
        end
    end

    #pre-set defaults that aren't mutable due to technology specifications
    can_supply_steam_turbine = defaults["can_supply_steam_turbine"]
    can_serve_space_heating = defaults["can_serve_space_heating"]
    can_serve_dhw = defaults["can_serve_dhw"]
    can_serve_process_heat = defaults["can_serve_process_heat"]
    

    installed_cost_per_kw = installed_cost_per_ton / KWH_THERMAL_PER_TONHOUR
    om_cost_per_kw = om_cost_per_ton / KWH_THERMAL_PER_TONHOUR

    heating_cop, heating_cf = get_ashp_performance(heating_cop_reference,
        heating_cf_reference,
        heating_reference_temps_degF,
        ambient_temp_degF,
        back_up_temp_threshold_degF
        )

    heating_cf[heating_cop .== 1] .= 1

    if can_serve_cooling
        cooling_cop, cooling_cf = get_ashp_performance(cooling_cop_reference,
            cooling_cf_reference,
            cooling_reference_temps_degF,
            ambient_temp_degF,
            -460
            )
    else
        cooling_cop = Float64[]
        cooling_cf = Float64[]
    end

    if isnothing(max_ton)
        if can_serve_cooling 
            #these are in kW rathern than tons so will be larger as a measure of conservatism
            max_ton = min(defaults["max_ton"], 10*(maximum(heating_load ./ heating_cf)+maximum(cooling_load ./ cooling_cf)))
        else
            max_ton = min(defaults["max_ton"], 10*maximum(heating_load ./ heating_cf))
        end
    else
        if can_serve_cooling 
            max_ton = min(max_ton, 10*(maximum(heating_load ./ heating_cf)+maximum(cooling_load ./ cooling_cf)))
        else
            max_ton = min(max_ton, 10*maximum(heating_load ./ heating_cf)) 
        end
        max_ton = max(max_ton, min_ton)
    end

    # Convert max sizes, cost factors from mmbtu_per_hour to kw
    min_kw = min_ton * KWH_THERMAL_PER_TONHOUR
    max_kw = max_ton * KWH_THERMAL_PER_TONHOUR    

    if !isnothing(min_allowable_ton) && !isnothing(min_allowable_peak_capacity_fraction)
        throw(@error("at most one of min_allowable_ton and min_allowable_peak_capacity_fraction may be input."))
    elseif !isnothing(min_allowable_ton)
        min_allowable_kw = min_allowable_ton * KWH_THERMAL_PER_TONHOUR
        @warn("user-provided minimum allowable ton is used in the place of the default; this may provided very small sizes if set to zero.")
    else
        if isnothing(min_allowable_peak_capacity_fraction)
            min_allowable_peak_capacity_fraction = 0.25
        end
        min_allowable_kw = get_ashp_default_min_allowable_size(heating_load, heating_cf, cooling_load, cooling_cf, min_allowable_peak_capacity_fraction)
    end

    if min_allowable_kw > max_kw
        throw(@error("The ASHPSpaceHeater minimum allowable size of $min_allowable_kw kW is larger than the maximum size of $max_kw kW."))
    end

    installed_cost_per_kw *= sizing_factor
    om_cost_per_kw *= sizing_factor

    ASHP(
        min_kw,
        max_kw,
        min_allowable_kw,
        sizing_factor,
        installed_cost_per_kw,
        om_cost_per_kw,
        macrs_option_years,
        macrs_bonus_fraction,
        can_supply_steam_turbine,
        heating_cop,
        cooling_cop,
        heating_cf,
        cooling_cf,
        can_serve_dhw,
        can_serve_space_heating,
        can_serve_process_heat,
        can_serve_cooling,
        force_into_system,
        force_dispatch,
        back_up_temp_threshold_degF,
        avoided_capex_by_ashp_present_value,
        max_ton,
        installed_cost_per_ton,
        om_cost_per_ton,
        heating_cop_reference,
        heating_cf_reference,
        heating_reference_temps_degF,
        cooling_cop_reference,
        cooling_cf_reference,
        cooling_reference_temps_degF
    )
end


"""
ASHP Water_Heater

If a user provides the `ASHPWaterHeater` key then the optimal scenario has the option to purchase 
this new `ASHPWaterHeater` to meet the domestic hot water load in addition to using the `ExistingBoiler`
to meet the domestic hot water load. 

```julia
function ASHPWaterHeater(;
    min_ton::Real = 0.0, # Minimum thermal power size
    max_ton::Real = BIG_NUMBER, # Maximum thermal power size
    min_allowable_ton::Real = 0.0 # Minimum nonzero thermal power size if included
    installed_cost_per_ton::Union{Real, nothing} = nothing, # Thermal power-based cost
    om_cost_per_ton::Union{Real, nothing} = nothing, # Thermal power-based fixed O&M cost
    macrs_option_years::Int = 0, # MACRS schedule for financial analysis. Set to zero to disable
    macrs_bonus_fraction::Real = 0.0, # Fraction of upfront project costs to depreciate under MACRS
    can_supply_steam_turbine::Union{Bool, nothing} = nothing # If the boiler can supply steam to the steam turbine for electric production
    avoided_capex_by_ashp_present_value::Real = 0.0 # avoided capital expenditure due to presence of ASHP system vs. defaults heating and cooling techs
    force_into_system::Bool = false # force into system to serve all hot water loads if true
    force_dispatch::Bool = true # force ASHP to meet load or maximize output if true
    
    #The following inputs are used to create the attributes heating_cop and heating cf: 
    heating_cop_reference::Array{<:Real,1}, # COP of the heating (i.e., thermal produced / electricity consumed)
    heating_cf_reference::Array{<:Real,1}, # ASHP's heating capacity factor curves
    heating_reference_temps_degF ::Array{<:Real,1}, # ASHP's reference temperatures for heating COP and CF
    back_up_temp_threshold_degF::Real = 10 # temperature threshold at which backup resistive heater is used

    #The following inputs are taken from the Site object:
    ambient_temp_degF::Array{<:Real,1} = Float64[] # time series of ambient temperature 
    heating_load::Array{<:Real,1} # time series of site domestic hot water load
)
```
"""
function ASHPWaterHeater(;
    min_ton::Real = 0.0,
    max_ton::Union{Real, Nothing} = nothing,
    min_allowable_ton::Union{Real, Nothing} = nothing,
    min_allowable_peak_capacity_fraction::Union{Real, Nothing} = nothing, 
    sizing_factor::Union{Real, Nothing} = nothing, 
    installed_cost_per_ton::Union{Real, Nothing} = nothing,
    om_cost_per_ton::Union{Real, Nothing} = nothing,
    macrs_option_years::Int = 0,
    macrs_bonus_fraction::Real = 0.0,
    avoided_capex_by_ashp_present_value::Real = 0.0,
    force_into_system::Bool = false,
    force_dispatch::Bool = true,
    heating_cop_reference::Array{<:Real,1} = Real[],
    heating_cf_reference::Array{<:Real,1} = Real[],
    heating_reference_temps_degF::Array{<:Real,1} = Real[],
    back_up_temp_threshold_degF::Union{Real, Nothing} = nothing,
    ambient_temp_degF::Array{<:Real,1} = Real[],
    heating_load::Array{<:Real,1} = Real[]
    )

    defaults = get_ashp_defaults("DomesticHotWater",force_into_system)

    # populate defaults as needed
    if isnothing(installed_cost_per_ton)
        installed_cost_per_ton = defaults["installed_cost_per_ton"]
    end
    if isnothing(om_cost_per_ton)
        om_cost_per_ton = defaults["om_cost_per_ton"]
    end
    if isnothing(back_up_temp_threshold_degF)
        back_up_temp_threshold_degF = defaults["back_up_temp_threshold_degF"]
    end
    if isnothing(sizing_factor)
        sizing_factor = defaults["sizing_factor"]
    end

    if length(heating_cop_reference) != length(heating_cf_reference) || length(heating_cf_reference) != length(heating_reference_temps_degF)
        throw(@error("heating_cop_reference, heating_cf_reference, and heating_reference_temps_degF must all be the same length."))
    else
        if length(heating_cop_reference) == 0
            heating_cop_reference = convert(Vector{Float64}, defaults["heating_cop_reference"])
            heating_cf_reference = convert(Vector{Float64}, defaults["heating_cf_reference"])
            heating_reference_temps_degF = convert(Vector{Float64}, defaults["heating_reference_temps_degF"])
        end
    end

     #pre-set defaults that aren't mutable due to technology specifications
     can_supply_steam_turbine = defaults["can_supply_steam_turbine"]
     can_serve_space_heating = defaults["can_serve_space_heating"]
     can_serve_dhw = defaults["can_serve_dhw"]
     can_serve_process_heat = defaults["can_serve_process_heat"]
     can_serve_cooling = defaults["can_serve_cooling"]

    installed_cost_per_kw = installed_cost_per_ton / KWH_THERMAL_PER_TONHOUR
    om_cost_per_kw = om_cost_per_ton / KWH_THERMAL_PER_TONHOUR

    heating_cop, heating_cf = get_ashp_performance(heating_cop_reference,
        heating_cf_reference,
        heating_reference_temps_degF,
        ambient_temp_degF,
        back_up_temp_threshold_degF
        )
    
    heating_cf[heating_cop .== 1] .= 1

    if isnothing(max_ton)
        #these are in kW rathern than tons so will be larger as a measure of conservatism
        max_ton = min(defaults["max_ton"], 10*maximum(heating_load ./ heating_cf))
    else
        max_ton = min(max_ton, 10*maximum(heating_load ./ heating_cf))
    end
    max_ton = max(max_ton, min_ton)

    # Convert max sizes, cost factors from mmbtu_per_hour to kw
    min_kw = min_ton * KWH_THERMAL_PER_TONHOUR
    max_kw = max_ton * KWH_THERMAL_PER_TONHOUR  

    if !isnothing(min_allowable_ton) && !isnothing(min_allowable_peak_capacity_fraction)
        throw(@error("at most one of min_allowable_ton and min_allowable_peak_capacity_fraction may be input."))
    elseif !isnothing(min_allowable_ton)
        min_allowable_kw = min_allowable_ton * KWH_THERMAL_PER_TONHOUR
        @warn("user-provided minimum allowable ton is used in the place of the default; this may provided very small sizes if set to zero.")
    else
        if isnothing(min_allowable_peak_capacity_fraction)
            min_allowable_peak_capacity_fraction = 0.25
        end
        min_allowable_kw = get_ashp_default_min_allowable_size(heating_load, heating_cf, Real[], Real[], min_allowable_peak_capacity_fraction)
    end

    if min_allowable_kw > max_kw
        throw(@error("The ASHPWaterHeater minimum allowable size of $min_allowable_kw kW is larger than the maximum size of $max_kw kW."))
    end

    ASHP(
        min_kw,
        max_kw,
        min_allowable_kw,
        sizing_factor,
        installed_cost_per_kw,
        om_cost_per_kw,
        macrs_option_years,
        macrs_bonus_fraction,
        can_supply_steam_turbine,
        heating_cop,
        Float64[],
        heating_cf,
        Float64[],
        can_serve_dhw,
        can_serve_space_heating,
        can_serve_process_heat,
        can_serve_cooling,
        force_into_system,
        force_dispatch,
        back_up_temp_threshold_degF,
        avoided_capex_by_ashp_present_value,
        max_ton,
        installed_cost_per_ton,
        om_cost_per_ton,
        heating_cop_reference,
        heating_cf_reference,
        heating_reference_temps_degF,
        Real[],
        Real[],
        Real[]
    )
end



"""
function get_ashp_defaults(load_served::String="SpaceHeating")

Obtains defaults for the ASHP from a JSON data file. 

inputs
load_served::String -- identifier of heating load served by AHSP system
force_into_system::Bool -- exclusively serves compatible thermal loads if true (i.e., replaces existing technologies)

returns
ashp_defaults::Dict -- Dictionary containing defaults for ASHP
"""
function get_ashp_defaults(load_served::String="SpaceHeating", force_into_system::Bool=false)
    if !(load_served in ["SpaceHeating", "DomesticHotWater"])
        throw(@error("Invalid inputs: argument `load_served` to function get_ashp_defaults() must be a String in the set ['SpaceHeating', 'DomesticHotWater']."))
    end
    all_ashp_defaults = JSON.parsefile(joinpath(dirname(@__FILE__), "..", "..", "data", "ashp", "ashp_defaults.json"))
    defaults = all_ashp_defaults[load_served]
    if force_into_system
        defaults["sizing_factor"] = 1.1
        defaults["om_cost_per_ton"] = 0.0
    end
    return defaults
end

"""
function get_ashp_performance(cop_reference,
                cf_reference,
                reference_temps,
                ambient_temp_degF,
                back_up_temp_threshold_degF
                )
"""
function get_ashp_performance(cop_reference,
    cf_reference,
    reference_temps,
    ambient_temp_degF,
    back_up_temp_threshold_degF
    )
    num_timesteps = length(ambient_temp_degF)
    cop = zeros(num_timesteps)
    cf = zeros(num_timesteps)
    for ts in 1:num_timesteps
        if ambient_temp_degF[ts] < reference_temps[1] && ambient_temp_degF[ts] < last(reference_temps)
            cop[ts] = cop_reference[argmin(reference_temps)]
            cf[ts] = cf_reference[argmin(reference_temps)]
        elseif ambient_temp_degF[ts] > reference_temps[1] && ambient_temp_degF[ts] > last(reference_temps)
            cop[ts] = cop_reference[argmax(reference_temps)]
            cf[ts] = cf_reference[argmax(reference_temps)]
        else
            for i in 2:length(reference_temps)
                if ambient_temp_degF[ts] >= min(reference_temps[i-1], reference_temps[i]) &&
                    ambient_temp_degF[ts] <= max(reference_temps[i-1], reference_temps[i])
                    cop[ts] = cop_reference[i-1] + (cop_reference[i]-cop_reference[i-1])*(ambient_temp_degF[ts]-reference_temps[i-1])/(reference_temps[i]-reference_temps[i-1])
                    cf[ts] = cf_reference[i-1] + (cf_reference[i]-cf_reference[i-1])*(ambient_temp_degF[ts]-reference_temps[i-1])/(reference_temps[i]-reference_temps[i-1])
                    break
                end
            end
        end
        if ambient_temp_degF[ts] < back_up_temp_threshold_degF
            cop[ts] = 1.0
            cf[ts] = 1.0
        end
    end
    return cop, cf
end

"""
function get_ashp_default_min_allowable_size(heating_load::Array{Float64},  # time series of heating load
    heating_cf::Array{Float64,1},   # time series of capacity factor for heating
    cooling_load::Array{Float64,1} = Float64[], # # time series of capacity factor for heating
    cooling_cf::Array{Float64,1} = Float64[], # time series of capacity factor for heating
    peak_load_thermal_factor::Float64 = 0.5 # peak load multiplier for minimum allowable size           
    )

Obtains the default minimum allowable size for ASHP system.  This is calculated as half of the peak site thermal load(s) addressed by the system, including the capacity factor
"""
function get_ashp_default_min_allowable_size(heating_load::Array{<:Real,1}, 
    heating_cf::Array{<:Real,1}, 
    cooling_load::Array{<:Real,1}, 
    cooling_cf::Array{<:Real,1},
    peak_load_thermal_factor::Real
    )

    if isempty(cooling_cf)
        peak_load = maximum(heating_load ./ heating_cf)
    else
        peak_load = maximum( (heating_load ./ heating_cf) .+ (cooling_load ./ cooling_cf) )
    end

    return peak_load_thermal_factor * peak_load
end

