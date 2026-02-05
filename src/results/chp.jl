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
    r = Dict{String, Any}()
	r["size_kw"] = value(sum(m[Symbol("dvSize"*_n)][t] for t in p.techs.chp))
    r["size_supplemental_firing_kw"] = value(sum(m[Symbol("dvSupplementaryFiringSize"*_n)][t] for t in p.techs.chp))
	@expression(m, CHPFuelUsedKWH, sum(m[Symbol("dvFuelUsage"*_n)][t, ts] for t in p.techs.chp, ts in p.time_steps))
	r["annual_fuel_consumption_mmbtu"] = round(value(CHPFuelUsedKWH) / KWH_PER_MMBTU, digits=3)
	@expression(m, Year1CHPElecProd,
		p.hours_per_time_step * sum(m[Symbol("dvRatedProduction"*_n)][t,ts] * p.production_factor[t, ts]
			for t in p.techs.chp, ts in p.time_steps))
	r["annual_electric_production_kwh"] = round(value(Year1CHPElecProd), digits=3)
	
	@expression(m, CHPThermalProdKW[ts in p.time_steps],
		sum(sum(m[Symbol("dvHeatingProduction"*_n)][t,q,ts] - m[Symbol("dvProductionToWaste"*_n)][t,q,ts] for q in p.heating_loads) + 
		m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts] for t in p.techs.chp))

	r["thermal_production_series_mmbtu_per_hour"] = round.(value.(CHPThermalProdKW) / KWH_PER_MMBTU, digits=5)
	
	r["annual_thermal_production_mmbtu"] = round(p.hours_per_time_step * sum(r["thermal_production_series_mmbtu_per_hour"]), digits=3)

	@expression(m, CHPElecProdTotal[ts in p.time_steps],
		sum(m[Symbol("dvRatedProduction"*_n)][t,ts] * p.production_factor[t, ts] for t in p.techs.chp))
	r["electric_production_series_kw"] = round.(value.(CHPElecProdTotal), digits=3)
	# Electric dispatch breakdown
    if !isempty(p.s.electric_tariff.export_bins)
        @expression(m, CHPtoGrid[ts in p.time_steps], sum(m[Symbol("dvProductionToGrid"*_n)][t,u,ts]
                for t in p.techs.chp, u in p.export_bins_by_tech[t]))
    else
        CHPtoGrid = zeros(length(p.time_steps))
    end
    r["electric_to_grid_series_kw"] = round.(value.(CHPtoGrid), digits=3)
	if !isempty(p.s.storage.types.elec)
		@expression(m, CHPtoBatt[ts in p.time_steps],
			sum(m[Symbol("dvProductionToStorage"*_n)]["ElectricStorage",t,ts] for t in p.techs.chp))
	else
		CHPtoBatt = zeros(length(p.time_steps))
	end
	r["electric_to_storage_series_kw"] = round.(value.(CHPtoBatt), digits=3)
	if p.s.chp.can_curtail
		@expression(m, CHPtoCurtail[ts in p.time_steps],
			sum(m[Symbol("dvCurtail"*_n)][t,ts] for t in p.techs.chp))
	else
		CHPtoCurtail = zeros(length(p.time_steps))
	end
	r["electric_curtailed_series_kw"] = round.(value.(CHPtoCurtail), digits=3)
	@expression(m, CHPtoLoad[ts in p.time_steps],
		sum(m[Symbol("dvRatedProduction"*_n)][t, ts] * p.production_factor[t, ts] * p.levelization_factor[t]
			for t in p.techs.chp) - CHPtoBatt[ts] - CHPtoGrid[ts] - CHPtoCurtail[ts])
	r["electric_to_load_series_kw"] = round.(value.(CHPtoLoad), digits=3)
	# Thermal dispatch breakdown
    if !isempty(p.s.storage.types.hot)
		@expression(m, CHPToHotTES[ts in p.time_steps],
			sum(m[Symbol("dvHeatToStorage"*_n)][b, t, q, ts] for b in p.s.storage.types.hot, t in p.techs.chp, q in p.heating_loads))
		@expression(m, CHPToHotTESByQuality[q in p.heating_loads, ts in p.time_steps],
			sum(m[Symbol("dvHeatToStorage"*_n)][b, t, q, ts] for b in p.s.storage.types.hot, t in p.techs.chp))
	else 
		@expression(m, CHPToHotTES[ts in p.time_steps], 0.0)
		@expression(m, CHPToHotTESByQuality[q in p.heating_loads, ts in p.time_steps], 0.0)
	end
	r["thermal_to_storage_series_mmbtu_per_hour"] = round.(value.(CHPToHotTES / KWH_PER_MMBTU), digits=5)
	@expression(m, CHPThermalToWasteKW[ts in p.time_steps],
		sum(m[Symbol("dvProductionToWaste"*_n)][t,q,ts] for q in p.heating_loads, t in p.techs.chp))
		@expression(m, CHPThermalToWasteByQualityKW[q in p.heating_loads, ts in p.time_steps],
		sum(m[Symbol("dvProductionToWaste"*_n)][t,q,ts] for t in p.techs.chp))	
	r["thermal_curtailed_series_mmbtu_per_hour"] = round.(value.(CHPThermalToWasteKW) / KWH_PER_MMBTU, digits=5)
    if !isempty(p.techs.steam_turbine) && p.s.chp.can_supply_steam_turbine
        @expression(m, CHPToSteamTurbineKW[ts in p.time_steps], sum(m[Symbol("dvThermalToSteamTurbine"*_n)][t,q,ts] for t in p.techs.chp, q in p.heating_loads))
		@expression(m, CHPToSteamTurbineByQualityKW[q in p.heating_loads, ts in p.time_steps], sum(m[Symbol("dvThermalToSteamTurbine"*_n)][t,q,ts] for t in p.techs.chp))
	else
        CHPToSteamTurbineKW = zeros(length(p.time_steps))
		@expression(m, CHPToSteamTurbineByQualityKW[q in p.heating_loads, ts in p.time_steps], 0.0)
    end	
    r["thermal_to_steamturbine_series_mmbtu_per_hour"] = round.(value.(CHPToSteamTurbineKW) / KWH_PER_MMBTU, digits=5)
    @expression(m, CHPThermalToLoadKW[ts in p.time_steps],
        sum(sum(m[Symbol("dvHeatingProduction"*_n)][t,q,ts] for q in p.heating_loads) + m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts]
            for t in p.techs.chp) - CHPToHotTES[ts] - CHPToSteamTurbineKW[ts] - CHPThermalToWasteKW[ts])
    r["thermal_to_load_series_mmbtu_per_hour"] = round.(value.(CHPThermalToLoadKW ./ KWH_PER_MMBTU), digits=5)

	CHPToLoadKW = @expression(m, [ts in p.time_steps],
		sum(value.(m[:dvHeatingProduction]["CHP",q,ts] for q in p.heating_loads)) - CHPToHotTES[ts] - CHPToSteamTurbineKW[ts]
    )
	r["thermal_to_load_series_mmbtu_per_hour"] = round.(value.(CHPThermalToLoadKW ./ KWH_PER_MMBTU), digits=5)
    
    if "DomesticHotWater" in p.heating_loads && p.s.chp.can_serve_dhw
        @expression(m, CHPToDHWKW[ts in p.time_steps], 
            m[:dvHeatingProduction]["CHP","DomesticHotWater",ts] - CHPToHotTESByQuality["DomesticHotWater",ts] - CHPToSteamTurbineByQualityKW["DomesticHotWater",ts] - CHPThermalToWasteByQualityKW["DomesticHotWater",ts]
        )
    else
        @expression(m, CHPToDHWKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_dhw_load_series_mmbtu_per_hour"] = round.(value.(CHPToDHWKW ./ KWH_PER_MMBTU), digits=5)
    
    if "SpaceHeating" in p.heating_loads && p.s.chp.can_serve_space_heating
        @expression(m, CHPToSpaceHeatingKW[ts in p.time_steps], 
            m[:dvHeatingProduction]["CHP","SpaceHeating",ts] - CHPToHotTESByQuality["SpaceHeating",ts] - CHPToSteamTurbineByQualityKW["SpaceHeating",ts] - CHPThermalToWasteByQualityKW["SpaceHeating",ts]
        )
    else
        @expression(m, CHPToSpaceHeatingKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_space_heating_load_series_mmbtu_per_hour"] = round.(value.(CHPToSpaceHeatingKW ./ KWH_PER_MMBTU), digits=5)
    
    if "ProcessHeat" in p.heating_loads && p.s.chp.can_serve_process_heat
        @expression(m, CHPToProcessHeatKW[ts in p.time_steps], 
            m[:dvHeatingProduction]["CHP","ProcessHeat",ts] - CHPToHotTESByQuality["ProcessHeat",ts] - CHPToSteamTurbineByQualityKW["ProcessHeat",ts] - CHPThermalToWasteByQualityKW["ProcessHeat",ts]
        )
    else
        @expression(m, CHPToProcessHeatKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_process_heat_load_series_mmbtu_per_hour"] = round.(value.(CHPToProcessHeatKW ./ KWH_PER_MMBTU), digits=5)

	r["year_one_fuel_cost_before_tax"] = round(value(m[:TotalCHPFuelCosts] / p.pwf_fuel["CHP"]), digits=3)
	r["year_one_fuel_cost_after_tax"] = r["year_one_fuel_cost_before_tax"] * (1 - p.s.financial.offtaker_tax_rate_fraction)
	r["lifecycle_fuel_cost_after_tax"] = round(value(m[:TotalCHPFuelCosts]) * (1- p.s.financial.offtaker_tax_rate_fraction), digits=3)
	#Standby charges and hourly O&M
	r["year_one_standby_cost_before_tax"] = round(value(m[Symbol("TotalCHPStandbyCharges")]) / p.pwf_e, digits=0)
	r["year_one_standby_cost_after_tax"] = r["year_one_standby_cost_before_tax"] * (1 - p.s.financial.offtaker_tax_rate_fraction)
	r["lifecycle_standby_cost_after_tax"] = round(value(m[Symbol("TotalCHPStandbyCharges")]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=0)
	r["initial_capital_costs"] = round(value(m[Symbol("CHPCapexNoIncentives")]), digits=2)

    d["CHP"] = r
    nothing
end
