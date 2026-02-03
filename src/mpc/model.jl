# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    run_mpc(m::JuMP.AbstractModel, fp::String)

Solve the model predictive control problem using the `MPCScenario` defined in the JSON file stored at the file path `fp`.

Returns a Dict of results with keys matching those in the `MPCScenario`.
"""
function run_mpc(m::JuMP.AbstractModel, fp::String)
	s = MPCScenario(JSON.parsefile(fp))
	run_mpc(m, MPCInputs(s))
end


"""
    run_mpc(m::JuMP.AbstractModel,  d::Dict)

Solve the model predictive control problem using the `MPCScenario` defined in the dict `d`.

Returns a Dict of results with keys matching those in the `MPCScenario`.
"""
function run_mpc(m::JuMP.AbstractModel, d::Dict)
	run_mpc(m, MPCInputs(d))
end


"""
    run_mpc(m::JuMP.AbstractModel, p::MPCInputs)

Solve the model predictive control problem using the `MPCInputs`.

Returns a Dict of results with keys matching those in the `MPCScenario`.
"""
function run_mpc(m::JuMP.AbstractModel, p::MPCInputs)
    build_mpc!(m, p)

	m[:ObjectivePenalties] = 0.0

    if !(isempty(p.s.storage.types.elec)) && p.s.settings.add_soc_incentive
		m[:ObjectivePenalties] += -1 * sum(m[:dvStoredEnergy]["ElectricStorage", ts] for ts in p.time_steps) /
									   (8760. / p.hours_per_time_step)
	end

	if !(isempty(p.s.storage.types.hydrogen)) && p.s.settings.add_soc_incentive
		#TODO Need to test if using a roundtrip efficiency would be better for hydrogen SOC incentive
		# hydrogen_roundtrip_efficiency = (p.s.compressor.efficiency_kwh_per_kg * p.s.electrolyzer.efficiency_kwh_per_kg *
		# 								p.s.fuel_cell.efficiency_kwh_per_kg)
		hydrogen_roundtrip_efficiency = 1
		m[:ObjectivePenalties] += -1 * sum(
				hydrogen_roundtrip_efficiency * m[:dvStoredEnergy][b, ts-1] for b in p.s.storage.types.hydrogen, ts in p.time_steps
			) / (8760. / p.hours_per_time_step)
	end
	
	@objective(m, Min, m[:Costs] + m[:ObjectivePenalties] )

	@info "Model built. Optimizing..."
	tstart = time()
	optimize!(m)
	opt_time = round(time() - tstart, digits=3)
	if termination_status(m) == MOI.TIME_LIMIT
		status = "timed-out"
    elseif termination_status(m) == MOI.OPTIMAL
        status = "optimal"
    else
		status = "not optimal"
		@warn "MPC solved with " termination_status(m), ", returning the model."
		return m
	end
	@info "MPC solved with " termination_status(m)
	@info "Solving took $(opt_time) seconds."

	tstart = time()
	results = mpc_results(m, p)
	time_elapsed = time() - tstart
	@info "Results processing took $(round(time_elapsed, digits=3)) seconds."
	results["status"] = status
	results["solver_seconds"] = opt_time
	return results
end


"""
    build_mpc!(m::JuMP.AbstractModel, p::MPCInputs)

Add variables and constraints for model predictive control model. 
Similar to a REopt model but with any length of horizon (instead of one calendar year),
and the DER sizes must be provided.
"""
function build_mpc!(m::JuMP.AbstractModel, p::MPCInputs)
    add_variables!(m, p)

	for ts in p.time_steps_without_grid

		fix(m[:dvGridPurchase][ts], 0.0, force=true)

		for t in p.s.storage.types.elec
			fix(m[:dvGridToStorage][t, ts], 0.0, force=true)
		end

		for t in p.techs.elec, u in p.export_bins_by_tech[t]
			fix(m[:dvProductionToGrid][t, u, ts], 0.0, force=true)
		end
	end

	for b in p.s.storage.types.all
		if b in p.s.storage.types.hydrogen
			if p.s.storage.attr[b].max_kg == 0
				@constraint(m, [ts in p.time_steps], m[:dvDischargeFromStorage][b, ts] == 0)
				@constraint(m, [ts in p.time_steps], m[:dvGridToStorage][b, ts] == 0)
				@constraint(m, [t in p.techs.elec, ts in p.time_steps_with_grid],
					m[:dvProductionToStorage][b, t, ts] == 0)
			else
				add_general_storage_dispatch_constraints(m, p, b)
				add_hydrogen_storage_dispatch_constraints(m, p, b)
			end
		elseif p.s.storage.attr[b].size_kw == 0 || p.s.storage.attr[b].size_kwh == 0
			@constraint(m, [ts in p.time_steps], m[:dvStoredEnergy][b, ts] == 0)
			@constraint(m, [t in p.techs.elec, ts in p.time_steps_with_grid],
						m[:dvProductionToStorage][b, t, ts] == 0)
			@constraint(m, [ts in p.time_steps], m[:dvDischargeFromStorage][b, ts] == 0)
			if b in p.s.storage.types.elec
				@constraint(m, [ts in p.time_steps], m[:dvGridToStorage][b, ts] == 0)
			end
		else
			add_general_storage_dispatch_constraints(m, p, b)
			if b in p.s.storage.types.elec
				add_elec_storage_dispatch_constraints(m, p, b)
			elseif b in p.s.storage.types.hot
				add_hot_thermal_storage_dispatch_constraints(m, p, b)
			elseif b in p.s.storage.types.cold
				add_cold_thermal_storage_dispatch_constraints(m, p, b)
			else
				throw(@error("Invalid storage does not fall in a thermal or electrical set"))
			end
		end
	end

	if any(size_kw->size_kw > 0, (p.s.storage.attr[b].size_kw for b in p.s.storage.types.elec)) 
		add_storage_sum_grid_constraints(m, p)
	elseif any(size_kg->size_kg > 0, (p.s.storage.attr[b].size_kg for b in p.s.storage.types.hydrogen))
		add_storage_sum_grid_constraints(m, p)
	end

	add_production_constraints(m, p)

	if !isempty(p.techs.no_turndown)
		@constraint(m, [t in p.techs.no_turndown, ts in p.time_steps],
            m[:dvRatedProduction][t,ts] == m[:dvSize][t]
        )
	end  

    if !isempty(p.techs.electrolyzer)
        @constraint(m, [t in p.techs.electrolyzer, ts in p.time_steps],
			m[:dvRatedProduction][t,ts]  <= m[:dvSize][t]
        )
    end  

    if !isempty(p.techs.compressor)
        @constraint(m, [t in p.techs.compressor, ts in p.time_steps],
			m[:dvRatedProduction][t,ts]  <= m[:dvSize][t]
        )
    end
    
    if !isempty(p.techs.fuel_cell)
        @constraint(m, [t in p.techs.fuel_cell, ts in p.time_steps],
			m[:dvRatedProduction][t,ts]  <= m[:dvSize][t]
        )
    end

	add_elec_load_balance_constraints(m, p)

	if !isempty(p.techs.electric_heater)
		add_thermal_load_constraints(m, p) 
	end

	if !isempty(p.s.limits.grid_draw_limit_kw_by_time_step)
		add_grid_draw_limits(m, p)
	end

	if !isempty(p.s.electric_tariff.export_bins)
		add_export_constraints(m, p)
		if !isempty(p.s.limits.export_limit_kw_by_time_step)
			add_export_limits(m, p)
		end
	end

	if !isempty(p.s.electric_tariff.monthly_demand_rates)
		add_monthly_peak_constraint(m, p)
	end

	if !isempty(p.s.electric_tariff.tou_demand_ratchet_time_steps)
		add_tou_peak_constraint(m, p)
	end

	if !(p.s.electric_utility.allow_simultaneous_export_import) & !isempty(p.s.electric_tariff.export_bins)
		add_simultaneous_export_import_constraint(m, p)
	end
	
    m[:TotalFuelCosts] = 0.0
    m[:TotalPerUnitProdOMCosts] = 0.0

    if !isempty(p.techs.gen)
        add_gen_constraints(m, p)
		m[:TotalPerUnitProdOMCosts] += @expression(m, 
			sum(p.s.generator.om_cost_per_kwh * p.hours_per_time_step *
			m[:dvRatedProduction][t, ts] for t in p.techs.gen, ts in p.time_steps)
		)
        m[:TotalGenFuelCosts] = @expression(m,
            sum(m[:dvFuelUsage][t,ts] * p.s.generator.fuel_cost_per_gallon for t in p.techs.gen, ts in p.time_steps)
        )
        m[:TotalFuelCosts] += m[:TotalGenFuelCosts]
	end

	if !isempty(p.techs.electrolyzer)
		add_electrolyzer_constraints(m, p)
		m[:TotalPerUnitProdOMCosts] += @expression(m,
			sum(p.s.electrolyzer.om_cost_per_kwh * p.hours_per_time_step *
			m[:dvRatedProduction][t, ts] for t in p.techs.electrolyzer, ts in p.time_steps))
	else
		@constraint(m, [t in p.techs.elec, ts in p.time_steps],
				m[:dvProductionToElectrolyzer][t, ts] == 0)
		@constraint(m, [ts in p.time_steps], m[:dvGridToElectrolyzer][ts] == 0)
		@constraint(m, [b in p.s.storage.types.elec, ts in p.time_steps],
				m[:dvStorageToElectrolyzer][b, ts] == 0)
		@constraint(m, [t in p.techs.electrolyzer, ts in p.time_steps],
				m[:dvRatedProduction][t,ts] == 0)
		@constraint(m, [t in p.techs.elec, ts in p.time_steps],
				m[:dvProductionToCompressor][t, ts] == 0)
		@constraint(m, [ts in p.time_steps], m[:dvGridToCompressor][ts] == 0)
		@constraint(m, [b in p.s.storage.types.elec, ts in p.time_steps],
				m[:dvStorageToCompressor][b, ts] == 0)
		@constraint(m, [t in p.techs.compressor, ts in p.time_steps],
				m[:dvRatedProduction][t,ts] == 0)
		@constraint(m, [t in p.techs.compressor, ts in p.time_steps],
				m[:dvProductionToStorage]["HydrogenStorage",t,ts] == 0)
	end

	if !isempty(p.techs.compressor)
		if !p.s.electrolyzer.require_compression
			@constraint(m, [t in p.techs.elec, ts in p.time_steps],
					m[:dvProductionToCompressor][t, ts] == 0)
			@constraint(m, [ts in p.time_steps], m[:dvGridToCompressor][ts] == 0)
			@constraint(m, [b in p.s.storage.types.elec, ts in p.time_steps],
					m[:dvStorageToCompressor][b, ts] == 0)
		end
		add_compressor_constraints(m, p)
		m[:TotalPerUnitProdOMCosts] += m[:TotalCompressorPerUnitProdOMCosts]
	else
		@constraint(m, [t in p.techs.elec, ts in p.time_steps],
				m[:dvProductionToCompressor][t, ts] == 0)
		@constraint(m, [ts in p.time_steps], m[:dvGridToCompressor][ts] == 0)
		@constraint(m, [b in p.s.storage.types.elec, ts in p.time_steps],
				m[:dvStorageToCompressor][b, ts] == 0)
		@constraint(m, [t in p.techs.compressor, ts in p.time_steps],
				m[:dvRatedProduction][t,ts] == 0)
		@constraint(m, [t in p.techs.compressor, ts in p.time_steps],
				m[:dvProductionToStorage]["HydrogenStorage",t,ts] == 0)
	end

	if !isempty(p.techs.fuel_cell)
		add_fuel_cell_constraints(m, p)
		m[:TotalPerUnitProdOMCosts] += @expression(m,
			sum(p.s.fuel_cell.om_cost_per_kwh * p.hours_per_time_step *
            m[:dvRatedProduction][t, ts] for t in p.techs.fuel_cell, ts in p.time_steps))
	else
		@constraint(m, [t in p.techs.fuel_cell, ts in p.time_steps],
			m[:dvRatedProduction][t,ts] == 0)
	end

	add_elec_utility_expressions(m, p)
    add_previous_monthly_peak_constraint(m, p)
    add_previous_tou_peak_constraint(m, p)
	add_yr1_emissions_calcs(m,p)

    # TODO: random outages in MPC?
	if !isempty(p.s.electric_utility.outage_durations)
		add_dv_UnservedLoad_constraints(m,p)
		add_outage_cost_constraints(m,p)
		add_MG_production_constraints(m,p)
		if !isempty(p.s.storage.types.elec)	
			add_MG_elec_storage_dispatch_constraints(m,p)
		else
			fix_MG_elec_storage_variables(m,p)
		end
		add_cannot_have_MG_with_only_PVwind_constraints(m,p)
		add_MG_size_constraints(m,p)
		
		if !isempty(p.techs.gen)
			add_MG_fuel_burn_constraints(m,p)
			add_binMGGenIsOnInTS_constraints(m,p)
		else
			m[:ExpectedMGFuelUsed] = 0
			m[:ExpectedMGFuelCost] = 0
			@constraint(m, [s in p.s.electric_utility.scenarios, tz in p.s.electric_utility.outage_start_time_steps, ts in p.s.electric_utility.outage_time_steps],
				m[:binMGGenIsOnInTS][s, tz, ts] == 0
			)
		end
		
		if p.s.site.min_resil_time_steps > 0
			add_min_hours_crit_ld_met_constraint(m,p)
		end
	end

	#################################  Objective Function   ########################################
	@expression(m, Costs,

		# Variable O&M
		m[:TotalPerUnitProdOMCosts] +

		# Total Generator Fuel Costs
        m[:TotalFuelCosts] +

		# Utility Bill
		m[:TotalElecBill]
	);
	if !isempty(p.s.electric_utility.outage_durations)
		add_to_expression!(Costs, m[:ExpectedOutageCost] + m[:mgTotalTechUpgradeCost] + m[:dvMGStorageUpgradeCost] + m[:ExpectedMGFuelCost])
	end
	
	# Add climate costs
	if p.s.settings.include_climate_in_objective # if user selects to include climate in objective
		add_to_expression!(Costs, m[:EmissionsYr1_Total_LbsCO2] * p.s.financial.CO2_cost_per_tonne * TONNE_PER_LB) 
	end

    #= Note: 0.9999*MinChargeAdder in Objective b/c when TotalMinCharge > (TotalEnergyCharges + TotalDemandCharges + TotalExportBenefit + TotalFixedCharges)
		it is arbitrary where the min charge ends up (eg. could be in TotalDemandCharges or MinChargeAdder).
		0.0001*MinChargeAdder is added back into LCC when writing to results.  =#
	nothing
end


function add_variables!(m::JuMP.AbstractModel, p::MPCInputs)
    @variables m begin
		# dvSize[p.techs.all] >= 0  # System Size of Technology t [kW]
		# dvPurchaseSize[p.techs.all] >= 0  # system kW beyond existing_kw that must be purchased
		dvGridPurchase[p.time_steps] >= 0  # Power from grid dispatched to meet electrical load [kW]
		dvRatedProduction[p.techs.all, p.time_steps] >= 0  # Rated production of technology t [kW]
		dvCurtail[p.techs.all, p.time_steps] >= 0  # [kW]
		dvProductionToStorage[p.s.storage.types.all, p.techs.all, p.time_steps] >= 0  # Power from technology t used to charge storage system b [kW]
		dvDischargeFromStorage[p.s.storage.types.all, p.time_steps] >= 0 # Power discharged from storage system b [kW]
		dvProductionToElectrolyzer[p.techs.elec, p.time_steps] >= 0
		dvProductionToCompressor[p.techs.elec, p.time_steps] >= 0
		dvGridToStorage[p.s.storage.types.elec, p.time_steps] >= 0 # Electrical power delivered to storage by the grid [kW]
		dvGridToElectrolyzer[p.time_steps] >= 0
		dvGridToCompressor[p.time_steps] >= 0
		dvStoredEnergy[p.s.storage.types.all, 0:p.time_steps[end]] >= 0  # State of charge of storage system b
		dvStoragePower[p.s.storage.types.all] >= 0   # Power capacity of storage system b [kW]
		dvStorageEnergy[p.s.storage.types.all] >= 0   # Energy capacity of storage system b [kWh]
		dvStorageToElectrolyzer[p.s.storage.types.elec, p.time_steps] >= 0
		dvStorageToCompressor[p.s.storage.types.elec, p.time_steps] >= 0
		# TODO rm dvStoragePower/Energy dv's
		dvPeakDemandTOU[p.ratchets, 1:1] >= 0  # Peak electrical power demand during ratchet r [kW]
		dvPeakDemandMonth[p.months] >= 0  # Peak electrical power demand during month m [kW]
		# MinChargeAdder >= 0
		dvDischargePumpPower[p.s.storage.types.hightemp, p.time_steps] >= 0
	end
	# TODO: tiers in MPC tariffs and variables?

	# Thermal variables
	if !isempty(p.techs.heating)
        @variable(m, dvHeatingProduction[p.techs.heating, p.heating_loads, p.time_steps] >= 0)
		@variable(m, dvProductionToWaste[p.techs.heating, p.heating_loads, p.time_steps] >= 0)
		if !isempty(p.s.storage.types.hot)
			@variable(m, dvStorageChargePower[p.s.storage.types.hot] >= 0)
			@variable(m, dvStorageDischargePower[p.s.storage.types.hot] >= 0)
			@variable(m, dvHeatToStorage[p.s.storage.types.hot, p.techs.heating, p.heating_loads, p.time_steps] >= 0) # Power charged to hot storage b at quality q [kW]
			@variable(m, dvHeatFromStorage[p.s.storage.types.hot, p.heating_loads, p.time_steps] >= 0) # Power discharged from hot storage system b for load q [kW]
    	end

		# Placeholder variable for cooling
		# @variable(m, dvCoolingProduction[p.techs.cooling, p.time_steps] >= 0)
	end

	if !isempty(p.s.electric_tariff.export_bins)
		@variable(m, dvProductionToGrid[p.techs.elec, p.s.electric_tariff.export_bins, p.time_steps] >= 0)
	end

    m[:dvSize] = p.existing_sizes

	for b in p.s.storage.types.all
		if b in p.s.storage.types.elec
			fix(m[:dvStoragePower][b], p.s.storage.attr["ElectricStorage"].size_kw, force=true)
			fix(m[:dvStorageEnergy][b], p.s.storage.attr["ElectricStorage"].size_kwh, force=true)
		elseif b in p.s.storage.types.hydrogen
			fix(m[:dvStorageEnergy][b], p.s.storage.attr["HydrogenStorage"].size_kg, force=true)
		elseif b in p.s.storage.types.hot
			fix(m[:dvStorageChargePower][b], p.s.storage.attr["HighTempThermalStorage"].charge_kw, force=true)
			fix(m[:dvStorageDischargePower][b], p.s.storage.attr["HighTempThermalStorage"].discharge_kw, force=true)
			# fix(m[:dvStoragePower][b], p.s.storage.attr["HighTempThermalStorage"].size_kw, force=true)
			fix(m[:dvStorageEnergy][b], p.s.storage.attr["HighTempThermalStorage"].size_kwh, force=true)
		end
	end

	# not modeling min charges since control does not affect them
    m[:MinChargeAdder] = 0

	if !isempty(p.techs.gen)  # Problem becomes a MILP
		@warn """Adding binary variable to model gas generator. 
				 Some solvers are very slow with integer variables"""
		@variables m begin
			dvFuelUsage[p.techs.gen, p.time_steps] >= 0 # Fuel burned by technology t in each time step [kWh]
			binGenIsOnInTS[p.techs.gen, p.time_steps], Bin  # 1 If technology t is operating in time step h; 0 otherwise
		end
	end

	if !(p.s.electric_utility.allow_simultaneous_export_import)
		@warn """Adding binary variable to prevent simultaneous grid import/export. 
				 Some solvers are very slow with integer variables"""
		@variable(m, binNoGridPurchases[p.time_steps], Bin)
	end

	if !isempty(p.s.electric_utility.outage_durations) # add dvUnserved Load if there is at least one outage
		@warn """Adding binary variable to model outages. 
				 Some solvers are very slow with integer variables"""
		max_outage_duration = maximum(p.s.electric_utility.outage_durations)
		outage_time_steps = p.s.electric_utility.outage_time_steps
		tZeros = p.s.electric_utility.outage_start_time_steps
		S = p.s.electric_utility.scenarios
		# TODO: currently defining more decision variables than necessary b/c using rectangular arrays, could use dicts of decision variables instead
		@variables m begin # if there is more than one specified outage, there can be more othan one outage start time
			dvUnservedLoad[S, tZeros, outage_time_steps] >= 0 # unserved load not met by system
			dvMGProductionToStorage[union(p.s.storage.types.elec, p.s.storage.types.hydrogen), union(p.techs.elec, p.techs.electrolyzer, p.techs.compressor), S, tZeros, outage_time_steps]  >= 0 # Electricity going to the storage system during each time_step
			dvMGDischargeFromStorage[S, tZeros, outage_time_steps] >= 0 # Electricity coming from the storage system during each time_step
			dvMGRatedProduction[p.techs.all, S, tZeros, outage_time_steps]  # MG Rated Production at every time_step.  Multiply by production_factor to get actual energy
			dvMGStoredEnergy[S, tZeros, 0:max_outage_duration] >= 0 # State of charge of the MG storage system
			dvMaxOutageCost[S] >= 0 # maximum outage cost dependent on number of outage durations
			# dvMGTechUpgradeCost[p.techs.all] >= 0
			# dvMGStorageUpgradeCost >= 0
			# dvMGsize[p.techs.all] >= 0
			
			dvMGFuelUsed[p.techs.all, S, tZeros] >= 0
			dvMGMaxFuelUsage[S] >= 0
			dvMGMaxFuelCost[S] >= 0
			dvMGCurtail[p.techs.all, S, tZeros, outage_time_steps] >= 0

			# binMGStorageUsed, Bin # 1 if MG storage battery used, 0 otherwise
			# binMGTechUsed[p.techs.all], Bin # 1 if MG tech used, 0 otherwise
			binMGGenIsOnInTS[S, tZeros, outage_time_steps], Bin
		end
	end

	if p.s.settings.off_grid_flag
		@variables m begin
			# dvOpResFromBatt[p.s.storage.types.elec, p.time_steps_without_grid] >= 0 # Operating reserves provided by the electric storage [kW]
			# dvOpResFromTechs[p.techs.providing_oper_res, p.time_steps_without_grid] >= 0 # Operating reserves provided by techs [kW]
			1 >= dvOffgridLoadServedFraction[p.time_steps_without_grid] >= 0 # Critical load served in each time_step. Applied in off-grid scenarios only. [fraction]
		end
	end
end