# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

prime_movers = ["recip_engine", "micro_turbine", "combustion_turbine", "fuel_cell"]
conflict_res_min_allowable_fraction_of_max = 0.25

"""
`CHP` is an optional REopt input with the following keys and default values:
```julia
    prime_mover::Union{String, Nothing} = nothing # Suggested to inform applicable default cost and performance. "restrict_to": ["recip_engine", "micro_turbine", "combustion_turbine", "fuel_cell"]
    fuel_cost_per_mmbtu::Union{<:Real, AbstractVector{<:Real}} = [] # REQUIRED. Can be a scalar, a list of 12 monthly values, or a time series of values for every time step

    # Required "custom inputs" if not providing prime_mover:
    installed_cost_per_kw::Union{Float64, AbstractVector{Float64}} = NaN # Installed CHP system cost in \$/kW (based on rated electric power)
    tech_sizes_for_cost_curve::Union{Float64, AbstractVector{Float64}} = NaN # Size of CHP systems corresponding to installed cost input points"
    om_cost_per_kwh::Float64 = NaN # CHP non-fuel variable operations and maintenance costs in \$/kwh
    electric_efficiency_full_load::Float64 = NaN # Electric efficiency of CHP prime-mover at full-load, HHV-basis
    electric_efficiency_half_load::Float64 = NaN # Electric efficiency of CHP prime-mover at half-load, HHV-basis
    min_turn_down_fraction::Float64 = NaN # Minimum CHP electric loading in fraction of capacity (size_kw)
    thermal_efficiency_full_load::Float64 = NaN # CHP fraction of fuel energy converted to hot-thermal energy at full electric load
    thermal_efficiency_half_load::Float64 = NaN # CHP fraction of fuel energy converted to hot-thermal energy at half electric load
    min_allowable_kw::Float64 = NaN # Minimum CHP size (based on electric) that still allows the model to choose zero (e.g. no CHP system)
    cooling_thermal_factor::Float64 = NaN  # only needed with cooling load
    unavailability_periods::AbstractVector{Dict} = Dict[] # CHP unavailability periods for scheduled and unscheduled maintenance, list of dictionaries with keys of "['month', 'start_week_of_month', 'start_day_of_week', 'start_hour', 'duration_hours'] all values are one-indexed and start_day_of_week uses 1 for Monday, 7 for Sunday
    unavailability_hourly::AbstractVector{Int64} = Int64[] # Hourly 8760 profile of unavailability (1) and availability (0)

    # Optional inputs:
    size_class::Union{Int, Nothing} = nothing # CHP size class for using appropriate default inputs, with size_class=0 using an average of all other size class data 
    min_kw::Float64 = 0.0 # Minimum CHP size (based on electric) constraint for optimization 
    max_kw::Float64 = NaN # Maximum CHP size (based on electric) constraint for optimization. Determined by heuristic sizing based on heating load or electric load.    
    fuel_type::String = "natural_gas" # "restrict_to": ["natural_gas", "landfill_bio_gas", "propane", "diesel_oil"]
    om_cost_per_kw::Float64 = 0.0 # Annual CHP fixed operations and maintenance costs in \$/kw-yr 
    om_cost_per_hr_per_kw_rated::Float64 = 0.0 # CHP non-fuel variable operations and maintenance costs in \$/hr/kw_rated
    supplementary_firing_capital_cost_per_kw::Float64 = 150.0 # Installed CHP supplementary firing system cost in \$/kW (based on rated electric power)
    supplementary_firing_max_steam_ratio::Float64 = 1.0 # Ratio of max fired steam to un-fired steam production. Relevant only for combustion_turbine prime_mover 
    supplementary_firing_efficiency::Float64 = 0.92 # Thermal efficiency of the incremental steam production from supplementary firing. Relevant only for combustion_turbine prime_mover 
    standby_rate_per_kw_per_month::Float64 = 0.0 # Standby rate charged to CHP based on CHP electric power size
    reduces_demand_charges::Bool = true # Boolean indicator if CHP does not reduce demand charges 
    can_supply_steam_turbine::Bool=false # If CHP can supply steam to the steam turbine for electric production 
    can_serve_dhw::Bool = true # If CHP can supply heat to the domestic hot water load
    can_serve_space_heating::Bool = true # If CHP can supply heat to the space heating load
    can_serve_process_heat::Bool = true # If CHP can supply heat to the process heating load
    is_electric_only::Bool = false # If CHP is a prime generator that does not supply heat
    operating_reserve_required_fraction::Real = off_grid_flag ? 0.0 : 0.0 # If off grid, 10%, else 0%. Applied to each time_step as a % of CHP generation. When positive, CHP requires reserves from Generator or Battery; when 0, CHP can provide reserves.

    macrs_option_years::Int = 5 # Notes: this value cannot be 0 if aiming to apply 100% bonus depreciation; default may change if Site.sector is not "commercial/industrial"
    macrs_bonus_fraction::Float64 = 1.0 #Note: default may change if Site.sector is not "commercial/industrial"
    macrs_itc_reduction::Float64 = 0.5
    federal_itc_fraction::Float64 = 0.0
    federal_rebate_per_kw::Float64 = 0.0
    state_ibi_fraction::Float64 = 0.0
    state_ibi_max::Float64 = 1.0e10
    state_rebate_per_kw::Float64 = 0.0
    state_rebate_max::Float64 = 1.0e10
    utility_ibi_fraction::Float64 = 0.0
    utility_ibi_max::Float64 = 1.0e10
    utility_rebate_per_kw::Float64 = 0.0
    utility_rebate_max::Float64 = 1.0e10
    production_incentive_per_kwh::Float64 = 0.0 # revenue from production incentive per kWh electricity produced, including curtailment
    production_incentive_max_benefit::Float64 = 1.0e9 # maximum allowable annual revenue from production incentives
    production_incentive_years::Int = 0 # number of year in which production incentives are paid
    production_incentive_max_kw::Float64 = 1.0e9 # maximum allowable system size to receive production incentives
    can_net_meter::Bool = false
    can_wholesale::Bool = false
    can_export_beyond_nem_limit::Bool = false
    can_curtail::Bool = false
    fuel_renewable_energy_fraction::Float64 = FUEL_DEFAULTS["fuel_renewable_energy_fraction"][fuel_type]
    emissions_factor_lb_CO2_per_mmbtu::Float64 = FUEL_DEFAULTS["emissions_factor_lb_CO2_per_mmbtu"][fuel_type]
    emissions_factor_lb_NOx_per_mmbtu::Float64 = FUEL_DEFAULTS["emissions_factor_lb_NOx_per_mmbtu"][fuel_type]
    emissions_factor_lb_SO2_per_mmbtu::Float64 = FUEL_DEFAULTS["emissions_factor_lb_SO2_per_mmbtu"][fuel_type]
    emissions_factor_lb_PM25_per_mmbtu::Float64 = FUEL_DEFAULTS["emissions_factor_lb_PM25_per_mmbtu"][fuel_type]
```

!!! note "Defaults and required inputs"
    See the `get_chp_defaults_prime_mover_size_class()` function docstring for details on the logic of choosing the type of CHP that is modeled
    If no information is provided, the default `prime_mover` is `recip_engine` and the `size_class` is 0 which represents
    the widest range of sizes available.

    `fuel_cost_per_mmbtu` is always required and can be a scalar, a list of 12 monthly values, or a time series of values for every time step

"""
Base.@kwdef mutable struct CHP <: AbstractCHP
    # Required input
    fuel_cost_per_mmbtu::Union{<:Real, AbstractVector{<:Real}} = []    
    
    # Inputs which defaults vary depending on prime_mover and size_class
    installed_cost_per_kw::Union{Float64, AbstractVector{Float64}} = Float64[]
    tech_sizes_for_cost_curve::AbstractVector{Float64} = Float64[]
    om_cost_per_kwh::Float64 = NaN
    electric_efficiency_full_load::Float64 = NaN
    thermal_efficiency_full_load::Float64 = NaN
    min_allowable_kw::Float64 = NaN
    cooling_thermal_factor::Float64 = NaN  # only needed with cooling load
    min_turn_down_fraction::Float64 = NaN
    unavailability_periods::AbstractVector{Dict} = Dict[]
    unavailability_hourly::AbstractVector{Int64} = Int64[]

    # Optional inputs:
    prime_mover::Union{String, Nothing} = nothing
    size_class::Union{Int, Nothing} = nothing
    min_kw::Float64 = 0.0
    max_kw::Float64 = NaN
    fuel_type::String = "natural_gas"
    om_cost_per_kw::Float64 = 0.0
    om_cost_per_hr_per_kw_rated::Float64 = 0.0
    electric_efficiency_half_load::Float64 = NaN  # Assigned to electric_efficiency_full_load if not input
    thermal_efficiency_half_load::Float64 = NaN  # Assigned to thermal_efficiency_full_load if not input
    supplementary_firing_capital_cost_per_kw::Float64 = 150.0
    supplementary_firing_max_steam_ratio::Float64 = 1.0
    supplementary_firing_efficiency::Float64 = 0.92
    standby_rate_per_kw_per_month::Float64 = 0.0
    reduces_demand_charges::Bool = true
    can_supply_steam_turbine::Bool = false
    can_serve_dhw::Bool = true
    can_serve_space_heating::Bool = true
    can_serve_process_heat::Bool = true
    is_electric_only::Bool = false
    operating_reserve_required_fraction::Real = 0.0

    macrs_option_years::Int = 5
    macrs_bonus_fraction::Float64 = 1.0
    macrs_itc_reduction::Float64 = 0.5
    federal_itc_fraction::Float64 = 0.0 
    federal_rebate_per_kw::Float64 = 0.0
    state_ibi_fraction::Float64 = 0.0
    state_ibi_max::Float64 = 1.0e10
    state_rebate_per_kw::Float64 = 0.0
    state_rebate_max::Float64 = 1.0e10
    utility_ibi_fraction::Float64 = 0.0
    utility_ibi_max::Float64 = 1.0e10
    utility_rebate_per_kw::Float64 = 0.0
    utility_rebate_max::Float64 = 1.0e10
    production_incentive_per_kwh::Float64 = 0.0
    production_incentive_max_benefit::Float64 = 1.0e9
    production_incentive_years::Int = 0
    production_incentive_max_kw::Float64 = 1.0e9
    can_net_meter::Bool = false
    can_wholesale::Bool = false
    can_export_beyond_nem_limit::Bool = false
    can_curtail::Bool = false
    fuel_renewable_energy_fraction::Real = get(FUEL_DEFAULTS["fuel_renewable_energy_fraction"],fuel_type,0)
    emissions_factor_lb_CO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_CO2_per_mmbtu"],fuel_type,0)
    emissions_factor_lb_NOx_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_NOx_per_mmbtu"],fuel_type,0)
    emissions_factor_lb_SO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_SO2_per_mmbtu"],fuel_type,0)
    emissions_factor_lb_PM25_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_PM25_per_mmbtu"],fuel_type,0)
end


function CHP(d::Dict; 
            avg_boiler_fuel_load_mmbtu_per_hour::Union{Float64, Nothing}=nothing, 
            existing_boiler::Union{ExistingBoiler, Nothing}=nothing,
            electric_load_series_kw::Array{<:Real,1}=Real[],
            year::Int64=2017,
            sector::String,
            federal_procurement_type::String,
            off_grid_flag::Bool=false)
    # If array inputs are coming from Julia JSON.parsefile (reader), they have type Vector{Any}; convert to expected type here
    for (k,v) in d
        if typeof(v) <: AbstractVector{Any} && k != "unavailability_periods"
            d[k] = convert(Vector{Float64}, v)
        end
    end

    # Check for required fuel cost
    if !haskey(d, "fuel_cost_per_mmbtu")
        throw(@error("CHP must have the required fuel_cost_per_mmbtu input"))
    end

    d = dictkeys_tosymbols(d)
    set_sector_defaults!(d; struct_name="CHP", sector=sector, federal_procurement_type=federal_procurement_type)

    # Create CHP struct from inputs, to be mutated as needed
    chp = CHP(; d...)

    @assert chp.fuel_type in FUEL_TYPES

    # These inputs are set based on prime_mover and size_class
    custom_chp_inputs = Dict{Symbol, Any}(
        :installed_cost_per_kw => chp.installed_cost_per_kw, 
        :tech_sizes_for_cost_curve => chp.tech_sizes_for_cost_curve, 
        :om_cost_per_kwh => chp.om_cost_per_kwh, 
        :electric_efficiency_full_load => chp.electric_efficiency_full_load,
        :thermal_efficiency_full_load => chp.thermal_efficiency_full_load,
        :min_allowable_kw => chp.min_allowable_kw,
        :cooling_thermal_factor => chp.cooling_thermal_factor,
        :min_turn_down_fraction => chp.min_turn_down_fraction
    )

    # Installed cost input validation
    update_installed_cost_params = false
    pass_all_params_error = false
    if !isempty(chp.installed_cost_per_kw) && typeof(chp.installed_cost_per_kw) == Float64
        if !isempty(chp.tech_sizes_for_cost_curve)
            chp.tech_sizes_for_cost_curve = []
            @warn "Ignoring `chp.tech_sizes_for_cost_curve` input because `chp.installed_cost_per_kw` is a scalar"
        end
    elseif length(chp.installed_cost_per_kw) > 1 && length(chp.installed_cost_per_kw) != length(chp.tech_sizes_for_cost_curve)
        throw(@error("To model CHP cost curve, you must provide `chp.tech_sizes_for_cost_curve` vector of equal length to `chp.installed_cost_per_kw`"))
    elseif typeof(chp.installed_cost_per_kw) <: Array && length(chp.installed_cost_per_kw) == 1
        chp.installed_cost_per_kw = chp.installed_cost_per_kw[1]
    elseif isempty(chp.tech_sizes_for_cost_curve) && isempty(chp.installed_cost_per_kw)
        update_installed_cost_params = true
    elseif isempty(chp.prime_mover)
        pass_all_params_error = true
    end

    # Set all missing default values in custom_chp_inputs after checking for an existing boiler; this allows CHP wo/ existing boiler
    if !isnothing(existing_boiler)
        prod_type = existing_boiler.production_type
        eff = existing_boiler.efficiency
    else
        prod_type = "hot_water"
        eff = EXISTING_BOILER_EFFICIENCY
    end

    # For non-heating CHP, Prime Generator, defaults require electric load metrics
    if !isempty(electric_load_series_kw)
        avg_electric_load_kw = sum(electric_load_series_kw) / length(electric_load_series_kw)
        max_electric_load_kw = convert(Float64, maximum(electric_load_series_kw))
    else
        avg_electric_load_kw = nothing
        max_electric_load_kw = nothing
    end

    chp_defaults_response = get_chp_defaults_prime_mover_size_class(;hot_water_or_steam=prod_type,
                                                                avg_boiler_fuel_load_mmbtu_per_hour=avg_boiler_fuel_load_mmbtu_per_hour,
                                                                prime_mover=chp.prime_mover,
                                                                size_class=chp.size_class,
                                                                max_kw=chp.max_kw,
                                                                boiler_efficiency=eff,
                                                                avg_electric_load_kw=avg_electric_load_kw,
                                                                max_electric_load_kw=max_electric_load_kw,
                                                                is_electric_only=chp.is_electric_only,
                                                                thermal_efficiency=chp.thermal_efficiency_full_load)
    defaults = chp_defaults_response["default_inputs"]
    for (k, v) in custom_chp_inputs
        if k in [:installed_cost_per_kw, :tech_sizes_for_cost_curve]
            if update_installed_cost_params
                setproperty!(chp, k, defaults[string(k)])
            end
        elseif isnan(v)
            setproperty!(chp, k, defaults[string(k)])
        end
    end

    # Set electric and thermal half load efficiency to full load if not input
    if isnan(chp.electric_efficiency_half_load)
        chp.electric_efficiency_half_load = chp.electric_efficiency_full_load
    end
    if isnan(chp.thermal_efficiency_half_load)
        chp.thermal_efficiency_half_load = chp.thermal_efficiency_full_load
    end

    if isnan(chp.max_kw)
        chp.max_kw = chp_defaults_response["chp_max_size_kw"]
    end

    if chp.min_allowable_kw > chp.max_kw
        @warn "CHP.min_allowable_kw is greater than CHP.max_kw, so setting min_allowable_kw equal to $conflict_res_min_allowable_fraction_of_max of the max_kw"
        setproperty!(chp, :min_allowable_kw, chp.max_kw * conflict_res_min_allowable_fraction_of_max)
    end
        
    if isempty(chp.unavailability_periods)
        chp.unavailability_periods = defaults["unavailability_periods"]
    end
    chp.unavailability_hourly = generate_year_profile_hourly(year, chp.unavailability_periods)

    if isnothing(chp.size_class)
        chp.size_class = chp_defaults_response["size_class"]
    end

    if chp.is_electric_only && (chp.thermal_efficiency_full_load > 0.0)
        @warn "CHP.thermal_efficiency_full_load is greater than zero but chp.is_electric_only is selected, so setting chp.thermal_efficiency_full_load to zero."
        setproperty!(chp, :thermal_efficiency_full_load, 0.0)
    end

    if chp.is_electric_only && (chp.thermal_efficiency_half_load > 0.0)
        @warn "CHP.thermal_efficiency_half_load is greater than zero but chp.is_electric_only is selected, so setting chp.thermal_efficiency_half_load to zero."
        setproperty!(chp, :thermal_efficiency_half_load, 0.0)
    end

    # Set operating_reserve_required_fraction based on off_grid_flag
    if haskey(d, "operating_reserve_required_fraction")
        chp.operating_reserve_required_fraction = d["operating_reserve_required_fraction"]
    end

    # Validate operating_reserve_required_fraction for on-grid scenarios
    if !off_grid_flag && !(chp.operating_reserve_required_fraction == 0.0)
        @warn "CHP operating_reserve_required_fraction applies only when off_grid_flag is true. Setting operating_reserve_required_fraction to 0.0 for this on-grid analysis."
        chp.operating_reserve_required_fraction = 0.0
    end

    return chp
end


"""
    get_prime_mover_defaults(prime_mover::String, boiler_type::String, size_class::Int, prime_mover_defaults_all::Dict, is_electric_only::Bool)

return a Dict{String, Union{Float64, AbstractVector{Float64}}} by selecting the appropriate values from 
data/chp/chp_default_data.json, which contains values based on prime_mover, boiler_type, and size_class for the 
custom_chp_inputs, i.e.
- "installed_cost_per_kw"
- "tech_sizes_for_cost_curve"
- "om_cost_per_kwh"
- "electric_efficiency_full_load"
- "thermal_efficiency_full_load"
- "min_allowable_kw"
- "cooling_thermal_factor"
- "min_turn_down_fraction" 
- "unavailability_periods"
"""
function get_prime_mover_defaults(prime_mover::String, boiler_type::String, size_class::Int, prime_mover_defaults_all::Dict, is_electric_only::Bool)
    pmds = prime_mover_defaults_all
    prime_mover_defaults = Dict{String, Any}()
    # Since size_class=0 is the first entry in the one-based indexed arrays in Julia, we need to add 1 for indexing
    for key in keys(pmds[prime_mover])
        if key in ["thermal_efficiency_full_load", "thermal_efficiency_half_load"]
            if is_electric_only
                prime_mover_defaults[key] = 0.0
            else
                prime_mover_defaults[key] = pmds[prime_mover][key][boiler_type][size_class+1]
            end
        elseif key == "unavailability_periods"
            prime_mover_defaults[key] = convert(Vector{Dict}, pmds[prime_mover][key])
        else
            prime_mover_defaults[key] = pmds[prime_mover][key][size_class+1]
        end
        if key in ["installed_cost_per_kw", "om_cost_per_kwh"] && is_electric_only
            prime_mover_defaults[key] *= 0.75
        end
    end
    pmds = nothing

    for (k,v) in prime_mover_defaults
        if typeof(v) <: AbstractVector{Any} && k != "unavailability_periods"
            prime_mover_defaults[k] = convert(Vector{Float64}, v)  # JSON.parsefile makes things Vector{Any}
        end
    end
    
    return prime_mover_defaults
end


"""
    get_chp_defaults_prime_mover_size_class(;hot_water_or_steam::Union{String, Nothing}=nothing,
                                        avg_boiler_fuel_load_mmbtu_per_hour::Union{Float64, Vector{Float64}, Nothing}=nothing,
                                        prime_mover::Union{String, Nothing}=nothing,
                                        size_class::Union{Int64, Nothing}=nothing,
                                        max_kw::Float64=NaN,
                                        boiler_efficiency::Union{Float64, Nothing}=nothing,
                                        avg_electric_load_kw::Union{Float64, Nothing}=nothing,
                                        max_electric_load_kw::Union{Float64, Nothing}=nothing,
                                        is_electric_only::Bool=false,
                                        thermal_efficiency::Float64=NaN)

Depending on the set of inputs, different sets of outputs are determine in addition to all CHP cost and performance parameter defaults:
    1. Inputs: hot_water_or_steam and avg_boiler_fuel_load_mmbtu_per_hour
       Outputs: prime_mover, size_class, chp_elec_size_heuristic_kw, chp_max_size_kw
    2. Inputs: prime_mover and avg_boiler_fuel_load_mmbtu_per_hour
       Outputs: size_class, chp_elec_size_heuristic_kw, chp_max_size_kw
    3. Inputs: prime_mover and size_class
       Outputs: (uses default hot_water_or_steam), chp_max_size_kw
    4. Inputs: prime_mover
       Outputs: default average size_class = 0, chp_max_size_kw
    5. Inputs: prime_mover, avg_electric_load_kw, max_electric_load_kw
       Outputs: chp_elec_size_heuristic_kw, chp_max_size_kw

The main purpose of this function is to communicate the following mapping of dependency of CHP defaults versus 
    hot_water_or_steam and avg_boiler_fuel_load_mmbtu_per_hour:
If hot_water and <= 27 MMBtu/hr avg_boiler_fuel_load_mmbtu_per_hour --> prime_mover = recip_engine of size_class X
If hot_water and > 27 MMBtu/hr avg_boiler_fuel_load_mmbtu_per_hour --> prime_mover = combustion_turbine of size_class X
If steam and <= 7 MMBtu/hr avg_boiler_fuel_load_mmbtu_per_hour --> prime_mover = recip_engine of size_class X
If steam and > 7 MMBtu/hr avg_boiler_fuel_load_mmbtu_per_hour --> prime_mover = combustion_turbine of size_class X

The threshold avg_boiler_fuel_load_mmbtu_per_hour are based on industry expert judgements for applicable prime_movers where
reciprocating engine is more suitable for smaller sizes and hot water, and combustion turbine is more suitable
for larger sizes and steam.

The determination of size_class and defaults based only on the electric load metrics is for non-heating "CHP", a.k.a. Prime Generator
"""
function get_chp_defaults_prime_mover_size_class(;hot_water_or_steam::Union{String, Nothing}=nothing,
                                                avg_boiler_fuel_load_mmbtu_per_hour::Union{Float64, Vector{Float64}, Nothing}=nothing,
                                                prime_mover::Union{String, Nothing}=nothing,
                                                size_class::Union{Int64, Nothing}=nothing,
                                                max_kw::Float64=NaN,
                                                boiler_efficiency::Union{Float64, Nothing}=nothing,
                                                avg_electric_load_kw::Union{Float64, Nothing}=nothing,
                                                max_electric_load_kw::Union{Float64, Nothing}=nothing,
                                                is_electric_only::Union{Bool, Nothing}=nothing,
                                                thermal_efficiency::Float64=NaN)
    
    prime_mover_defaults_all = JSON.parsefile(joinpath(@__DIR__, "..", "..", "data", "chp", "chp_defaults.json"))
    avg_boiler_fuel_load_under_recip_over_ct = Dict([("hot_water", 27.0), ("steam", 7.0)])  # [MMBtu/hr] Based on external calcs for size versus production by prime_mover type

    # Inputs validation
    if !isnothing(prime_mover)
        if !(prime_mover in prime_movers)  # Validate user-entered hot_water_or_steam
            throw(@error("Invalid argument for `prime_mover`; must be in $prime_movers"))
        end
    end

    if !isnothing(hot_water_or_steam)  # Option 1 if prime_mover also not input
        if !(hot_water_or_steam in ["hot_water", "steam"])  # Validate user-entered hot_water_or_steam
            throw(@error("Invalid argument for `hot_water_or_steam``; must be `hot_water` or `steam`"))
        end
    else  # Options 2, 3, or 4
        hot_water_or_steam = "hot_water"
    end

    if !isnothing(avg_boiler_fuel_load_mmbtu_per_hour)  # Option 1
        if avg_boiler_fuel_load_mmbtu_per_hour <= 0
            throw(@error("avg_boiler_fuel_load_mmbtu_per_hour must be >= 0.0"))
        end
    end

    if !isnothing(size_class) && !isnothing(prime_mover) # Option 3
        n_classes = length(prime_mover_defaults_all[prime_mover]["installed_cost_per_kw"])
        # Note, size_class=0 is first class, so (n_class-1) is largest valid size_class number
        if size_class < 0 || size_class > (n_classes-1)
            throw(@error("The size class $size_class input is outside the valid range of 0 to $(n_classes-1) for prime_mover $prime_mover"))
        end
    end

    # Default value of is_electric_only is False
    if isnothing(is_electric_only)
        is_electric_only = false
    end

    # Calculate heuristic CHP size based on average thermal load, using the default size class efficiency data
    # and estimate max size based on 2x the heuristic size
    recalc_heuristic_flag = false
    boiler_effic = NaN
    if !isnothing(avg_boiler_fuel_load_mmbtu_per_hour) && !is_electric_only
        if isnothing(prime_mover)
            if avg_boiler_fuel_load_mmbtu_per_hour <= avg_boiler_fuel_load_under_recip_over_ct[hot_water_or_steam]
                prime_mover = "recip_engine"  # Must make an initial guess at prime_mover to use those thermal and electric efficiency params to convert to size
            else
                prime_mover = "combustion_turbine"
            end
        end
        if isnothing(size_class)
            size_class_calc = 0
            recalc_heuristic_flag = true
        else
            size_class_calc = size_class
        end
        if isnothing(boiler_efficiency)
            boiler_effic = existing_boiler_efficiency_defaults[hot_water_or_steam]
        else
            boiler_effic = boiler_efficiency
        end
        chp_elec_size_heuristic_kw = get_heuristic_chp_size_kw(prime_mover_defaults_all, avg_boiler_fuel_load_mmbtu_per_hour, 
                                        prime_mover, size_class_calc, hot_water_or_steam, boiler_effic, thermal_efficiency)
        chp_max_size_kw = 2 * chp_elec_size_heuristic_kw
    # If available, calculate heuristic CHP size based on average electric load, and max size based on peak electric load
    elseif !isnothing(avg_electric_load_kw) && !isnothing(max_electric_load_kw)
        chp_elec_size_heuristic_kw = avg_electric_load_kw
        chp_max_size_kw = max_electric_load_kw
    else
        chp_elec_size_heuristic_kw = nothing
        chp_max_size_kw = nothing
    end

    # Assign recip_engine as the (default) prime mover if not input or assigned base on avg_boiler_fuel_load_mmbtu_per_hour
    if isnothing(prime_mover)
        prime_mover = "recip_engine"
    end

    # Overwrite chp_max_size_kw, if max_kw is input
    if !isnan(max_kw)
        chp_max_size_kw = max_kw
    end

    # prime_mover now assigned even if it was not input, so now load in these size_class metrics
    n_classes = length(prime_mover_defaults_all[prime_mover]["installed_cost_per_kw"])
    class_bounds = prime_mover_defaults_all[prime_mover]["tech_sizes_for_cost_curve"]

    # If size class is specified use that and ignore heuristic CHP sizing for determining size class
    if !isnothing(size_class)
        if size_class < 0 || size_class > (n_classes-1)
            throw(@error("The size class $size_class input is outside the valid range of 1 to $(n_classes-1) for prime_mover $prime_mover"))
        end
        if isnothing(chp_max_size_kw)
            chp_max_size_kw = class_bounds[size_class+1][2]
        end
    # If size class is not specified, heuristic sizing based on avg thermal load and size class 0 efficiencies
    elseif isnothing(size_class) && !isnothing(chp_elec_size_heuristic_kw)
        # With heuristic size, find the suggested size class
        size_class = get_size_class_from_size(chp_elec_size_heuristic_kw, class_bounds, n_classes)
    else
        size_class = 0
    end

    # Recalculate heuristic size based on updated size_class, and iterate if 
    #    necessary if size_class changes after recalc
    if recalc_heuristic_flag
        size_class_last = [0]
        while !(size_class in size_class_last)
            append!(size_class_last, size_class)
            chp_elec_size_heuristic_kw = get_heuristic_chp_size_kw(prime_mover_defaults_all, avg_boiler_fuel_load_mmbtu_per_hour, 
            prime_mover, size_class, hot_water_or_steam, boiler_effic, thermal_efficiency)
            chp_max_size_kw = 2 * chp_elec_size_heuristic_kw
            size_class = get_size_class_from_size(chp_elec_size_heuristic_kw, class_bounds, n_classes)            
        end
    end

    prime_mover_defaults = get_prime_mover_defaults(prime_mover, hot_water_or_steam, size_class, prime_mover_defaults_all, is_electric_only)

    if !isnothing(chp_max_size_kw) && prime_mover_defaults["min_allowable_kw"] > chp_max_size_kw
        prime_mover_defaults["min_allowable_kw"] = chp_max_size_kw * conflict_res_min_allowable_fraction_of_max
    end

    response = Dict([
        ("prime_mover", prime_mover),
        ("size_class", size_class),
        ("hot_water_or_steam", hot_water_or_steam),
        ("default_inputs", prime_mover_defaults),
        ("chp_elec_size_heuristic_kw", chp_elec_size_heuristic_kw),
        ("size_class_bounds", class_bounds),
        ("chp_max_size_kw", chp_max_size_kw)
    ])
    return response

end

function get_heuristic_chp_size_kw(prime_mover_defaults_all, avg_boiler_fuel_load_mmbtu_per_hour, 
                                prime_mover, size_class, hot_water_or_steam, boiler_effic, thermal_efficiency=NaN)
    if isnan(thermal_efficiency)
        therm_effic = prime_mover_defaults_all[prime_mover]["thermal_efficiency_full_load"][hot_water_or_steam][size_class+1]
    else
        therm_effic = thermal_efficiency
    end
    if therm_effic == 0.0
        if prime_mover == "micro_turbine" && isnothing(size_class)
            size_class = "any"
        end
        throw(@error("Error trying to calculate heuristic CHP size based on average thermal load because the 
                    thermal efficiency of prime_mover $prime_mover (size_class $size_class) for generating $hot_water_or_steam is 0.0"))
    end
    elec_effic = prime_mover_defaults_all[prime_mover]["electric_efficiency_full_load"][size_class+1]
    avg_heating_thermal_load_mmbtu_per_hr = avg_boiler_fuel_load_mmbtu_per_hour * boiler_effic
    chp_fuel_rate_mmbtu_per_hr = avg_heating_thermal_load_mmbtu_per_hr / therm_effic
    chp_elec_size_heuristic_kw = chp_fuel_rate_mmbtu_per_hr * elec_effic * KWH_PER_MMBTU
    
    return chp_elec_size_heuristic_kw
end

function get_size_class_from_size(chp_elec_size_heuristic_kw, class_bounds, n_classes)
    if chp_elec_size_heuristic_kw < class_bounds[2][2]
        # If smaller than the upper bound of the smallest class, assign the smallest class
        size_class = 1
    elseif chp_elec_size_heuristic_kw >= class_bounds[n_classes][1]
        # If larger than or equal to the lower bound of the largest class, assign the largest class
        size_class = n_classes - 1 # Size classes are zero-indexed
    else
        # For middle size classes
        for sc in 3:(n_classes-1)
            if chp_elec_size_heuristic_kw >= class_bounds[sc][1] && 
                chp_elec_size_heuristic_kw < class_bounds[sc][2]
                size_class = sc - 1
                break
            end
        end
    end
    return size_class
end
