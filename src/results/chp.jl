# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`CHP` results keys:
- `size_kw` Power capacity size of the CHP system [kW]
- `size_supplemental_firing_kw` Power capacity of CHP supplementary firing system [kW]
- `annual_fuel_consumption_mmbtu` Fuel consumed in a year [MMBtu]
- `annual_electric_production_kwh` Electric energy produced in a year [kWh]
- `annual_thermal_production_mmbtu` Thermal energy produced in a year (not including curtailed thermal) [MMBtu]
- `electric_production_series_kw` Electric power production time-series array [kW]
- `electric_to_grid_series_kw` Electric power exported time-series array [kW]
- `electric_to_storage_series_kw` Electric power to charge the battery storage time-series array [kW]
- `electric_to_load_series_kw` Electric power to serve the electric load time-series array [kW]
- `thermal_to_storage_series_mmbtu_per_hour` Thermal power to TES (HotThermalStorage) time-series array [MMBtu/hr]
- `thermal_curtailed_series_mmbtu_per_hour` Thermal power wasted/unused/vented time-series array [MMBtu/hr]
- `thermal_to_load_series_mmbtu_per_hour` Thermal power to serve the heating load time-series array [MMBtu/hr]
- `thermal_to_steamturbine_series_mmbtu_per_hour` Thermal (steam) power to steam turbine time-series array [MMBtu/hr]
- `year_one_fuel_cost_before_tax` Cost of fuel consumed by the CHP system in year one, before tax [\$]
- `year_one_fuel_cost_after_tax` Cost of fuel consumed by the CHP system in year one, after tax
- `lifecycle_fuel_cost_after_tax` Present value of cost of fuel consumed by the CHP system, after tax [\$]
- `year_one_standby_cost_before_tax` CHP standby charges in year one, before tax [\$]
- `year_one_standby_cost_after_tax` CHP standby charges in year one, after tax
- `lifecycle_standby_cost_after_tax` Present value of all CHP standby charges, after tax.
- `thermal_production_series_mmbtu_per_hour`  
- `initial_capital_costs` Initial capital costs of the CHP system, before incentives [\$]

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""
function add_chp_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	# Adds the `CHP` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
	# Note: the node number is an empty string if evaluating a single `Site`.
    
    # Add each CHP's results using its name as the key
    for chp_name in p.techs.chp
        r = get_chp_results_for_tech(m, p, chp_name, _n)
        d[chp_name] = r
    end
    nothing
end

function get_chp_results_for_tech(m::JuMP.AbstractModel, p::REoptInputs, chp_name::String, _n::String)
    r = Dict{String, Any}()
    
    # Find the CHP object for this name
    chp_idx = findfirst(chp -> chp.name == chp_name, p.s.chps)
    if isnothing(chp_idx)
        @warn "CHP named $chp_name not found in scenario"
        return r
    end
    chp = p.s.chps[chp_idx]
    
	r["size_kw"] = value(m[Symbol("dvSize"*_n)][chp_name])
    r["size_supplemental_firing_kw"] = value(m[Symbol("dvSupplementaryFiringSize"*_n)][chp_name])
	CHPFuelUsedKWH = sum(value(m[Symbol("dvFuelUsage"*_n)][chp_name, ts]) for ts in p.time_steps)
	r["annual_fuel_consumption_mmbtu"] = round(CHPFuelUsedKWH / KWH_PER_MMBTU, digits=3)
	Year1CHPElecProd = p.hours_per_time_step * sum(value(m[Symbol("dvRatedProduction"*_n)][chp_name,ts]) * p.production_factor[chp_name, ts]
			for ts in p.time_steps)
	r["annual_electric_production_kwh"] = round(Year1CHPElecProd, digits=3)
	
	CHPThermalProdKW = [sum(value(m[Symbol("dvHeatingProduction"*_n)][chp_name,q,ts]) - value(m[Symbol("dvProductionToWaste"*_n)][chp_name,q,ts]) for q in p.heating_loads) + 
		value(m[Symbol("dvSupplementaryThermalProduction"*_n)][chp_name,ts]) for ts in p.time_steps]

	r["thermal_production_series_mmbtu_per_hour"] = round.(CHPThermalProdKW / KWH_PER_MMBTU, digits=5)
	
	r["annual_thermal_production_mmbtu"] = round(p.hours_per_time_step * sum(r["thermal_production_series_mmbtu_per_hour"]), digits=3)

	CHPElecProdTotal = [value(m[Symbol("dvRatedProduction"*_n)][chp_name,ts]) * p.production_factor[chp_name, ts] for ts in p.time_steps]
	r["electric_production_series_kw"] = round.(CHPElecProdTotal, digits=3)
	# Electric dispatch breakdown
    if !isempty(p.s.electric_tariff.export_bins) && haskey(p.export_bins_by_tech, chp_name) && !isempty(p.export_bins_by_tech[chp_name])
        CHPtoGrid = [sum(value(m[Symbol("dvProductionToGrid"*_n)][chp_name,u,ts])
                for u in p.export_bins_by_tech[chp_name]) for ts in p.time_steps]
    else
        CHPtoGrid = zeros(length(p.time_steps))
    end
    r["electric_to_grid_series_kw"] = round.(CHPtoGrid, digits=3)
	if !isempty(p.s.storage.types.elec)
		CHPtoBatt = [value(m[Symbol("dvProductionToStorage"*_n)]["ElectricStorage",chp_name,ts]) for ts in p.time_steps]
	else
		CHPtoBatt = zeros(length(p.time_steps))
	end
	r["electric_to_storage_series_kw"] = round.(CHPtoBatt, digits=3)
	
	# Check if this specific CHP can curtail
	if chp.can_curtail
		CHPtoCurtail = [value(m[Symbol("dvCurtail"*_n)][chp_name,ts]) for ts in p.time_steps]
	else
		CHPtoCurtail = zeros(length(p.time_steps))
	end
	r["electric_curtailed_series_kw"] = round.(CHPtoCurtail, digits=3)
	
	CHPtoLoad = [value(m[Symbol("dvRatedProduction"*_n)][chp_name, ts]) * p.production_factor[chp_name, ts] * p.levelization_factor[chp_name] - CHPtoBatt[ts] - CHPtoGrid[ts] - CHPtoCurtail[ts] for ts in p.time_steps]
	r["electric_to_load_series_kw"] = round.(CHPtoLoad, digits=3)
	# Thermal dispatch breakdown
    if !isempty(p.s.storage.types.hot)
		CHPToHotTES = [sum(value(m[Symbol("dvHeatToStorage"*_n)][b, chp_name, q, ts]) for b in p.s.storage.types.hot, q in p.heating_loads) for ts in p.time_steps]
		CHPToHotTESByQuality = Dict(q => [sum(value(m[Symbol("dvHeatToStorage"*_n)][b, chp_name, q, ts]) for b in p.s.storage.types.hot) for ts in p.time_steps] for q in p.heating_loads)
	else 
		CHPToHotTES = zeros(length(p.time_steps))
		CHPToHotTESByQuality = Dict(q => zeros(length(p.time_steps)) for q in p.heating_loads)
	end
	r["thermal_to_storage_series_mmbtu_per_hour"] = round.(CHPToHotTES / KWH_PER_MMBTU, digits=5)
	CHPThermalToWasteKW = [sum(value(m[Symbol("dvProductionToWaste"*_n)][chp_name,q,ts]) for q in p.heating_loads) for ts in p.time_steps]
	CHPThermalToWasteByQualityKW = Dict(q => [value(m[Symbol("dvProductionToWaste"*_n)][chp_name,q,ts]) for ts in p.time_steps] for q in p.heating_loads)
	r["thermal_curtailed_series_mmbtu_per_hour"] = round.(CHPThermalToWasteKW / KWH_PER_MMBTU, digits=5)
    if !isempty(p.techs.steam_turbine) && chp.can_supply_steam_turbine
        CHPToSteamTurbineKW = [sum(value(m[Symbol("dvThermalToSteamTurbine"*_n)][chp_name,q,ts]) for q in p.heating_loads) for ts in p.time_steps]
		CHPToSteamTurbineByQualityKW = Dict(q => [value(m[Symbol("dvThermalToSteamTurbine"*_n)][chp_name,q,ts]) for ts in p.time_steps] for q in p.heating_loads)
	else
        CHPToSteamTurbineKW = zeros(length(p.time_steps))
		CHPToSteamTurbineByQualityKW = Dict(q => zeros(length(p.time_steps)) for q in p.heating_loads)
    end	
    r["thermal_to_steamturbine_series_mmbtu_per_hour"] = round.(CHPToSteamTurbineKW / KWH_PER_MMBTU, digits=5)
    CHPThermalToLoadKW = [sum(value(m[Symbol("dvHeatingProduction"*_n)][chp_name,q,ts]) for q in p.heating_loads) + value(m[Symbol("dvSupplementaryThermalProduction"*_n)][chp_name,ts]) - CHPToHotTES[ts] - CHPToSteamTurbineKW[ts] - CHPThermalToWasteKW[ts] for ts in p.time_steps]
    r["thermal_to_load_series_mmbtu_per_hour"] = round.(CHPThermalToLoadKW ./ KWH_PER_MMBTU, digits=5)
    
    if "DomesticHotWater" in p.heating_loads && chp.can_serve_dhw
        CHPToDHWKW = [value(m[:dvHeatingProduction][chp_name,"DomesticHotWater",ts]) - CHPToHotTESByQuality["DomesticHotWater"][ts] - CHPToSteamTurbineByQualityKW["DomesticHotWater"][ts] - CHPThermalToWasteByQualityKW["DomesticHotWater"][ts]
            for ts in p.time_steps]
    else
        CHPToDHWKW = zeros(length(p.time_steps))
    end
    r["thermal_to_dhw_load_series_mmbtu_per_hour"] = round.(CHPToDHWKW ./ KWH_PER_MMBTU, digits=5)
    
    if "SpaceHeating" in p.heating_loads && chp.can_serve_space_heating
        CHPToSpaceHeatingKW = [value(m[:dvHeatingProduction][chp_name,"SpaceHeating",ts]) - CHPToHotTESByQuality["SpaceHeating"][ts] - CHPToSteamTurbineByQualityKW["SpaceHeating"][ts] - CHPThermalToWasteByQualityKW["SpaceHeating"][ts]
            for ts in p.time_steps]
    else
        CHPToSpaceHeatingKW = zeros(length(p.time_steps))
    end
    r["thermal_to_space_heating_load_series_mmbtu_per_hour"] = round.(CHPToSpaceHeatingKW ./ KWH_PER_MMBTU, digits=5)
    
    if "ProcessHeat" in p.heating_loads && chp.can_serve_process_heat
        CHPToProcessHeatKW = [value(m[:dvHeatingProduction][chp_name,"ProcessHeat",ts]) - CHPToHotTESByQuality["ProcessHeat"][ts] - CHPToSteamTurbineByQualityKW["ProcessHeat"][ts] - CHPThermalToWasteByQualityKW["ProcessHeat"][ts]
            for ts in p.time_steps]
    else
        CHPToProcessHeatKW = zeros(length(p.time_steps))
    end
    r["thermal_to_process_heat_load_series_mmbtu_per_hour"] = round.(CHPToProcessHeatKW ./ KWH_PER_MMBTU, digits=5)

	# Calculate individual CHP fuel cost (not the total across all CHPs)
	chp_fuel_cost_lifecycle = sum(p.pwf_fuel[chp_name] * value(m[:dvFuelUsage][chp_name, ts]) * p.fuel_cost_per_kwh[chp_name][ts] for ts in p.time_steps)
	r["year_one_fuel_cost_before_tax"] = round(chp_fuel_cost_lifecycle / p.pwf_fuel[chp_name], digits=3)
	r["year_one_fuel_cost_after_tax"] = r["year_one_fuel_cost_before_tax"] * (1 - p.s.financial.offtaker_tax_rate_fraction)
	r["lifecycle_fuel_cost_after_tax"] = round(chp_fuel_cost_lifecycle * (1- p.s.financial.offtaker_tax_rate_fraction), digits=3)
	
	#Standby charges and hourly O&M
	r["year_one_standby_cost_before_tax"] = round(chp.standby_rate_per_kw_per_month * 12 * value(m[Symbol("dvSize"*_n)][chp_name]), digits=0)
	r["year_one_standby_cost_after_tax"] = r["year_one_standby_cost_before_tax"] * (1 - p.s.financial.offtaker_tax_rate_fraction)
	r["lifecycle_standby_cost_after_tax"] = round(r["year_one_standby_cost_before_tax"] * p.pwf_e * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=0)
	
	# Calculate individual CHP capital costs
	size_kw = value(m[Symbol("dvSize"*_n)][chp_name])
	suppl_firing_size = value(m[Symbol("dvSupplementaryFiringSize"*_n)][chp_name])
	
	# Base CHP capital cost using generalized function
	capital_cost = get_tech_initial_capex(chp, size_kw)
	
	# Add supplementary firing capital cost
	capital_cost += chp.supplementary_firing_capital_cost_per_kw * suppl_firing_size
	
	r["initial_capital_costs"] = round(capital_cost, digits=2)

    return r
end


"""
    organize_multiple_chp_results(p::REoptInputs, d::Dict)

The last step in results processing: if more than one CHP was modeled then move their results from the top
level keys (that use each CHP.name) to an array of results with "CHP" as the top key in the results dict `d`.
"""
function organize_multiple_chp_results(p::REoptInputs, d::Dict)
    if length(p.techs.chp) == 1 && p.techs.chp[1] == "CHP"
        return nothing
    end
    chps = Dict[]
    for chpname in p.techs.chp
        d[chpname]["name"] = chpname  # add name to results dict to distinguish each CHP
        push!(chps, d[chpname])
        delete!(d, chpname)
    end
    d["CHP"] = chps
    nothing
end
