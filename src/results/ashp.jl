# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

"""
`ASHPSpaceHeater` results keys:
- `size_ton`  # Thermal production capacity size of the ASHP [ton/hr]
- `electric_consumption_series_kw`  # Fuel consumption series [kW]
- `annual_electric_consumption_kwh`  # Fuel consumed in a year [kWh]
- `thermal_production_series_mmbtu_per_hour`  # Thermal heating energy production series [MMBtu/hr]
- `annual_thermal_production_mmbtu`  # Thermal heating energy produced in a year [MMBtu]
- `thermal_to_storage_series_mmbtu_per_hour`  # Thermal power production to TES (HotThermalStorage) series [MMBtu/hr]
- `thermal_to_load_series_mmbtu_per_hour`  # Thermal power production to serve the heating load series [MMBtu/hr]
- `thermal_to_space_heating_load_series_mmbtu_per_hour` # Thermal production to space heating load [MMBTU/hr]
- `thermal_to_storage_series_ton` # Thermal production to ColdThermalStorage
- `thermal_to_load_series_ton` # Thermal production to cooling load
- `annual_thermal_production_tonhour` Thermal cooling energy produced in a year 


!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""

function add_ashp_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    r = Dict{String, Any}()
    r["size_ton"] = round(p.s.ashp.sizing_factor * value(m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"]) / KWH_THERMAL_PER_TONHOUR, digits=3)
    @expression(m, ASHPElectricConsumptionSeries[ts in p.time_steps],
        p.hours_per_time_step * sum(m[:dvHeatingProduction]["ASHPSpaceHeater",q,ts] for q in p.heating_loads)
        / p.heating_cop["ASHPSpaceHeater"][ts]
    ) 

    @expression(m, ASHPThermalProductionSeries[ts in p.time_steps],
        sum(m[:dvHeatingProduction]["ASHPSpaceHeater",q,ts] for q in p.heating_loads)) # TODO add cooling
	r["thermal_production_series_mmbtu_per_hour"] = 
        round.(value.(ASHPThermalProductionSeries) / KWH_PER_MMBTU, digits=5)
	r["annual_thermal_production_mmbtu"] = round(sum(r["thermal_production_series_mmbtu_per_hour"]), digits=3)

	if !isempty(p.s.storage.types.hot)
        @expression(m, ASHPToHotTESKW[ts in p.time_steps],
		    sum(m[:dvHeatToStorage][b,"ASHPSpaceHeater",q,ts] for b in p.s.storage.types.hot, q in p.heating_loads)
        )
        @expression(m, ASHPToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 
            sum(m[:dvHeatToStorage][b,"ASHPSpaceHeater",q,ts] for b in p.s.storage.types.hot)
        )
    else
        @expression(m, ASHPToHotTESKW[ts in p.time_steps], 0.0)
        @expression(m, ASHPToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 0.0)
    end
	r["thermal_to_storage_series_mmbtu_per_hour"] = round.(value.(ASHPToHotTESKW) / KWH_PER_MMBTU, digits=3)
    @expression(m, ASHPToWaste[ts in p.time_steps],
        sum(m[:dvProductionToWaste]["ASHPSpaceHeater", q, ts] for q in p.heating_loads) 
    )
    @expression(m, ASHPToWasteByQualityKW[q in p.heating_loads, ts in p.time_steps], 
        m[:dvProductionToWaste]["ASHPSpaceHeater",q,ts]
    )
	@expression(m, ASHPToLoad[ts in p.time_steps],
		sum(m[:dvHeatingProduction]["ASHPSpaceHeater", q, ts] for q in p.heating_loads) - ASHPToHotTESKW[ts] - ASHPToWaste[ts]
    )
	r["thermal_to_load_series_mmbtu_per_hour"] = round.(value.(ASHPToLoad) ./ KWH_PER_MMBTU, digits=3)
    
    if "SpaceHeating" in p.heating_loads && p.s.ashp.can_serve_space_heating
        @expression(m, ASHPToSpaceHeatingKW[ts in p.time_steps], 
            m[:dvHeatingProduction]["ASHPSpaceHeater","SpaceHeating",ts] - ASHPToHotTESByQualityKW["SpaceHeating",ts] - ASHPToWasteByQualityKW["SpaceHeating",ts]
        )
    else
        @expression(m, ASHPToSpaceHeatingKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_space_heating_load_series_mmbtu_per_hour"] = round.(value.(ASHPToSpaceHeatingKW ./ KWH_PER_MMBTU), digits=5)
    
    if "ASHPSpaceHeater" in p.techs.cooling && sum(p.s.cooling_load.loads_kw_thermal) > 0.0

        @expression(m, ASHPtoColdTES[ts in p.time_steps],
            sum(m[:dvProductionToStorage][b,"ASHPSpaceHeater",ts] for b in p.s.storage.types.cold)
        )
        r["thermal_to_storage_series_ton"] = round.(value.(ASHPtoColdTES ./ KWH_THERMAL_PER_TONHOUR), digits=3)   

        @expression(m, ASHPtoColdLoad[ts in p.time_steps],
            sum(m[:dvCoolingProduction]["ASHPSpaceHeater", ts]) - ASHPtoColdTES[ts]
        )
        r["thermal_to_load_series_ton"] = round.(value.(ASHPtoColdLoad ./ KWH_THERMAL_PER_TONHOUR), digits=3)

        @expression(m, Year1ASHPColdThermalProd,
            p.hours_per_time_step * sum(m[:dvCoolingProduction]["ASHPSpaceHeater", ts] for ts in p.time_steps)
        )
        r["annual_thermal_production_tonhour"] = round(value(Year1ASHPColdThermalProd / KWH_THERMAL_PER_TONHOUR), digits=3)
        
        @expression(m, ASHPColdElectricConsumptionSeries[ts in p.time_steps], 
            p.hours_per_time_step * m[:dvCoolingProduction]["ASHPSpaceHeater",ts] / p.cooling_cop["ASHPSpaceHeater"][ts] 
        )
        r["cooling_cop"] = p.cooling_cop["ASHPSpaceHeater"]
        r["cooling_cf"] = p.cooling_cf["ASHPSpaceHeater"]
    else
        r["thermal_to_storage_series_ton"] = zeros(length(p.time_steps))
        r["thermal_to_load_series_ton"] = zeros(length(p.time_steps))
        r["annual_thermal_production_tonhour"] = 0.0
        @expression(m, ASHPColdElectricConsumptionSeries[ts in p.time_steps], 0.0)
        r["cooling_cop"] = zeros(length(p.time_steps))
        r["cooling_cf"] = zeros(length(p.time_steps))
    end
    r["electric_consumption_series_kw"] = round.(value.(ASHPElectricConsumptionSeries .+ ASHPColdElectricConsumptionSeries), digits=3)
    r["electric_consumption_for_cooling_series_kw"] = round.(value.(ASHPColdElectricConsumptionSeries), digits=3)
    r["electric_consumption_for_heating_series_kw"] = round.(value.(ASHPElectricConsumptionSeries), digits=3)
    r["annual_electric_consumption_kwh"] = p.hours_per_time_step * sum(r["electric_consumption_series_kw"])
    r["annual_electric_consumption_for_cooling_kwh"] = p.hours_per_time_step * sum(r["electric_consumption_for_cooling_series_kw"])
    r["annual_electric_consumption_for_heating_kwh"] = p.hours_per_time_step * sum(r["electric_consumption_for_heating_series_kw"])
    r["heating_cop"] = p.heating_cop["ASHPSpaceHeater"]
    r["heating_cf"] = p.heating_cf["ASHPSpaceHeater"]

    d["ASHPSpaceHeater"] = r
	nothing
end

"""
`ASHPWaterHeater` results keys:
- `size_ton`  # Thermal production capacity size of the ASHPWaterHeater [ton/hr]
- `electric_consumption_series_kw`  # Fuel consumption series [kW]
- `annual_electric_consumption_kwh`  # Fuel consumed in a year [kWh]
- `thermal_production_series_mmbtu_per_hour`  # Thermal heating energy production series [MMBtu/hr]
- `annual_thermal_production_mmbtu`  # Thermal heating energy produced in a year [MMBtu]
- `thermal_to_storage_series_mmbtu_per_hour`  # Thermal power production to TES (HotThermalStorage) series [MMBtu/hr]
- `thermal_to_load_series_mmbtu_per_hour`  # Thermal power production to serve the heating load series [MMBtu/hr]


!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""

function add_ashp_wh_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    r = Dict{String, Any}()
    r["size_ton"] = round(p.s.ashp_wh.sizing_factor * value(m[Symbol("dvSize"*_n)]["ASHPWaterHeater"]) / KWH_THERMAL_PER_TONHOUR, digits=3)
    @expression(m, ASHPWHElectricConsumptionSeries[ts in p.time_steps],
        p.hours_per_time_step * sum(m[:dvHeatingProduction][t,q,ts] / p.heating_cop[t][ts]
        for q in p.heating_loads, t in p.techs.ashp_wh) 
    ) 

    @expression(m, ASHPWHThermalProductionSeries[ts in p.time_steps],
        sum(m[:dvHeatingProduction][t,q,ts] for q in p.heating_loads, t in p.techs.ashp_wh))
	r["thermal_production_series_mmbtu_per_hour"] = 
        round.(value.(ASHPWHThermalProductionSeries) / KWH_PER_MMBTU, digits=5)
	r["annual_thermal_production_mmbtu"] = round(sum(r["thermal_production_series_mmbtu_per_hour"]), digits=3)

	if !isempty(p.s.storage.types.hot)
        @expression(m, ASHPWHToHotTESKW[ts in p.time_steps],
		    sum(m[:dvHeatToStorage][b,"ASHPWaterHeater",q,ts] for b in p.s.storage.types.hot, q in p.heating_loads)
        )
        @expression(m, ASHPWHToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 
            sum(m[:dvHeatToStorage][b,"ASHPWaterHeater",q,ts] for b in p.s.storage.types.hot)
        )
    else
        @expression(m, ASHPWHToHotTESKW[ts in p.time_steps], 0.0)
        @expression(m, ASHPWHToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 0.0)
    end
	r["thermal_to_storage_series_mmbtu_per_hour"] = round.(value.(ASHPWHToHotTESKW) / KWH_PER_MMBTU, digits=3)
    @expression(m, ASHPWHToWaste[ts in p.time_steps],
        sum(m[:dvProductionToWaste]["ASHPWaterHeater", q, ts] for q in p.heating_loads) 
    )
    @expression(m, ASHPWHToWasteByQualityKW[q in p.heating_loads, ts in p.time_steps], 
        m[:dvProductionToWaste]["ASHPWaterHeater",q,ts]
    )
    @expression(m, ASHPWHToLoad[ts in p.time_steps],
        sum(m[:dvHeatingProduction]["ASHPWaterHeater", q, ts] for q in p.heating_loads) - ASHPWHToHotTESKW[ts] - ASHPWHToWaste[ts]
    )
	r["thermal_to_load_series_mmbtu_per_hour"] = round.(value.(ASHPWHToLoad) ./ KWH_PER_MMBTU, digits=3)

    if "DomesticHotWater" in p.heating_loads && p.s.ashp_wh.can_serve_dhw
        @expression(m, ASHPWHToDHWKW[ts in p.time_steps], 
            m[:dvHeatingProduction]["ASHPWaterHeater","DomesticHotWater",ts] - ASHPWHToHotTESByQualityKW["DomesticHotWater",ts] - ASHPWHToWasteByQualityKW["DomesticHotWater",ts]
        )
    else
        @expression(m, ASHPWHToDHWKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_dhw_load_series_mmbtu_per_hour"] = round.(value.(ASHPWHToDHWKW ./ KWH_PER_MMBTU), digits=5)
    
    r["electric_consumption_series_kw"] = round.(value.(ASHPWHElectricConsumptionSeries), digits=3)
    r["annual_electric_consumption_kwh"] = p.hours_per_time_step * sum(r["electric_consumption_series_kw"])
    r["heating_cop"] = p.heating_cop["ASHPSpaceHeater"]
    r["heating_cf"] = p.heating_cf["ASHPSpaceHeater"]

    d["ASHPWaterHeater"] = r
	nothing
end