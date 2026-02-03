# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`SteamTurbine` results keys:
- `size_kw` Power capacity size [kW]
- `annual_thermal_consumption_mmbtu` Thermal (steam) consumption [MMBtu]
- `annual_electric_production_kwh` Electric energy produced in a year [kWh]
- `annual_thermal_production_mmbtu` Thermal energy produced in a year [MMBtu]
- `thermal_consumption_series_mmbtu_per_hour` Thermal (steam) energy consumption series [MMBtu/hr]
- `electric_production_series_kw` Electric power production series [kW]
- `electric_to_grid_series_kw` Electric power exported to grid series [kW]
- `electric_to_storage_series_kw` Electric power to charge the battery series [kW]
- `electric_to_load_series_kw` Electric power to serve load series [kW]
- `thermal_to_storage_series_mmbtu_per_hour` Thermal production to charge the HotThermalStorage series [MMBtu/hr]
- `thermal_to_load_series_mmbtu_per_hour` Thermal production to serve the heating load SERVICES [MMBtu/hr]

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""
function add_steam_turbine_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	# Adds the `SteamTurbine` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
	# Note: the node number is an empty string if evaluating a single `Site`.	

    r = Dict{String, Any}()

	r["size_kw"] = round(value(sum(m[Symbol("dvSize"*_n)][t] for t in p.techs.steam_turbine)), digits=3)
    @expression(m, Year1SteamTurbineThermalConsumptionKWH,
		p.hours_per_time_step * sum(m[Symbol("dvThermalToSteamTurbine"*_n)][tst,q,ts] for tst in p.techs.can_supply_steam_turbine, q in p.heating_loads, ts in p.time_steps))
    r["annual_thermal_consumption_mmbtu"] = round(value(Year1SteamTurbineThermalConsumptionKWH) / KWH_PER_MMBTU, digits=5)
    @expression(m, Year1SteamTurbineElecProd,
		p.hours_per_time_step * sum(m[Symbol("dvRatedProduction"*_n)][t,ts] * p.production_factor[t, ts]
			for t in p.techs.steam_turbine, ts in p.time_steps))
	r["annual_electric_production_kwh"] = round(value(Year1SteamTurbineElecProd), digits=3)
	@expression(m, Year1SteamTurbineThermalProdKWH,
		p.hours_per_time_step * sum(m[Symbol("dvHeatingProduction"*_n)][t,q,ts] for q in p.heating_loads, t in p.techs.steam_turbine, ts in p.time_steps))
	r["annual_thermal_production_mmbtu"] = round(value(Year1SteamTurbineThermalProdKWH) / KWH_PER_MMBTU, digits=5)
    @expression(m, SteamTurbineThermalConsumptionKW[ts in p.time_steps],
		sum(m[Symbol("dvThermalToSteamTurbine"*_n)][tst,q,ts] for tst in p.techs.can_supply_steam_turbine, q in p.heating_loads))
    r["thermal_consumption_series_mmbtu_per_hour"] = round.(value.(SteamTurbineThermalConsumptionKW) ./ KWH_PER_MMBTU, digits=5)
	@expression(m, SteamTurbineElecProdTotal[ts in p.time_steps],
		sum(m[Symbol("dvRatedProduction"*_n)][t,ts] * p.production_factor[t, ts] for t in p.techs.steam_turbine))
	r["electric_production_series_kw"] = round.(value.(SteamTurbineElecProdTotal), digits=3)
    if !isempty(p.s.electric_tariff.export_bins)
        @expression(m, SteamTurbinetoGrid[ts in p.time_steps],
                sum(m[Symbol("dvProductionToGrid"*_n)][t, u, ts] for t in p.techs.steam_turbine, u in p.export_bins_by_tech[t]))	
    else
        SteamTurbinetoGrid = zeros(length(p.time_steps))
    end
	r["electric_to_grid_series_kw"] = round.(value.(SteamTurbinetoGrid), digits=3)
	if !isempty(p.s.storage.types.elec)
		@expression(m, SteamTurbinetoBatt[ts in p.time_steps],
			sum(m[Symbol("dvProductionToStorage"*_n)]["ElectricStorage",t,ts] for t in p.techs.steam_turbine))
	else
		SteamTurbinetoBatt = zeros(length(p.time_steps))
	end
	r["electric_to_storage_series_kw"] = round.(value.(SteamTurbinetoBatt), digits=3)
	@expression(m, SteamTurbinetoLoad[ts in p.time_steps],
		sum(m[Symbol("dvRatedProduction"*_n)][t, ts] * p.production_factor[t, ts]
			for t in p.techs.steam_turbine) - SteamTurbinetoBatt[ts] - SteamTurbinetoGrid[ts])
	r["electric_to_load_series_kw"] = round.(value.(SteamTurbinetoLoad), digits=3)
    if !isempty(p.s.storage.types.hot)
		if "HotThermalStorage" in p.s.storage.types.hot
			@expression(m, SteamTurbinetoHotTESKW[ts in p.time_steps],
				sum(m[Symbol("dvHeatToStorage"*_n)]["HotThermalStorage",t,q,ts] for q in p.heating_loads, t in p.techs.steam_turbine))
			@expression(m, SteamTurbineToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps],
				sum(m[Symbol("dvHeatToStorage"*_n)]["HotThermalStorage",t,q,ts] for t in p.techs.steam_turbine))
		else
			@expression(m, SteamTurbinetoHotTESKW[ts in p.time_steps], 0.0)
			@expression(m, SteamTurbineToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 0.0)
		end
		if "HighTempThermalStorage" in p.s.storage.types.hot
			@expression(m, SteamTurbineToHotSensibleTESKW[ts in p.time_steps],
				sum(m[Symbol("dvHeatToStorage"*_n)]["HighTempThermalStorage",t,q,ts] for t in p.techs.steam_turbine, q in p.heating_loads)
				)
		else
			@expression(m, SteamTurbineToHotSensibleTESKW[ts in p.time_steps], 0.0)
		end
	else
		SteamTurbinetoHotTESKW = zeros(length(p.time_steps))
		@expression(m, SteamTurbineToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 0.0)
		@expression(m, SteamTurbineToHotSensibleTESKW[ts in p.time_steps], 0.0)
	end
	r["thermal_to_storage_series_mmbtu_per_hour"] = round.(value.(SteamTurbinetoHotTESKW) ./ KWH_PER_MMBTU, digits=5)
	r["thermal_to_high_temp_thermal_storage_series_mmbtu_per_hour"] = round.(value.(m[:SteamTurbineToHotSensibleTESKW]) ./ KWH_PER_MMBTU, digits=5)
	
	@expression(m, SteamTurbineThermalToLoadKW[ts in p.time_steps],
		sum(m[Symbol("dvHeatingProduction"*_n)][t,q,ts] for t in p.techs.steam_turbine, q in p.heating_loads) - SteamTurbinetoHotTESKW[ts])
	r["thermal_to_load_series_mmbtu_per_hour"] = round.(value.(SteamTurbineThermalToLoadKW) ./ KWH_PER_MMBTU, digits=5)
	
	if "DomesticHotWater" in p.heating_loads && p.s.steam_turbine.can_serve_dhw
        @expression(m, SteamTurbineToDHWKW[ts in p.time_steps], 
            m[Symbol("dvHeatingProduction"*_n)]["SteamTurbine","DomesticHotWater",ts] - SteamTurbineToHotTESByQualityKW["DomesticHotWater",ts] 
        )
    else
        @expression(m, SteamTurbineToDHWKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_dhw_load_series_mmbtu_per_hour"] = round.(value.(SteamTurbineToDHWKW ./ KWH_PER_MMBTU), digits=5)
    
    if "SpaceHeating" in p.heating_loads && p.s.steam_turbine.can_serve_space_heating
        @expression(m, SteamTurbineToSpaceHeatingKW[ts in p.time_steps], 
            m[Symbol("dvHeatingProduction"*_n)]["SteamTurbine","SpaceHeating",ts] - SteamTurbineToHotTESByQualityKW["SpaceHeating",ts] 
        )
    else
        @expression(m, SteamTurbineToSpaceHeatingKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_space_heating_load_series_mmbtu_per_hour"] = round.(value.(SteamTurbineToSpaceHeatingKW ./ KWH_PER_MMBTU), digits=5)
    
    if "ProcessHeat" in p.heating_loads && p.s.steam_turbine.can_serve_process_heat
        @expression(m, SteamTurbineToProcessHeatKW[ts in p.time_steps], 
            m[Symbol("dvHeatingProduction"*_n)]["SteamTurbine","ProcessHeat",ts] - SteamTurbineToHotTESByQualityKW["ProcessHeat",ts] 
        )
    else
        @expression(m, SteamTurbineToProcessHeatKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_process_heat_load_series_mmbtu_per_hour"] = round.(value.(SteamTurbineToProcessHeatKW ./ KWH_PER_MMBTU), digits=5)

	
	d["SteamTurbine"] = r
	nothing
end