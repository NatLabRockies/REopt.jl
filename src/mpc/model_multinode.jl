# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

"""
    run_mpc(m::JuMP.AbstractModel, ps::AbstractVector{MPCInputs})

Solve the model predictive control problem using multiple `MPCInputs`.

Returns a Dict of results with keys matching those in the `MPCScenario`.
"""
function run_mpc(m::JuMP.AbstractModel, ps::AbstractVector{MPCInputs})
    build_mpc!(m, ps)

    @objective(m, Min, sum(m[Symbol(string("Costs_", p.s.node))] for p in ps))

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

	results = Dict{Union{Int, String}, Any}()
	for p in ps
		results[p.s.node] = mpc_results(m, p; _n=string("_", p.s.node))
	end

	time_elapsed = time() - tstart
	@info "Results processing took $(round(time_elapsed, digits=3)) seconds."
	results["status"] = status
	results["solver_seconds"] = opt_time
	return results
end


"""
    build_mpc!(m::JuMP.AbstractModel, ps::AbstractVector{MPCInputs})

Add variables and constraints for model predictive control model of multiple nodes. 
Similar to a REopt model but with any length of horizon (instead of one calendar year),
and the DER sizes must be provided.
"""
function build_mpc!(m::JuMP.AbstractModel, ps::AbstractVector{MPCInputs})
    add_variables!(m, ps)
    @warn "Outages are not currently modeled in multinode mode."
    @warn "Diesel generators are not currently modeled in multinode mode."
	@warn "Emissions and renewable energy fractions are not currently modeling in multinode mode."
    for p in ps
        _n = string("_", p.s.node)

		for b in p.s.storage.types.all
			if p.s.storage.attr[b].size_kw == 0 || p.s.storage.attr[b].size_kwh == 0
				@constraint(m, [ts in p.time_steps], m[Symbol("dvStoredEnergy"*_n)][b, ts] == 0)
				@constraint(m, [t in p.techs.elec, ts in p.time_steps_with_grid],
							m[Symbol("dvProductionToStorage"*_n)][b, t, ts] == 0)
				@constraint(m, [ts in p.time_steps], m[Symbol("dvDischargeFromStorage"*_n)][b, ts] == 0)
				if b in p.s.storage.types.elec
					@constraint(m, [ts in p.time_steps], m[Symbol("dvGridToStorage"*_n)][b, ts] == 0)
				end
			else
				add_general_storage_dispatch_constraints(m, p, b; _n=_n)
				if b in p.s.storage.types.elec
					add_elec_storage_dispatch_constraints(m, p, b; _n=_n)
				elseif b in p.s.storage.types.hot
					add_hot_thermal_storage_dispatch_constraints(m, p, b; _n=_n)
				elseif b in p.s.storage.types.cold
					add_cold_thermal_storage_dispatch_constraints(m, p, b; _n=_n)
				else
					throw(@error("Invalid storage does not fall in a thermal or electrical set"))
				end
			end
		end

		if any(size_kw->size_kw > 0, (p.s.storage.attr[b].size_kw for b in p.s.storage.types.elec))
			add_storage_sum_grid_constraints(m, p; _n=_n)
		end

		add_production_constraints(m, p; _n=_n)

		if !isempty(p.techs.no_turndown)
			@constraint(m, [t in p.techs.no_turndown, ts in p.time_steps],
				m[Symbol("dvRatedProduction"*_n)][t,ts] == m[Symbol("dvSize"*_n)][t]
			)
		end

		add_elec_load_balance_constraints(m, p; _n=_n)

		if !isempty(p.s.limits.grid_draw_limit_kw_by_time_step)
			add_grid_draw_limits(m, p; _n=_n)
		end

		if !isempty(p.s.electric_tariff.export_bins)
			add_export_constraints(m, p; _n=_n)
			if !isempty(p.s.limits.export_limit_kw_by_time_step)
				add_export_limits(m, p; _n=_n)
			end
		end

		if !isempty(p.s.electric_tariff.monthly_demand_rates)
			add_monthly_peak_constraint(m, p; _n=_n)
		end

		if !isempty(p.s.electric_tariff.tou_demand_ratchet_time_steps)
			add_tou_peak_constraint(m, p; _n=_n)
		end

		if !(p.s.electric_utility.allow_simultaneous_export_import) & !isempty(p.s.electric_tariff.export_bins)
			add_simultaneous_export_import_constraint(m, p; _n=_n)
		end
	
		## no multinode generators yet
		# m[Symbol("TotalFuelCosts"+_n)] = 0.0
		# m[Symbol("TotalPerUnitProdOMCosts"+_n)] = 0.0

		add_elec_utility_expressions(m, p; _n=_n)
		add_previous_monthly_peak_constraint(m, p; _n=_n)
		add_previous_tou_peak_constraint(m, p; _n=_n)

		#################################  Objective Function   ########################################
		m[Symbol("Costs"*_n)] = @expression(m,
			
			# # Variable O&M
			# m[Symbol("TotalPerUnitProdOMCosts"+_n)] +

			# # Total Generator Fuel Costs
			# m[Symbol("TotalFuelCosts"+_n)] +
	
			# Utility Bill
			m[Symbol("TotalElecBill"*_n)]
		);

	end

	nothing
end


function add_variables!(m::JuMP.AbstractModel, ps::AbstractVector{MPCInputs})

	dvs_idx_on_techs_time_steps = String[
        "dvCurtail",
		"dvRatedProduction",
	]
	dvs_idx_on_storagetypes_time_steps = String[
		"dvDischargeFromStorage"
	]
	for p in ps
		_n = string("_", p.s.node)

		m[Symbol("dvSize"*_n)] = p.existing_sizes

		for dv in dvs_idx_on_techs_time_steps
			x = dv*_n
			m[Symbol(x)] = @variable(m, [p.techs.all, p.time_steps], base_name=x, lower_bound=0)
		end
		
		m[Symbol("dvStoragePower"*_n)] = Dict{String, Float64}()
		m[Symbol("dvStorageEnergy"*_n)] = Dict{String, Float64}()
		for b in p.s.storage.types.elec
			m[Symbol("dvStoragePower"*_n)][b] = p.s.storage.attr[b].size_kw
			m[Symbol("dvStorageEnergy"*_n)][b] = p.s.storage.attr[b].size_kwh
		end

		for dv in dvs_idx_on_storagetypes_time_steps
			x = dv*_n
			m[Symbol(x)] = @variable(m, [p.s.storage.types.all, p.time_steps], base_name=x, lower_bound=0)
		end

		dv = "dvGridToStorage"*_n
		m[Symbol(dv)] = @variable(m, [p.s.storage.types.elec, p.time_steps], base_name=dv, lower_bound=0)

		dv = "dvGridPurchase"*_n
		m[Symbol(dv)] = @variable(m, [p.time_steps], base_name=dv, lower_bound=0)

		dv = "dvPeakDemandTOU"*_n
		m[Symbol(dv)] = @variable(m, [p.ratchets, 1], base_name=dv, lower_bound=0)

		dv = "dvPeakDemandMonth"*_n
		m[Symbol(dv)] = @variable(m, [p.months, 1], base_name=dv, lower_bound=0)

		dv = "dvProductionToStorage"*_n
		m[Symbol(dv)] = @variable(m, [p.s.storage.types.all, p.techs.all, p.time_steps], base_name=dv, lower_bound=0)

		dv = "dvStoredEnergy"*_n
		m[Symbol(dv)] = @variable(m, [p.s.storage.types.all, 0:p.time_steps[end]], base_name=dv, lower_bound=0)

		dv = "MinChargeAdder"*_n
		m[Symbol(dv)] = 0

        if !isempty(p.s.electric_tariff.export_bins)
            dv = "dvProductionToGrid"*_n
            m[Symbol(dv)] = @variable(m, [p.techs.elec, p.s.electric_tariff.export_bins, p.time_steps], base_name=dv, lower_bound=0)
        end

        ex_name = "TotalPerUnitProdOMCosts"*_n
		m[Symbol(ex_name)] = 0 # TODO make sure this gets adjusted for multi nodes
	
    end

	nothing
	
end