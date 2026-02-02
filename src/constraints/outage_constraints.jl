# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_dv_UnservedLoad_constraints(m,p)
    # Effective load balance
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:dvUnservedLoad][s, tz, ts] == p.s.electric_load.critical_loads_kw[time_step_wrap_around(tz+ts-1, time_steps_per_hour=p.s.settings.time_steps_per_hour)]
        - sum(  m[:dvMGRatedProduction][t, s, tz, ts] * (p.production_factor[t, time_step_wrap_around(tz+ts-1, time_steps_per_hour=p.s.settings.time_steps_per_hour)] + p.unavailability[t][time_step_wrap_around(tz+ts-1, time_steps_per_hour=p.s.settings.time_steps_per_hour)]) * p.levelization_factor[t]
              - m[:dvMGProductionToStorage][t, s, tz, ts] - m[:dvMGCurtail][t, s, tz, ts]
            for t in p.techs.elec
        )
        - m[:dvMGDischargeFromStorage][s, tz, ts]
    )
end

# constrain minimum hours that critical load is met
function add_min_hours_crit_ld_met_constraint(m,p)
    if p.s.site.min_resil_time_steps <= length(p.s.electric_utility.outage_time_steps)
        @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in 1:p.s.site.min_resil_time_steps],
            m[:dvUnservedLoad][s, tz, ts] <= 0
        )
    end
end

function add_outage_cost_constraints(m,p)
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMaxOutageCost][s] >= p.pwf_e * sum(p.value_of_lost_load_per_kwh[time_step_wrap_around(tz+ts-1, time_steps_per_hour=p.s.settings.time_steps_per_hour)] * m[:dvUnservedLoad][s, tz, ts] for ts in 1:p.s.electric_utility.outage_durations[s])
    )

    @expression(m, ExpectedOutageCost,
        sum(m[:dvMaxOutageCost][s] * p.s.electric_utility.outage_probabilities[s] for s in p.s.electric_utility.scenarios)
    )
   
    if !isempty(setdiff(p.techs.elec, p.techs.segmented))
        if solver_is_compatible_with_indicator_constraints(p.s.settings.solver_name)
            @constraint(m, [t in setdiff(p.techs.elec, p.techs.segmented)],
                m[:binMGTechUsed][t] => {m[:dvMGTechUpgradeCost][t] >= p.s.financial.microgrid_upgrade_cost_fraction * p.third_party_factor *
                                        p.cap_cost_slope[t] * m[:dvMGsize][t]}
            )
        else
            @constraint(m, [t in setdiff(p.techs.elec, p.techs.segmented)],
                m[:dvMGTechUpgradeCost][t] >= p.s.financial.microgrid_upgrade_cost_fraction * p.third_party_factor *
                                        p.cap_cost_slope[t] * m[:dvMGsize][t] - (
                                            p.s.financial.microgrid_upgrade_cost_fraction * p.third_party_factor *
                                            p.cap_cost_slope[t] * p.max_sizes[t] * (1-m[:binMGTechUsed][t])
                                        )  #TODO: check max_sizes for quality of lower bounds (can we make a better big-M?)
            )
            @constraint(m, [t in setdiff(p.techs.elec, p.techs.segmented)],
                m[:dvMGTechUpgradeCost][t] >= 0.0
            )
        end
    end

    if !isempty(intersect(p.techs.segmented, p.techs.elec))
        @warn "Adding binary variable(s) to model cost curves in stochastic outages"
        if solver_is_compatible_with_indicator_constraints(p.s.settings.solver_name)
            @constraint(m, [t in intersect(p.techs.segmented, p.techs.elec)],  # cannot have this for statement in sum( ... for t in ...) ???
                m[:binMGTechUsed][t] => {m[:dvMGTechUpgradeCost][t] >= p.s.financial.microgrid_upgrade_cost_fraction * p.third_party_factor * 
                    sum(p.cap_cost_slope[t][s] * m[Symbol("dvSegmentSystemSize"*t)][s] + 
                        p.seg_yint[t][s] * m[Symbol("binSegment"*t)][s] for s in 1:p.n_segs_by_tech[t])}
                )
        else
            @constraint(m, [t in intersect(p.techs.segmented, p.techs.elec)],  
                m[:dvMGTechUpgradeCost][t] >= p.s.financial.microgrid_upgrade_cost_fraction * p.third_party_factor * 
                    sum(p.cap_cost_slope[t][s] * m[Symbol("dvSegmentSystemSize"*t)][s] + 
                        p.seg_yint[t][s] * m[Symbol("binSegment"*t)][s] for s in 1:p.n_segs_by_tech[t]) -
                        (maximum(p.cap_cost_slope[t][s] for s in 1:p.n_segs_by_tech[t]) * p.max_sizes[t] + maximum(p.seg_yint[t][s] for s in 1:p.n_segs_by_tech[t]))*(1-m[:binMGTechUsed][t])
                )
            @constraint(m, [t in intersect(p.techs.segmented, p.techs.elec)], m[:dvMGTechUpgradeCost][t] >= 0.0)
        end
    end

    if solver_is_compatible_with_indicator_constraints(p.s.settings.solver_name)
        @constraint(m,
            m[:binMGStorageUsed] => {m[:dvMGStorageUpgradeCost] >= p.s.financial.microgrid_upgrade_cost_fraction * m[:TotalStorageCapCosts]}
        )
    else
        @constraint(m,
            m[:dvMGStorageUpgradeCost] >= p.s.financial.microgrid_upgrade_cost_fraction * m[:TotalStorageCapCosts] - (
                p.s.financial.microgrid_upgrade_cost_fraction * p.third_party_factor * (
                    sum( p.s.storage.attr[b].net_present_cost_per_kw * p.s.storage.attr[b].max_kw for b in p.s.storage.types.elec) + 
                    sum( p.s.storage.attr[b].net_present_cost_per_kwh * p.s.storage.attr[b].max_kwh for b in p.s.storage.types.all ) +
                    sum(p.s.storage.attr[b].net_present_cost_cost_constant for b in p.s.storage.types.elec)
                ) * (1-m[:binMGStorageUsed])  # Big-M is capital cost of battery with max size kw and kwh
            )
        )
        @constraint(m, m[:dvMGStorageUpgradeCost] >= 0.0)
    end
    
    @expression(m, mgTotalTechUpgradeCost,
        sum( m[:dvMGTechUpgradeCost][t] for t in p.techs.elec )
    )
end


function add_MG_size_constraints(m,p)
    @constraint(m, [t in p.techs.elec],
         m[:dvMGsize][t] >= m[:binMGTechUsed][t]  # 1 kW min size to prevent binaryMGTechUsed = 1 with zero cost
    )

    @constraint(m, [b in p.s.storage.types.all],
        m[:dvStoragePower][b] >= m[:binMGStorageUsed] # 1 kW min size to prevent binaryMGStorageUsed = 1 with zero cost
    )
    
    if p.s.site.mg_tech_sizes_equal_grid_sizes
        @constraint(m, [t in p.techs.elec],
            m[:dvMGsize][t] == m[:dvSize][t]
        )
    else
        @constraint(m, [t in p.techs.elec],
            m[:dvMGsize][t] <= m[:dvSize][t]
        )
    end
end


function add_MG_production_constraints(m,p)

	# Electrical production sent to storage or export must be less than technology's rated production
	@constraint(m, [t in p.techs.elec, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
		m[:dvMGProductionToStorage][t, s, tz, ts] + m[:dvMGCurtail][t, s, tz, ts] <=
		(p.production_factor[t, time_step_wrap_around(tz+ts-1, time_steps_per_hour=p.s.settings.time_steps_per_hour)] + p.unavailability[t][time_step_wrap_around(tz+ts-1, time_steps_per_hour=p.s.settings.time_steps_per_hour)]) * p.levelization_factor[t] * m[:dvMGRatedProduction][t, s, tz, ts]
    )

    @constraint(m, [t in p.techs.elec, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps], 
        m[:dvMGRatedProduction][t, s, tz, ts] >= 0
    )
    
    @constraint(m, [t in p.techs.elec, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:dvMGRatedProduction][t, s, tz, ts] <= m[:dvMGsize][t]
    )
end


function add_MG_Gen_fuel_burn_constraints(m,p)
	fuel_slope_gal_per_kwhe, fuel_intercept_gal_per_hr = fuel_slope_and_intercept(
		electric_efficiency_full_load=p.s.generator.electric_efficiency_full_load, 
		electric_efficiency_half_load=p.s.generator.electric_efficiency_half_load,
        fuel_higher_heating_value_kwh_per_unit=p.s.generator.fuel_higher_heating_value_kwh_per_gal
	)
    # Define dvMGFuelUsed by summing over outage time_steps.
    @constraint(m, [t in p.techs.gen, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGFuelUsed][t, s, tz] == fuel_slope_gal_per_kwhe * p.hours_per_time_step * p.levelization_factor[t] *
        sum( (p.production_factor[t, time_step_wrap_around(tz+ts-1, time_steps_per_hour=p.s.settings.time_steps_per_hour)] + p.unavailability[t][time_step_wrap_around(tz+ts-1, time_steps_per_hour=p.s.settings.time_steps_per_hour)]) * m[:dvMGRatedProduction][t, s, tz, ts] for ts in 1:p.s.electric_utility.outage_durations[s])
        + fuel_intercept_gal_per_hr * p.hours_per_time_step * 
        sum( m[:binMGGenIsOnInTS][s, tz, ts] for ts in 1:p.s.electric_utility.outage_durations[s])
    )

    # For each outage the fuel used is <= fuel_avail_gal
    @constraint(m, [t in p.techs.gen, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGFuelUsed][t, s, tz] <= p.s.generator.fuel_avail_gal
    )
    
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGGenMaxFuelUsage][s] >= sum( m[:dvMGFuelUsed][t, s, tz] for t in p.techs.gen )
    )
    
    @expression(m, ExpectedMGGenFuelUsed, 
        sum( m[:dvMGGenMaxFuelUsage][s] * p.s.electric_utility.outage_probabilities[s] for s in p.s.electric_utility.scenarios )
    )

    # fuel cost = gallons * $/gal for each tech, outage
    @expression(m, MGFuelCost[t in p.techs.gen, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGFuelUsed][t, s, tz] * p.s.generator.fuel_cost_per_gallon # why not: * p.pwf_fuel[t] ?
    )
    
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGGenMaxFuelCost][s] >= sum( MGFuelCost[t, s, tz] for t in p.techs.gen )
    )
    
    @expression(m, ExpectedMGGenFuelCost,
        sum( m[:dvMGGenMaxFuelCost][s] * p.s.electric_utility.outage_probabilities[s] for s in p.s.electric_utility.scenarios )
    )

    m[:ExpectedMGFuelCost] += ExpectedMGGenFuelCost
end

function add_MG_CHP_fuel_burn_constraints(m, p; _n="")
    # Fuel burn slope and intercept
    fuel_burn_slope, fuel_burn_intercept = fuel_slope_and_intercept(; 
        electric_efficiency_full_load = p.s.chp.electric_efficiency_full_load, 
        electric_efficiency_half_load = p.s.chp.electric_efficiency_half_load, 
        fuel_higher_heating_value_kwh_per_unit=1
    )
  
    # Conditionally add dvFuelBurnYIntercept if coefficient p.FuelBurnYIntRate is greater than ~zero
    if abs(fuel_burn_intercept) > 1.0E-7
        #Constraint (1c1): Total Fuel burn for CHP **with** y-intercept fuel burn and supplementary firing
        @constraint(m, MGCHPFuelBurnCon[t in p.techs.chp, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
            m[Symbol("dvMGFuelUsed"*_n)][t,s,tz]  == p.hours_per_time_step * (
                m[Symbol("dvMGCHPFuelBurnYIntercept"*_n)][s,tz] +
                sum(fuel_burn_slope * m[Symbol("dvMGRatedProduction"*_n)][t,s,tz,ts]
                    for ts in 1:p.s.electric_utility.outage_durations[s]))
        )

        #Constraint (1d): Y-intercept fuel burn for CHP across the scenario outage time steps
        @constraint(m, MGCHPFuelBurnYIntCon[t in p.techs.chp, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
            m[Symbol("binMGCHPIsOnInTS"*_n)][s,tz,ts] => 
                {m[Symbol("dvMGCHPFuelBurnYIntercept"*_n)][s,tz] >= sum(fuel_burn_intercept * m[Symbol("dvMGsize"*_n)][t] 
                    for _ in 1:p.s.electric_utility.outage_durations[s])}
        )
    else
        #Constraint (1c2): Total Fuel burn for CHP **without** y-intercept fuel burn
        @constraint(m, MGCHPFuelBurnConLinear[t in p.techs.chp, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
            m[Symbol("dvMGFuelUsed"*_n)][t,s,tz]  == p.hours_per_time_step *
                sum(fuel_burn_slope * m[Symbol("dvMGRatedProduction"*_n)][t,s,tz,ts]
                for ts in 1:p.s.electric_utility.outage_durations[s])
        )
    end 
    
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGCHPMaxFuelUsage][s] >= sum( m[:dvMGFuelUsed][t, s, tz] for t in p.techs.chp )
    )
    
    @expression(m, ExpectedMGCHPFuelUsed, 
        sum( m[:dvMGCHPMaxFuelUsage][s] * p.s.electric_utility.outage_probabilities[s] for s in p.s.electric_utility.scenarios )
    )

    # fuel cost = kWh * $/kWh
    @expression(m, MGCHPFuelCost[t in p.techs.chp, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGFuelUsed][t, s, tz] * p.fuel_cost_per_kwh[t][tz] # why not: * p.pwf_fuel[t] ?
    )
    
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGCHPMaxFuelCost][s] >= sum( MGCHPFuelCost[t, s, tz] for t in p.techs.chp )
    )
    
    @expression(m, ExpectedMGCHPFuelCost,
        sum( m[:dvMGCHPMaxFuelCost][s] * p.s.electric_utility.outage_probabilities[s] for s in p.s.electric_utility.scenarios )
    )

    m[:ExpectedMGFuelCost] += ExpectedMGCHPFuelCost
end

function add_binMGGenIsOnInTS_constraints(m,p)
    # The following 2 constraints define binMGGenIsOnInTS to be the binary corollary to dvMGRatedProd for generator,
    # i.e. binMGGenIsOnInTS = 1 for dvMGRatedProd > min_turn_down_fraction * dvMGsize, and binMGGenIsOnInTS = 0 for dvMGRatedProd = 0
    if solver_is_compatible_with_indicator_constraints(p.s.settings.solver_name)
        @constraint(m, [t in p.techs.gen, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            !m[:binMGGenIsOnInTS][s, tz, ts] => { m[:dvMGRatedProduction][t, s, tz, ts] <= 0 }
        )
        @constraint(m, [t in p.techs.gen, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            m[:binMGGenIsOnInTS][s, tz, ts] => { 
                m[:dvMGRatedProduction][t, s, tz, ts] >= p.s.generator.min_turn_down_fraction * m[:dvMGsize][t]
            }
        )
    else
        @constraint(m, [t in p.techs.gen, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            m[:dvMGRatedProduction][t, s, tz, ts] <= p.max_sizes[t] *  m[:binMGGenIsOnInTS][s, tz, ts]
        )
        @constraint(m, [t in p.techs.gen, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            m[:dvMGRatedProduction][t, s, tz, ts] >= p.s.generator.min_turn_down_fraction * m[:dvMGsize][t] - p.max_sizes[t] * (1-m[:binMGGenIsOnInTS][s, tz, ts])
        )
    end
    @constraint(m, [t in p.techs.gen, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:binMGTechUsed][t] >= m[:binMGGenIsOnInTS][s, tz, ts]
    )
    # TODO? make binMGGenIsOnInTS indexed on p.techs.gen
end

function add_binMGCHPIsOnInTS_constraints(m, p; _n="")
    # The following 2 constraints define binMGCHPIsOnInTS to be the binary corollary to dvMGRatedProd for CHP,
    # i.e. binMGCHPIsOnInTS = 1 for dvMGRatedProd > min_turn_down_fraction * dvMGsize, and binMGCHPIsOnInTS = 0 for dvMGRatedProd = 0
    if solver_is_compatible_with_indicator_constraints(p.s.settings.solver_name)
        @constraint(m, [t in p.techs.chp, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            !m[:binMGCHPIsOnInTS][s, tz, ts] => { m[:dvMGRatedProduction][t, s, tz, ts] <= 0 }
        )
    else
        @constraint(m, [t in p.techs.chp, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            m[:dvMGRatedProduction][t, s, tz, ts] <= p.max_sizes[t] * m[:binMGCHPIsOnInTS][s, tz, ts] 
        )
    end
    @constraint(m, [t in p.techs.chp, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:binMGTechUsed][t] >= m[:binMGCHPIsOnInTS][s, tz, ts]
    )
    # TODO? make binMGCHPIsOnInTS indexed on p.techs.chp    
end

function add_MG_storage_dispatch_constraints(m,p)
    # initial SOC at start of each outage equals the grid-optimal SOC
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps],
        m[:dvMGStoredEnergy][s, tz, 0] <= m[:dvStoredEnergy]["ElectricStorage", tz]
    )
    
    # state of charge
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:dvMGStoredEnergy][s, tz, ts] == m[:dvMGStoredEnergy][s, tz, ts-1] + p.hours_per_time_step * (
            p.s.storage.attr["ElectricStorage"].charge_efficiency * sum(m[:dvMGProductionToStorage][t, s, tz, ts] for t in p.techs.elec)
            - m[:dvMGDischargeFromStorage][s, tz, ts] / p.s.storage.attr["ElectricStorage"].discharge_efficiency
        )
    )

	# Prevent simultaneous charge and discharge by limitting charging alone to not make the SOC exceed 100%
    @constraint(m, [ts in p.time_steps_without_grid],
        m[:dvStorageEnergy]["ElectricStorage"] >= m[:dvMGStoredEnergy][s, tz, ts-1] + p.hours_per_time_step * (  
            p.s.storage.attr["ElectricStorage"].charge_efficiency * sum(m[:dvMGProductionToStorage][t, s, tz, ts] for t in p.techs.elec) 
        )
    )

    # Min SOC
    if p.s.storage.attr["ElectricStorage"].soc_min_applies_during_outages
        # Minimum state of charge
        @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            m[:dvMGStoredEnergy][s, tz, ts] >=  p.s.storage.attr["ElectricStorage"].soc_min_fraction * m[:dvStorageEnergy]["ElectricStorage"]
        )
    end
    
    # Dispatch to MG electrical storage is no greater than inverter capacity
    # and can't charge the battery unless binMGStorageUsed = 1
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:dvStoragePower]["ElectricStorage"] >= sum(m[:dvMGProductionToStorage][t, s, tz, ts] for t in p.techs.elec)
    )
    
    # Dispatch from MG storage is no greater than inverter capacity
    # and can't discharge from storage unless binMGStorageUsed = 1
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:dvStoragePower]["ElectricStorage"] >= m[:dvMGDischargeFromStorage][s, tz, ts]
    )
    
    # Dispatch to and from electrical storage is no greater than power capacity
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:dvStoragePower]["ElectricStorage"] >= m[:dvMGDischargeFromStorage][s, tz, ts]
            + sum(m[:dvMGProductionToStorage][t, s, tz, ts] for t in p.techs.elec)
    )
    
    # State of charge upper bound is storage system size
    @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
        m[:dvStorageEnergy]["ElectricStorage"] >= m[:dvMGStoredEnergy][s, tz, ts]
    )
    
    if solver_is_compatible_with_indicator_constraints(p.s.settings.solver_name)
        @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            !m[:binMGStorageUsed] => { sum(m[:dvMGProductionToStorage][t, s, tz, ts] for t in p.techs.elec) <= 0 }
        )
        
        @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            !m[:binMGStorageUsed] => { m[:dvMGDischargeFromStorage][s, tz, ts] <= 0 }
        )
    else
        @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            sum(m[:dvMGProductionToStorage][t, s, tz, ts] for t in p.techs.elec) <= p.s.storage.attr["ElectricStorage"].max_kw * m[:binMGStorageUsed]
        )
        
        @constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
            m[:dvMGDischargeFromStorage][s, tz, ts] <= p.s.storage.attr["ElectricStorage"].max_kw * m[:binMGStorageUsed]
        )
    end
end


function fix_MG_storage_variables(m, p)
    fix(m[:dvMGStorageUpgradeCost], 0.0, force=true)
    fix(m[:binMGStorageUsed], 0, force=true)
    for s in p.s.electric_utility.scenarios
        for tz in p.s.electric_utility.outage_start_time_steps
            for ts in p.s.electric_utility.outage_time_steps
                fix(m[:dvMGDischargeFromStorage][s, tz, ts], 0.0, force=true)
                fix(m[:dvMGStoredEnergy][s, tz, ts], 0.0, force=true)
                for t in p.techs.elec
                    fix(m[:dvMGProductionToStorage][t, s, tz, ts], 0.0, force=true)
                end
            end
        end
    end
end


function add_cannot_have_MG_with_only_PVwind_constraints(m, p)
    dispatchable_techs = union(p.techs.gen, p.techs.chp)
    renewable_techs = setdiff(p.techs.elec, dispatchable_techs)
    # can't "turn down" renewable_techs
    if !isempty(renewable_techs)
        if solver_is_compatible_with_indicator_constraints(p.s.settings.solver_name)
            @constraint(m, [t in renewable_techs, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
                m[:binMGTechUsed][t] => { m[:dvMGRatedProduction][t, s, tz, ts] >= m[:dvMGsize][t] }
            )
            @constraint(m, [t in renewable_techs, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
                !m[:binMGTechUsed][t] => { m[:dvMGRatedProduction][t, s, tz, ts] <= 0 }
            )
        else
            @constraint(m, [t in renewable_techs, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
                m[:dvMGRatedProduction][t, s, tz, ts] >= m[:dvMGsize][t] - p.max_sizes[t] * (1-m[:binMGTechUsed][t])
            )
            @constraint(m, [t in renewable_techs, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
                m[:dvMGRatedProduction][t, s, tz, ts] <= p.max_sizes[t] * m[:binMGTechUsed][t]
            )
        end
        if !isempty(dispatchable_techs) # PV or Wind alone cannot be used for a MG
            @constraint(m, [t in renewable_techs, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
                sum(m[:binMGTechUsed][tek] for tek in dispatchable_techs) + m[:binMGStorageUsed] >= m[:binMGTechUsed][t]
            )
        else
            @constraint(m, [t in renewable_techs, s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
                m[:binMGStorageUsed] >= m[:binMGTechUsed][t]
            )
        end
    end
end
