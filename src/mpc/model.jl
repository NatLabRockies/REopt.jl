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

    if !p.s.settings.add_soc_incentive || !("ElectricStorage" in p.s.storage.types.elec)
		@objective(m, Min, m[:Costs])
	else # Keep SOC high
		@objective(m, Min, m[:Costs] - sum(m[:dvStoredEnergy][s, "ElectricStorage", ts] for s in 1:p.n_scenarios, ts in p.time_steps) /
									   (8760. / p.hours_per_time_step)
		)
	end

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

		for s in 1:p.n_scenarios, tier in 1:p.s.electric_tariff.n_energy_tiers
			fix(m[:dvGridPurchase][s, ts, tier], 0.0, force=true)
		end

		for s in 1:p.n_scenarios, t in p.s.storage.types.elec
			fix(m[:dvGridToStorage][s, t, ts], 0.0, force=true)
		end

		for s in 1:p.n_scenarios, t in p.techs.elec, u in p.export_bins_by_tech[t]
			fix(m[:dvProductionToGrid][s, t, u, ts], 0.0, force=true)
		end
	end

	for b in p.s.storage.types.all
		if p.s.storage.attr[b].size_kw == 0 || p.s.storage.attr[b].size_kwh == 0
			@constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps], m[:dvStoredEnergy][s, b, ts] == 0)
			@constraint(m, [s in 1:p.n_scenarios, t in p.techs.elec, ts in p.time_steps_with_grid],
						m[:dvProductionToStorage][s, b, t, ts] == 0)
			@constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps], m[:dvDischargeFromStorage][s, b, ts] == 0)
			if b in p.s.storage.types.elec
				@constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps], m[:dvGridToStorage][s, b, ts] == 0)
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

	if any(size_kw->size_kw > 0, (p.s.storage.attr[b].size_kw for b in p.s.storage.types.all))
		add_storage_sum_grid_constraints(m, p)
	end

	add_production_constraints(m, p)

	if !isempty(p.techs.no_turndown)
		@constraint(m, [s in 1:p.n_scenarios, t in p.techs.no_turndown, ts in p.time_steps],
            m[:dvRatedProduction][s, t, ts] == m[:dvSize][t]
        )
	end

	add_elec_load_balance_constraints(m, p)

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
			m[:dvRatedProduction][s, t, ts] for s in 1:p.n_scenarios, t in p.techs.gen, ts in p.time_steps)
		)
        m[:TotalGenFuelCosts] = @expression(m,
            sum(m[:dvFuelUsage][s, t, ts] * p.s.generator.fuel_cost_per_gallon for s in 1:p.n_scenarios, t in p.techs.gen, ts in p.time_steps)
        )
        m[:TotalFuelCosts] += m[:TotalGenFuelCosts]
	end

	add_elec_utility_expressions(m, p)
    add_previous_monthly_peak_constraint(m, p)
    add_previous_tou_peak_constraint(m, p)

    # TODO: random outages in MPC?
	if !isempty(p.s.electric_utility.outage_durations)
		add_dv_UnservedLoad_constraints(m,p)
		add_outage_cost_constraints(m,p)
		add_MG_production_constraints(m,p)
		if !isempty(p.s.storage.types.elec)	
			add_MG_storage_dispatch_constraints(m,p)
		else
			fix_MG_storage_variables(m,p)
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
    #= Note: 0.9999*MinChargeAdder in Objective b/c when TotalMinCharge > (TotalEnergyCharges + TotalDemandCharges + TotalExportBenefit + TotalFixedCharges)
		it is arbitrary where the min charge ends up (eg. could be in TotalDemandCharges or MinChargeAdder).
		0.0001*MinChargeAdder is added back into LCC when writing to results.  =#
	nothing
end


function add_variables!(m::JuMP.AbstractModel, p::MPCInputs)
    @variables m begin
		# dvSize[p.techs.all] >= 0  # System Size of Technology t [kW]
		# dvPurchaseSize[p.techs.all] >= 0  # system kW beyond existing_kw that must be purchased
		dvGridPurchase[1:p.n_scenarios, p.time_steps, 1:p.s.electric_tariff.n_energy_tiers] >= 0  # Power from grid dispatched to meet electrical load [kW]
		dvRatedProduction[1:p.n_scenarios, p.techs.all, p.time_steps] >= 0  # Rated production of technology t [kW]
		dvCurtail[1:p.n_scenarios, p.techs.all, p.time_steps] >= 0  # [kW]
		dvProductionToStorage[1:p.n_scenarios, p.s.storage.types.all, p.techs.all, p.time_steps] >= 0  # Power from technology t used to charge storage system b [kW]
		dvDischargeFromStorage[1:p.n_scenarios, p.s.storage.types.all, p.time_steps] >= 0 # Power discharged from storage system b [kW]
		dvGridToStorage[1:p.n_scenarios, p.s.storage.types.elec, p.time_steps] >= 0 # Electrical power delivered to storage by the grid [kW]
		dvStoredEnergy[1:p.n_scenarios, p.s.storage.types.all, 0:p.time_steps[end]] >= 0  # State of charge of storage system b
		dvStoragePower[p.s.storage.types.all] >= 0   # Power capacity of storage system b [kW]
		dvStorageEnergy[p.s.storage.types.all] >= 0   # Energy capacity of storage system b [kWh]
		# TODO rm dvStoragePower/Energy dv's
		dvPeakDemandTOU[1:p.n_scenarios, p.ratchets, 1:p.s.electric_tariff.n_tou_demand_tiers] >= 0  # Peak electrical power demand during ratchet r [kW]
		dvPeakDemandMonth[1:p.n_scenarios, p.months, 1:p.s.electric_tariff.n_monthly_demand_tiers] >= 0  # Peak electrical power demand during month m [kW]
		# MinChargeAdder >= 0
	end
	# TODO: tiers in MPC tariffs and variables?

	if !isempty(p.s.electric_tariff.export_bins)
		@variable(m, dvProductionToGrid[1:p.n_scenarios, p.techs.elec, p.s.electric_tariff.export_bins, p.time_steps] >= 0)
	end

    m[:dvSize] = p.existing_sizes

	for b in p.s.storage.types.all
		fix(m[:dvStoragePower][b], p.s.storage.attr["ElectricStorage"].size_kw, force=true)
		fix(m[:dvStorageEnergy][b], p.s.storage.attr["ElectricStorage"].size_kwh, force=true)
	end

	# not modeling min charges since control does not affect them
    m[:MinChargeAdder] = 0

	if !isempty(p.techs.gen)  # Problem becomes a MILP
		@warn """Adding binary variable to model gas generator. 
				 Some solvers are very slow with integer variables"""
		@variables m begin
			dvFuelUsage[1:p.n_scenarios, p.techs.gen, p.time_steps] >= 0 # Fuel burned by technology t in each time step [kWh]
			binGenIsOnInTS[1:p.n_scenarios, p.techs.gen, p.time_steps], Bin  # 1 If technology t is operating in time step h; 0 otherwise
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
			dvMGProductionToStorage[p.techs.all, S, tZeros, outage_time_steps] >= 0 # Electricity going to the storage system during each time_step
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
end