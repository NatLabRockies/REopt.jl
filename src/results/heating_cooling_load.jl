# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`CoolingLoad` results keys:
- `load_series_ton` # vector of site cooling load in every time step
- `annual_calculated_tonhour` # sum of the `load_series_ton`. Annual site total cooling load [tonhr]
- `electric_chiller_base_load_series_kw` # Hourly total base load drawn from chiller [kW-electric]
- `annual_electric_chiller_base_load_kwh` # Annual total base load drawn from chiller [kWh-electric]

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""
function add_cooling_load_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    # Adds the `ElectricLoad` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()

    load_series_kw = p.s.cooling_load.loads_kw_thermal
    r["load_series_ton"] = load_series_kw/ KWH_THERMAL_PER_TONHOUR

    r["electric_chiller_base_load_series_kw"] = load_series_kw ./ p.s.cooling_load.existing_chiller_cop

    r["annual_calculated_tonhour"] = round(
        sum(r["load_series_ton"]) * p.hours_per_time_step, digits=2
    )
    
    r["annual_electric_chiller_base_load_kwh"] = round(
        sum(r["electric_chiller_base_load_series_kw"]) * p.hours_per_time_step, digits=2
    )

    d["CoolingLoad"] = r
    nothing
end

"""
`HeatingLoad` results keys:
- `dhw_thermal_load_series_mmbtu_per_hour` vector of site thermal domestic hot water load in every time step 
- `space_heating_thermal_load_series_mmbtu_per_hour` vector of site thermal space heating load in every time step
- `process_heat_thermal_load_series_mmbtu_per_hour` vector of site thermal process heat load in every time step
- `total_heating_thermal_load_series_mmbtu_per_hour` vector of sum thermal heating load in every time step
- `dhw_boiler_fuel_load_series_mmbtu_per_hour` vector of site fuel domestic hot water load in every time step
- `space_heating_boiler_fuel_load_series_mmbtu_per_hour` vector of site fuel space heating load in every time step
- `process_heat_boiler_fuel_load_series_mmbtu_per_hour` vector of site fuel process heat load in every time step
- `total_heating_thermal_load_series_mmbtu_per_hour` vector of sum fuel heating load in every time step
- `annual_calculated_dhw_thermal_load_mmbtu` sum of the `dhw_thermal_load_series_mmbtu_per_hour`
- `annual_calculated_space_heating_thermal_load_mmbtu` sum of the `space_heating_thermal_load_series_mmbtu_per_hour`
- `annual_calculated_process_heat_thermal_load_mmbtu` sum of the `process_heat_thermal_load_series_mmbtu_per_hour`
- `annual_calculated_total_heating_thermal_load_mmbtu` sum of the `total_heating_thermal_load_series_mmbtu_per_hour`
- `annual_calculated_dhw_boiler_fuel_load_mmbtu` sum of the `dhw_boiler_fuel_load_series_mmbtu_per_hour`
- `annual_calculated_space_heating_boiler_fuel_load_mmbtu` sum of the `space_heating_boiler_fuel_load_series_mmbtu_per_hour`
- `annual_calculated_process_heat_boiler_fuel_load_mmbtu` sum of the `process_heat_boiler_fuel_load_series_mmbtu_per_hour`
- `annual_calculated_total_heating_boiler_fuel_load_mmbtu` sum of the `total_heating_boiler_fuel_load_series_mmbtu_per_hour`
"""
function add_heating_load_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    # Adds the `ElectricLoad` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    r =   Dict{String, Any}()

    dhw_load_series_kw           =   p.s.dhw_load.loads_kw
    space_heating_load_series_kw =   p.s.space_heating_load.loads_kw
    process_heat_load_series_kw  =   p.s.process_heat_load.loads_kw

    existing_boiler_efficiency =   isnothing(p.s.existing_boiler) ? EXISTING_BOILER_EFFICIENCY : p.s.existing_boiler.efficiency
    r["dhw_thermal_load_series_mmbtu_per_hour"]           =   dhw_load_series_kw ./ KWH_PER_MMBTU
    r["space_heating_thermal_load_series_mmbtu_per_hour"] =   space_heating_load_series_kw ./ KWH_PER_MMBTU
    r["process_heat_thermal_load_series_mmbtu_per_hour"]  =   process_heat_load_series_kw ./ KWH_PER_MMBTU
    r["total_heating_thermal_load_series_mmbtu_per_hour"] =   r["dhw_thermal_load_series_mmbtu_per_hour"] .+ r["space_heating_thermal_load_series_mmbtu_per_hour"] .+ r["process_heat_thermal_load_series_mmbtu_per_hour"]

    r["dhw_boiler_fuel_load_series_mmbtu_per_hour"]           =   dhw_load_series_kw ./ KWH_PER_MMBTU ./ existing_boiler_efficiency
    r["space_heating_boiler_fuel_load_series_mmbtu_per_hour"] =   space_heating_load_series_kw ./ KWH_PER_MMBTU ./ existing_boiler_efficiency
    r["process_heat_boiler_fuel_load_series_mmbtu_per_hour"]  =   process_heat_load_series_kw ./ KWH_PER_MMBTU ./ existing_boiler_efficiency
    r["total_heating_boiler_fuel_load_series_mmbtu_per_hour"] =   r["dhw_boiler_fuel_load_series_mmbtu_per_hour"] .+ r["space_heating_boiler_fuel_load_series_mmbtu_per_hour"] .+ r["process_heat_boiler_fuel_load_series_mmbtu_per_hour"]

    r["annual_calculated_dhw_thermal_load_mmbtu"] = round(
        sum(r["dhw_thermal_load_series_mmbtu_per_hour"]) * p.hours_per_time_step, digits =   2
    )
    r["annual_calculated_space_heating_thermal_load_mmbtu"] = round(
        sum(r["space_heating_thermal_load_series_mmbtu_per_hour"]) * p.hours_per_time_step, digits =   2
    )
    r["annual_calculated_process_heat_thermal_load_mmbtu"] = round(
        sum(r["process_heat_thermal_load_series_mmbtu_per_hour"]) * p.hours_per_time_step, digits =   2
    )
    r["annual_calculated_total_heating_thermal_load_mmbtu"] =   r["annual_calculated_dhw_thermal_load_mmbtu"] + r["annual_calculated_space_heating_thermal_load_mmbtu"] + r["annual_calculated_process_heat_thermal_load_mmbtu"]
    
    r["annual_calculated_dhw_boiler_fuel_load_mmbtu"]           =   r["annual_calculated_dhw_thermal_load_mmbtu"] / existing_boiler_efficiency
    r["annual_calculated_space_heating_boiler_fuel_load_mmbtu"] =   r["annual_calculated_space_heating_thermal_load_mmbtu"] / existing_boiler_efficiency
    r["annual_calculated_process_heat_boiler_fuel_load_mmbtu"]  =   r["annual_calculated_process_heat_thermal_load_mmbtu"] / existing_boiler_efficiency
    r["annual_calculated_total_heating_boiler_fuel_load_mmbtu"] =   r["annual_calculated_total_heating_thermal_load_mmbtu"] / existing_boiler_efficiency

    r["annual_total_unaddressable_heating_load_mmbtu"] = (p.s.dhw_load.unaddressable_annual_fuel_mmbtu + 
                                                    p.s.space_heating_load.unaddressable_annual_fuel_mmbtu + 
                                                    p.s.process_heat_load.unaddressable_annual_fuel_mmbtu)

    r["annual_emissions_from_unaddressable_heating_load_tonnes_CO2"] = r["annual_total_unaddressable_heating_load_mmbtu"] * p.s.existing_boiler.emissions_factor_lb_CO2_per_mmbtu * TONNE_PER_LB

    d["HeatingLoad"] =   r
    nothing
end
