struct CST <: AbstractThermalTech
    min_kw::Real
    max_kw::Real
    production_factor::AbstractVector{<:Real}
    elec_consumption_factor_series::AbstractVector{<:Real}
    installed_cost_per_kw::Real
    om_cost_per_kw::Real
    om_cost_per_kwh::Real
    acres_per_kw::Real
    macrs_option_years::Int
    macrs_bonus_fraction::Real
    tech_type::String
    can_supply_steam_turbine::Bool
    can_serve_dhw::Bool
    can_serve_space_heating::Bool
    can_serve_process_heat::Bool
    can_waste_heat::Bool
    charge_storage_only::Bool
    emissions_factor_lb_CO2_per_mmbtu::Real
    emissions_factor_lb_NOx_per_mmbtu::Real
    emissions_factor_lb_SO2_per_mmbtu::Real
    emissions_factor_lb_PM25_per_mmbtu::Real
    inlet_temp_degF::Real
    outlet_temp_degF::Real
end

"""
    CST

If a user provides the `CST` key then the optimal scenario has the option to purchase this new 
`CST` technology to meet compatible heating loads in addition to using the `ExistingBoiler` 
to meet the heating load(s). 

```julia
function CST(;
    min_kw::Real = 0.0, # Minimum thermal power size (capacity)
    max_kw::Real = BIG_NUMBER, # Maximum thermal power size (capacity)
    production_factor::AbstractVector{<:Real} = Float64[],  production factor
    elec_consumption_factor_series::AbstractVector{<:Real} = Float64[], electric consumption factor per kw TODO: (do we need? are we including parasitics?) 
    acres_per_kw::Union{Real,Nothing} = nothing, # 
    macrs_option_years::Union{Int,Nothing} = nothing, # MACRS schedule for financial analysis. Set to zero to disable
    macrs_bonus_fraction::Union{Real,Nothing} = nothing, # Fraction of upfront project costs to depreciate under MACRS
    installed_cost_per_kw::Union{Real,Nothing} = nothing, # Thermal power-based cost, see cst_defaults.json for CST default by type
    om_cost_per_kw::Union{Real,Nothing} = nothing, # Thermal power-based fixed O&M cost, see cst_defaults.json for CST default by type
    om_cost_per_kwh::Union{Real,Nothing} = nothing, # Thermal energy produced-based variable O&M cost
    tech_type::Union{String,Nothing} = nothing,  # restrict to: ["ptc", "mst", "lf", "swh_evactube", "swh_flatplate"]
    can_supply_steam_turbine::Union{Bool,Nothing} = nothing # If the CST can supply steam to the steam turbine for electric production
    can_serve_dhw::Union{Bool,Nothing} = nothing # If CST can supply heat to the domestic hot water load
    can_serve_space_heating::Union{Bool,Nothing} = nothing # If CST can supply heat to the space heating load
    can_serve_process_heat::Union{Bool,Nothing} = nothing # If CST can supply heat to the process heating load
    can_waste_heat::Union{Bool,Nothing} = nothing # If CST can curtail excess heat
    charge_storage_only::Union{Bool,Nothing} = nothing # If CST can only supply hot TES (i.e., cannot meet load directly)
    emissions_factor_lb_CO2_per_mmbtu::Real = 0.0
    emissions_factor_lb_NOx_per_mmbtu::Real = 0.0
    emissions_factor_lb_SO2_per_mmbtu::Real = 0.0
    emissions_factor_lb_PM25_per_mmbtu::Real = 0.0
    inlet_temp_degF::Real = 400.0 # heat transfer medium temperature at inlet of CST heat offtaker (e.g., inlet to HTF hot tank or industrial process)
    outlet_temp_degF::Real = 70.0 # heat transfer medium temperature at outlet of CST heat offtaker (e.g., HTF cold tank storage)
)
```
"""
function CST(;
        min_kw::Real = 0.0,
        max_kw::Real = BIG_NUMBER,
        production_factor::AbstractVector{<:Real} = Float64[],
        elec_consumption_factor_series::AbstractVector{<:Real} = Float64[],
        macrs_option_years::Union{Int,Nothing} = nothing,
        macrs_bonus_fraction::Union{Real,Nothing} = nothing,
        installed_cost_per_kw::Union{Real,Nothing} = nothing,
        om_cost_per_kw::Union{Real,Nothing} = nothing,  #per kw per year
        om_cost_per_kwh::Union{Real,Nothing} = nothing,   #per kwh produced
        acres_per_kw::Union{Real,Nothing} = nothing,
        tech_type::Union{String,Nothing} = nothing,  # restrict to: ["ptc", "mst", "lf", "swh_evactube", "swh_flatplate"]  TODO update with Jeff's work
        can_supply_steam_turbine::Union{Bool,Nothing} = nothing,
        can_serve_dhw::Union{Bool,Nothing} = nothing,
        can_serve_space_heating::Union{Bool,Nothing} = nothing,
        can_serve_process_heat::Union{Bool,Nothing} = nothing,
        can_waste_heat::Union{Bool,Nothing} = nothing,
        charge_storage_only::Union{Bool,Nothing} = nothing,
        emissions_factor_lb_CO2_per_mmbtu::Real = 0.0,
        emissions_factor_lb_NOx_per_mmbtu::Real = 0.0,
        emissions_factor_lb_SO2_per_mmbtu::Real = 0.0,
        emissions_factor_lb_PM25_per_mmbtu::Real = 0.0,
        inlet_temp_degF::Real = 400.0,
        outlet_temp_degF::Real = 70.0
    )

    if isempty(production_factor)
        throw(@error("CST.production_factor is a required input when modeling a heating load which is served by the ConcentratedSolar system in the optimal case"))
    end
    if isempty(elec_consumption_factor_series)
        throw(@error("CST.elec_consumption_factor_series is a required input when modeling a heating load which is served by the ConcentratedSolar system in the optimal case"))
    end

    if isnothing(tech_type)
        tech_type = "ptc"
    end
    defaults = get_cst_defaults(tech_type)
    if isnothing(macrs_option_years)
        macrs_option_years = defaults["macrs_option_years"]
    end
    if isnothing(macrs_bonus_fraction)
        macrs_bonus_fraction = defaults["macrs_bonus_fraction"]
    end
    if isnothing(installed_cost_per_kw)
        installed_cost_per_kw = defaults["installed_cost_per_kw"]
    end
    if isnothing(om_cost_per_kw)
        om_cost_per_kw = defaults["om_cost_per_kw"]
    end
    if isnothing(om_cost_per_kwh)
        om_cost_per_kwh = defaults["om_cost_per_kwh"]
    end
    if isnothing(acres_per_kw)
        acres_per_kw = defaults["acres_per_kw"]
    end
    if isnothing(can_supply_steam_turbine)
        can_supply_steam_turbine = defaults["can_supply_steam_turbine"]
    end
    if isnothing(can_serve_dhw)
        can_serve_dhw = defaults["can_serve_dhw"]
    end
    if isnothing(can_serve_space_heating)
        can_serve_space_heating = defaults["can_serve_space_heating"]
    end
    if isnothing(can_serve_process_heat)
        can_serve_process_heat = defaults["can_serve_process_heat"]
    end
    if isnothing(can_waste_heat)
        can_waste_heat = defaults["can_waste_heat"]
    end
    if isnothing(charge_storage_only)
        charge_storage_only = defaults["charge_storage_only"]
    end

    CST(
        min_kw,
        max_kw,
        production_factor,
        elec_consumption_factor_series,
        installed_cost_per_kw,
        om_cost_per_kw,
        om_cost_per_kwh,
        acres_per_kw,
        macrs_option_years,
        macrs_bonus_fraction,
        tech_type,
        can_supply_steam_turbine,
        can_serve_dhw,
        can_serve_space_heating,
        can_serve_process_heat,
        can_waste_heat,
        charge_storage_only,
        emissions_factor_lb_CO2_per_mmbtu,
        emissions_factor_lb_NOx_per_mmbtu,
        emissions_factor_lb_SO2_per_mmbtu,
        emissions_factor_lb_PM25_per_mmbtu,
        inlet_temp_degF,
        outlet_temp_degF
    )
end


"""
function get_cst_defaults(tech_type::String="")

Obtains defaults for the ConcnetratingSolar technology type, taken from a JSON data file. 

inputs
tech_type::String -- identifier of CST technology type

returns
cst_defaults::Dict -- Dictionary containing defaults for CST technology type
"""
function get_cst_defaults(tech_type::String="")
    if !(tech_type in CST_TYPES)
        throw(@error("Invalid inputs: argument `tech_type` to function get_cst_defaults() is invalid."))
    end
    all_cst_defaults = JSON.parsefile(joinpath(dirname(@__FILE__), "..", "..", "data", "cst", "cst_defaults.json"))
    return all_cst_defaults[tech_type]
end
