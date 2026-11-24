


function add_variables!(m::JuMP.AbstractModel, ps::AbstractVector{REoptInputs{T}}) where T <: AbstractScenario
	print(" Adding variables\n")
	dvs_idx_on_techs = String[
		"dvSize",
		"dvPurchaseSize",
	]
	dvs_idx_on_techs_time_steps = String[
        "dvCurtail",
		"dvRatedProduction",
	]
	dvs_idx_on_storagetypes = String[
		"dvStoragePower",
		"dvStorageEnergy"
	]
	dvs_idx_on_storagetypes_time_steps = String[
		"dvDischargeFromStorage"
	]
	
	for p in ps
		_n = string("_", p.s.site.node)

		for dv in dvs_idx_on_techs
			x = dv*_n
			m[Symbol(x)] = @variable(m, [p.techs.all], base_name=x, lower_bound=0)
		end

		for dv in dvs_idx_on_techs_time_steps
			x = dv*_n
			m[Symbol(x)] = @variable(m, [p.techs.all, p.time_steps], base_name=x, lower_bound=0)
		end

		for dv in dvs_idx_on_storagetypes
			x = dv*_n 
			m[Symbol(x)] = @variable(m, [p.s.storage.types.elec], base_name=x, lower_bound=0)
		end 

		for dv in dvs_idx_on_storagetypes_time_steps
			x = dv*_n 
			m[Symbol(x)] = @variable(m, [p.s.storage.types.all, p.time_steps], base_name=x, lower_bound=0)
			# add in the definition 
		end

		dv = "dvGridToStorage"*_n
		m[Symbol(dv)] = @variable(m, [p.s.storage.types.elec, p.time_steps], base_name=dv, lower_bound=0)

		dv = "dvGridPurchase"*_n
		if string(p.s.site.node) == p.s.settings.facilitymeter_node
			# The facility meter node is indexed by time step and energy tier, as in single node REopt, so that tiered energy rates can be used
			m[Symbol(dv)] = @variable(m, [p.time_steps, 1:p.s.electric_tariff.n_energy_tiers], base_name=dv, lower_bound=0)
		else
			if p.s.electric_tariff.n_energy_tiers > 1
				throw(@error("The electric tariff for node $(p.s.site.node) has tiered energy rates. Tiered energy rates are only supported at the facility meter node in the multinode model."))
			end
			m[Symbol(dv)] = @variable(m, [p.time_steps], base_name=dv, lower_bound=0)
		end

		dv = "dvPeakDemandTOU"*_n
		m[Symbol(dv)] = @variable(m, [p.ratchets, 1], base_name=dv, lower_bound=0)

		dv = "dvPeakDemandMonth"*_n
		m[Symbol(dv)] = @variable(m, [p.months, 1], base_name=dv, lower_bound=0)

		dv = "dvProductionToStorage"*_n
		m[Symbol(dv)] = @variable(m, [p.s.storage.types.all, p.techs.all, p.time_steps], base_name=dv, lower_bound=0)

		dv = "dvStoredEnergy"*_n
		m[Symbol(dv)] = @variable(m, [p.s.storage.types.all, 0:p.time_steps[end]], base_name=dv, lower_bound=0)

		dv = "MinChargeAdder"*_n
		m[Symbol(dv)] = @variable(m, base_name=dv, lower_bound=0)

		dv = "dvFuelUsage"*_n
		m[Symbol(dv)] = @variable(m, [p.techs.gen, 0:p.time_steps[end]], base_name=dv, lower_bound=0)
	
		dv = "binGenIsOnInTS"*_n
		m[Symbol(dv)] = @variable(m, [p.techs.gen, 0:p.time_steps[end]], base_name=dv, lower_bound=0, upper_bound=1)
		
		#if !isempty(p.s.storage.types.elec_no_simultaneous_charge_discharge)
		#	@warn "Adding binary variable to prevent simultaneous battery charge/discharge. Some solvers are very slow with integer variables."
		#end

		#dv = "binBattCharging"*_n
		#m[Symbol(dv)] = @variable(m, [p.s.storage.types.elec_no_simultaneous_charge_discharge, p.time_steps], base_name=dv, Bin)
		
		if !isempty(p.s.electric_tariff.export_bins)
            dv = "dvProductionToGrid"*_n
            m[Symbol(dv)] = @variable(m, [p.techs.elec, p.s.electric_tariff.export_bins, p.time_steps], base_name=dv, lower_bound=0)
			dv = "dvStorageToGrid"*_n
            m[Symbol(dv)] = @variable(m, [p.s.storage.types.elec, p.s.electric_tariff.export_bins, p.time_steps], base_name=dv, lower_bound=0)
        end

		ex_name = "TotalTechCapCosts"*_n
		m[Symbol(ex_name)] = @expression(m, p.third_party_factor *
			sum( p.cap_cost_slope[t] * m[Symbol("dvPurchaseSize"*_n)][t] for t in p.techs.all ) 
		)

		ex_name = "TotalStorageCapCosts"*_n
		m[Symbol(ex_name)] = @expression(m, p.third_party_factor * 
			sum(p.s.storage.attr[b].net_present_cost_per_kw * m[Symbol("dvStoragePower"*_n)][b] for b in p.s.storage.types.elec)
			+ sum(p.s.storage.attr[b].net_present_cost_per_kwh * m[Symbol("dvStorageEnergy"*_n)][b] for b in p.s.storage.types.all)
		)

		if !isempty(p.s.storage.types.elec)
			for b in p.s.storage.types.elec
				if (p.s.storage.attr[b].installed_cost_constant != 0) || (p.s.storage.attr[b].replace_cost_constant != 0)
					@warn "Adding binary variable for the battery cost constant. Some solvers are slow with binaries."
					dv = "binIncludeStorageCostConstant"*_n
					m[Symbol(dv)] = @variable(m, [p.s.storage.types.elec], base_name=dv, binary=true)
					break # If one of the elec storages has a battery constant, then do not need to create another binIncludeStorageCostConstraint because by default the binIncludeStorageCostConstraint is index on all elec storage types
				end
			end

			for b in p.s.storage.types.elec
				if (p.s.storage.attr[b].installed_cost_constant != 0) || (p.s.storage.attr[b].replace_cost_constant != 0)
					add_to_expression!(m[Symbol(ex_name)], sum(p.s.storage.attr[b].net_present_cost_cost_constant * m[Symbol("binIncludeStorageCostConstant"*_n)][b] ))
				end
			end
		end

        # Add ElectricStorageCapCost and ElectricStorageOMCost expressions (like in reopt.jl)
        ex_name = "ElectricStorageCapCost"*_n
        m[Symbol(ex_name)] = @expression(m, 
            sum(p.s.storage.attr[b].installed_cost_per_kw * m[Symbol("dvStoragePower"*_n)][b] for b in p.s.storage.types.elec) +
            sum(p.s.storage.attr[b].installed_cost_per_kwh * m[Symbol("dvStorageEnergy"*_n)][b] for b in p.s.storage.types.elec)
        )
        # Add installed_cost_constant if needed
        if !isempty(p.s.storage.types.elec)
            for b in p.s.storage.types.elec
                if (p.s.storage.attr[b].installed_cost_constant != 0) || (p.s.storage.attr[b].replace_cost_constant != 0)
                    m[Symbol(ex_name)] = m[Symbol(ex_name)] + sum(p.s.storage.attr[b].installed_cost_constant * m[Symbol("binIncludeStorageCostConstant"*_n)][b])
                end
            end
        end

        ex_name_om = "ElectricStorageOMCost"*_n
        m[Symbol(ex_name_om)] = @expression(m,
            p.third_party_factor * p.pwf_om *
            sum(p.s.storage.attr[b].om_cost_fraction_of_installed_cost * m[Symbol("ElectricStorageCapCost"*_n)] for b in p.s.storage.types.elec)
        )		

		# Up-front capital costs before incentives for this node (reported as "initial_capital_costs" in the results).
		# Note the code for this ex_name = "InitialCapexNoIncentives"*_n (the next about 14 lines) was generated with the assistance of AI.
		# Multinode does not use cost curve segments, so each tech's cost is its installed cost per kW times its purchased (new) size
		ex_name = "InitialCapexNoIncentives"*_n
		# Start from an empty affine expression, because ElectricStorageCapCost is a plain number (0.0) at nodes without electric storage
		m[Symbol(ex_name)] = JuMP.AffExpr(0.0)
		add_to_expression!(m[Symbol(ex_name)], m[Symbol("ElectricStorageCapCost"*_n)])
		for pv in p.s.pvs
			pv.name in p.techs.all || continue
			pv_installed_cost_per_kw = pv.installed_cost_per_kw isa AbstractVector ? pv.installed_cost_per_kw[1] : pv.installed_cost_per_kw
			add_to_expression!(m[Symbol(ex_name)], pv_installed_cost_per_kw * m[Symbol("dvPurchaseSize"*_n)][pv.name])
		end
		if "Wind" in p.techs.all
			add_to_expression!(m[Symbol(ex_name)], p.s.wind.installed_cost_per_kw * m[Symbol("dvPurchaseSize"*_n)]["Wind"])
		end
		if !isempty(p.techs.gen)
			add_to_expression!(m[Symbol(ex_name)], p.s.generator.installed_cost_per_kw * m[Symbol("dvPurchaseSize"*_n)]["Generator"])
		end

		ex_name = "TotalPerUnitSizeOMCosts"*_n
		m[Symbol(ex_name)] = @expression(m, p.third_party_factor * p.pwf_om * 
			sum( p.om_cost_per_kw[t] * m[Symbol("dvSize"*_n)][t] for t in p.techs.all ) 
		)

        ex_name = "TotalPerUnitProdOMCosts"*_n
		m[Symbol(ex_name)] = 0

		ex_name = "TotalFuelCosts"*_n
		m[Symbol(ex_name)] = 0

		ex_name = "TotalFuelCosts"
		m[Symbol(ex_name)] = 0

		if !isempty(p.techs.gen)
            add_gen_constraints(m, p; _n = _n )
            m[Symbol("TotalPerUnitProdOMCosts"*_n)] += m[Symbol("TotalGenPerUnitProdOMCosts"*_n)] + m[Symbol("TotalHourlyGenOMCosts"*_n)]
            m[Symbol("TotalFuelCosts"*_n)] += m[Symbol("TotalGenFuelCosts"*_n)]
		end	

		if !isempty(p.s.electric_tariff.export_bins)
        		add_export_constraints(m, p; _n=_n)
		end

		if !isempty(p.s.electric_tariff.coincpeak_periods)
			add_coincident_peak_charge_constraints(m, p; _n=_n)
		end

		add_elec_utility_expressions(m, p; _n=_n)

		# Existing HVAC Cost NOT hooked up for multi-node; this is a patch to avoid errors
		ex_name = "ExistingBoilerCost"*_n
		m[Symbol(ex_name)] = 0
		ex_name = "ExistingChillerCost"*_n
		m[Symbol(ex_name)] = 0
	
		#################################  Objective Function   ########################################
		m[Symbol("Costs"*_n)] = @expression(m,
			#TODO: update in line with non-multinode version
			# Capital Costs
			m[Symbol("TotalTechCapCosts"*_n)] + m[Symbol("TotalStorageCapCosts"*_n)] +  
			
			## Fixed O&M, tax deductible for owner
			(m[Symbol("TotalPerUnitSizeOMCosts"*_n)] + m[Symbol("ElectricStorageOMCost"*_n)]) * (1 - p.s.financial.owner_tax_rate_fraction) +

			# Variable O&M (including hourly generator O&M), tax deductible for owner
			m[Symbol("TotalPerUnitProdOMCosts"*_n)] * (1 - p.s.financial.owner_tax_rate_fraction) +

			# Fuel costs, tax deductible for offtaker
			m[Symbol("TotalFuelCosts"*_n)] * (1 - p.s.financial.offtaker_tax_rate_fraction) +

			# Utility Bill, tax deductible for offtaker, including export benefit
			m[Symbol("TotalElecBill"*_n)] * (1 - p.s.financial.offtaker_tax_rate_fraction)
			
		);
    end
end


function build_reopt!(m::JuMP.AbstractModel, ps::AbstractVector{REoptInputs{T}}, d) where T <: AbstractScenario
    add_variables!(m, ps)
	@warn "Emissions and renewable energy fractions are not currently modeled in multinode mode."

    for p in ps
        _n = string("_", p.s.site.node)
		
		for b in p.s.storage.types.all
            if p.s.storage.attr[b].max_kw == 0 || p.s.storage.attr[b].max_kwh == 0
                @info "\n For node $(_n), the storage input size was 0 kW or 0 kWh, so the battery will not be used"
				@constraint(m, [ts in p.time_steps], m[Symbol("dvStoredEnergy"*_n)][b, ts] == 0)
                @constraint(m, m[Symbol("dvStorageEnergy"*_n)][b] == 0)
                @constraint(m, m[Symbol("dvStoragePower"*_n)][b] == 0)
                @constraint(m, [t in p.techs.elec, ts in p.time_steps_with_grid],
                            m[Symbol("dvProductionToStorage"*_n)][b, t, ts] == 0)
                @constraint(m, [ts in p.time_steps], m[Symbol("dvDischargeFromStorage"*_n)][b, ts] == 0)
				if b in p.s.storage.types.elec
					@constraint(m, [ts in p.time_steps], m[Symbol("dvGridToStorage"*_n)][b, ts] == 0)
					@constraint(m, [u in p.export_bins_by_storage[b], ts in p.time_steps], m[Symbol("dvStorageToGrid"*_n)][b, u, ts] == 0)
					if (p.s.storage.attr[b].installed_cost_constant != 0) || (p.s.storage.attr[b].replace_cost_constant != 0)
						@constraint(m, m[Symbol("binIncludeStorageCostConstant"*_n)][b] == 0)
					end
				end
            else
                add_storage_size_constraints(m, p, b; _n=_n)
                add_general_storage_dispatch_constraints(m, p, b; _n=_n)
				if b in p.s.storage.types.elec
					add_elec_storage_dispatch_constraints(m, p, b; _n=_n)
    				if (p.s.storage.attr[b].installed_cost_constant != 0) || (p.s.storage.attr[b].replace_cost_constant != 0)
						add_elec_storage_cost_constant_constraints(m, p, b; _n=_n)
					end
					# Constraint for min battery state of charge during non-outage times, excluding the recharge window after each grid outage
					@constraint(m, [ts in setdiff(d.grid_available_timesteps, d.battery_recharge_timesteps_after_grid_outage)],
                            m[Symbol("dvStoredEnergy"*_n)][b,ts] >=  d.battery_min_soc_fraction_during_non_outage_times * m[Symbol("dvStorageEnergy"*_n)][b])
					# Constraint for min battery state of charge during grid-outage times and the recharge window after each grid outage
					@constraint(m, [ts in union(d.grid_outage_timesteps, d.battery_recharge_timesteps_after_grid_outage)],
                            m[Symbol("dvStoredEnergy"*_n)][b,ts] >=  d.battery_min_soc_fraction_during_grid_outage_times * m[Symbol("dvStorageEnergy"*_n)][b])
				elseif b in p.s.storage.types.hot
					add_hot_thermal_storage_dispatch_constraints(m, p, b; _n=_n)
				elseif b in p.s.storage.types.cold
					add_cold_thermal_storage_dispatch_constraints(m, p, b; _n=_n)
				else
					throw(@error("Invalid storage does not fall in a thermal or electrical set"))
				end
            end
        end

        if any(max_kw->max_kw > 0, (p.s.storage.attr[b].max_kw for b in p.s.storage.types.elec))
            add_storage_sum_grid_constraints(m, p; _n=_n)
        end
    
        if !isempty(p.techs.all)
            add_tech_size_constraints(m, p; _n=_n)
            if !isempty(p.techs.no_curtail)
                add_no_curtail_constraints(m, p; _n=_n)
            end
        end
		
		# Only apply the load balance constraint to nodes that aren't the facility meter node. The facility meter node may be used as a meter for the multinode network, so the "grid_import" is set to the power flow through the line upstream of that node
		if string(p.s.site.node) != p.s.settings.facilitymeter_node  
			add_elec_load_balance_constraints(m, p; _n=_n)
			add_production_constraints(m, p; _n=_n)
		else
			print("\n Not applying the REopt load balance constraint to the node $(_n) because it is the facility meter node. No technologies should be applied to it. \n")
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

        if p.s.electric_tariff.demand_lookback_percent > 0
            add_demand_lookback_constraints(m, p; _n=_n)
        end
    
    end
end


function add_objective!(m::JuMP.AbstractModel, ps::AbstractVector{REoptInputs{T}}) where T <: AbstractScenario
	if !(any(p.s.settings.add_soc_incentive for p in ps))
		@objective(m, Min, sum(m[Symbol(string("Costs_", p.s.site.node))] for p in ps))
	else # Keep SOC high
		@objective(m, Min, sum(m[Symbol(string("Costs_", p.s.site.node))] for p in ps)
        - sum(sum(sum(m[Symbol(string("dvStoredEnergy_", p.s.site.node))][b, ts] 
            for ts in p.time_steps) for b in p.s.storage.types.elec) for p in ps) / (8760. / ps[1].hours_per_time_step))
	end  # TODO need to handle different hours_per_time_step?
	nothing
end

#=
function run_reopt(m::JuMP.AbstractModel, ps::AbstractVector{REoptInputs{T}}) where T <: AbstractScenario

	build_reopt!(m, ps)

	add_objective!(m, ps)

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
        @warn "REopt solved with " termination_status(m), ", returning the model."
        return m
	end
	@info "REopt solved with " termination_status(m)
	@info "Solving took $(opt_time) seconds."
    
	tstart = time()
	results = reopt_results(m, ps)
	time_elapsed = time() - tstart
	@info "Results processing took $(round(time_elapsed, digits=3)) seconds."
	results["status"] = status
	results["solver_seconds"] = opt_time
	return results
end
=#

function reopt_results(m::JuMP.AbstractModel, ps::AbstractVector{REoptInputs{T}}) where T <: AbstractScenario
	# TODO address Warning: The addition operator has been used on JuMP expressions a large number of times.
	results = Dict{Union{Int, String}, Any}()
	for p in ps
		results[p.s.site.node] = reopt_results(m, p; _n=string("_", p.s.site.node))
	end
	return results
end

