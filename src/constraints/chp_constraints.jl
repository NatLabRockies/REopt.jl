# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_chp_fuel_burn_constraints(m, p; _n="")
    # Fuel cost
    m[:TotalCHPFuelCosts] = @expression(m, 
        sum(p.pwf_fuel[t] * m[:dvFuelUsage][t, ts] * p.fuel_cost_per_kwh[t][ts] for t in p.techs.chp, ts in p.time_steps)
    )
    
    # Loop through each CHP and add constraints with tech-specific parameters
    for t in p.techs.chp
        # Fuel burn slope and intercept for this specific CHP
        fuel_burn_slope, fuel_burn_intercept = fuel_slope_and_intercept(; 
            electric_efficiency_full_load = p.chp_params[t][:electric_efficiency_full_load], 
            electric_efficiency_half_load = p.chp_params[t][:electric_efficiency_half_load], 
            fuel_higher_heating_value_kwh_per_unit=1
        )

        # Conditionally add dvFuelBurnYIntercept if coefficient fuel_burn_intercept is greater than ~zero
        if abs(fuel_burn_intercept) > 1.0E-7
            if !haskey(m, Symbol("dvFuelBurnYIntercept"*_n))
                dv = "dvFuelBurnYIntercept"*_n
                m[Symbol(dv)] = @variable(m, [p.techs.chp, p.time_steps], base_name=dv)
            end

            #Constraint (1c1): Total Fuel burn for CHP **with** y-intercept fuel burn and supplementary firing
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvFuelUsage"*_n)][t,ts]  == p.hours_per_time_step * (
                    m[Symbol("dvFuelBurnYIntercept"*_n)][t,ts] +
                    p.production_factor[t,ts] * fuel_burn_slope * m[Symbol("dvRatedProduction"*_n)][t,ts] +
                    m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts] / p.chp_params[t][:supplementary_firing_efficiency]
                )
            )
            #Constraint (1d): Y-intercept fuel burn for CHP
            @constraint(m, [ts in p.time_steps],
                        fuel_burn_intercept * m[Symbol("dvSize"*_n)][t] - p.max_sizes[t] * 
                        (1-m[Symbol("binCHPIsOnInTS"*_n)][t,ts])  <= m[Symbol("dvFuelBurnYIntercept"*_n)][t,ts]
                        )
        else
            #Constraint (1c2): Total Fuel burn for CHP **without** y-intercept fuel burn
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvFuelUsage"*_n)][t,ts]  == p.hours_per_time_step * (
                    p.production_factor[t,ts] * fuel_burn_slope * m[Symbol("dvRatedProduction"*_n)][t,ts] +
                    m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts] / p.chp_params[t][:supplementary_firing_efficiency]
                )
            )
        end
    end
end

function add_chp_thermal_production_constraints(m, p; _n="")
    # Loop through each CHP and add constraints with tech-specific thermal production parameters
    for t in p.techs.chp
        # Thermal production slope and intercept for this specific CHP
        thermal_prod_full_load = 1.0 / p.chp_params[t][:electric_efficiency_full_load] * p.chp_params[t][:thermal_efficiency_full_load]  # [kWt/kWe]
        thermal_prod_half_load = 0.5 / p.chp_params[t][:electric_efficiency_half_load] * p.chp_params[t][:thermal_efficiency_half_load]   # [kWt/kWe]
        thermal_prod_slope = (thermal_prod_full_load - thermal_prod_half_load) / (1.0 - 0.5)  # [kWt/kWe]
        thermal_prod_intercept = thermal_prod_full_load - thermal_prod_slope * 1.0  # [kWt/kWe_rated]

        # Conditionally add dvHeatingProductionYIntercept if coefficient thermal_prod_intercept is greater than ~zero
        if abs(thermal_prod_intercept) > 1.0E-7
            if !haskey(m, Symbol("dvHeatingProductionYIntercept"*_n))
                dv = "dvHeatingProductionYIntercept"*_n
                m[Symbol(dv)] = @variable(m, [p.techs.chp, p.time_steps], base_name=dv)
            end

            #Constraint (2a-1): Upper Bounds on Thermal Production Y-Intercept
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvHeatingProductionYIntercept"*_n)][t,ts] <= thermal_prod_intercept * m[Symbol("dvSize"*_n)][t]
            )
            # Constraint (2a-2): Upper Bounds on Thermal Production Y-Intercept
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvHeatingProductionYIntercept"*_n)][t,ts] <= thermal_prod_intercept * p.max_sizes[t] 
                * m[Symbol("binCHPIsOnInTS"*_n)][t,ts]
            )
            #Constraint (2b): Lower Bounds on Thermal Production Y-Intercept
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvHeatingProductionYIntercept"*_n)][t,ts] >= thermal_prod_intercept * m[Symbol("dvSize"*_n)][t] 
                - thermal_prod_intercept * p.max_sizes[t] * (1 - m[Symbol("binCHPIsOnInTS"*_n)][t,ts])
            )
            # Constraint (2c): Thermal Production of CHP
            @constraint(m, [ts in p.time_steps],
            sum(m[Symbol("dvHeatingProduction"*_n)][t,q,ts] for q in p.heating_loads) ==
                thermal_prod_slope * p.production_factor[t,ts] * m[Symbol("dvRatedProduction"*_n)][t,ts] 
                + m[Symbol("dvHeatingProductionYIntercept"*_n)][t,ts] +
                m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts]
            )
        else
            @constraint(m, [ts in p.time_steps],
                sum(m[Symbol("dvHeatingProduction"*_n)][t,q,ts] for q in p.heating_loads) ==
                thermal_prod_slope * p.production_factor[t,ts] * m[Symbol("dvRatedProduction"*_n)][t,ts] +
                m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts]
            )        
        end
    end
end

"""
    add_chp_supplementary_firing_constraints(m, p; _n="")

Used by add_chp_constraints to add supplementary firing constraints if 
    p.chp_params[t][:supplementary_firing_max_steam_ratio] > 1.0 to add CHP supplementary firing operating constraints.  
    Else, the supplementary firing dispatch and size decision variables are set to zero.
"""
function add_chp_supplementary_firing_constraints(m, p; _n="")
    # Check if the Y-intercept variable exists
    has_y_intercept = haskey(m, Symbol("dvHeatingProductionYIntercept"*_n))
    
    for t in p.techs.chp
        thermal_prod_full_load = 1.0 / p.chp_params[t][:electric_efficiency_full_load] * p.chp_params[t][:thermal_efficiency_full_load]  # [kWt/kWe]
        thermal_prod_half_load = 0.5 / p.chp_params[t][:electric_efficiency_half_load] * p.chp_params[t][:thermal_efficiency_half_load]   # [kWt/kWe]
        thermal_prod_slope = (thermal_prod_full_load - thermal_prod_half_load) / (1.0 - 0.5)  # [kWt/kWe]
        thermal_prod_intercept = thermal_prod_full_load - thermal_prod_slope * 1.0  # [kWt/kWe_rated]

        # Constrain upper limit of dvSupplementaryThermalProduction
        if has_y_intercept && abs(thermal_prod_intercept) > 1.0E-7
            @constraint(m, [ts in p.time_steps],
                        m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts] <=
                        (p.chp_params[t][:supplementary_firing_max_steam_ratio] - 1.0) * p.production_factor[t,ts] * (thermal_prod_slope * m[Symbol("dvSupplementaryFiringSize"*_n)][t] + m[Symbol("dvHeatingProductionYIntercept"*_n)][t,ts])
                        )
        else
            @constraint(m, [ts in p.time_steps],
                        m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts] <=
                        (p.chp_params[t][:supplementary_firing_max_steam_ratio] - 1.0) * p.production_factor[t,ts] * thermal_prod_slope * m[Symbol("dvSupplementaryFiringSize"*_n)][t]
                        )
        end
        
        if solver_is_compatible_with_indicator_constraints(p.s.settings.solver_name)
            # Constrain lower limit of 0 if CHP tech is off
            @constraint(m, [ts in p.time_steps],
                    !m[Symbol("binCHPIsOnInTS"*_n)][t,ts] => {m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts] <= 0.0}
                    )
        else
            #There's no upper bound specified for the CHP supplementary firing, so assume the entire heat load as a reasonable maximum that wouldn't be exceeded (but might not be the best possible value). 
            max_supplementary_firing_size = maximum(p.s.dhw_load.loads_kw .+ p.s.space_heating_load.loads_kw)
            if has_y_intercept && abs(thermal_prod_intercept) > 1.0E-7
                @constraint(m, [ts in p.time_steps],
                        m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts] <= (p.chp_params[t][:supplementary_firing_max_steam_ratio] - 1.0) * p.production_factor[t,ts] * (thermal_prod_slope * max_supplementary_firing_size + m[Symbol("dvHeatingProductionYIntercept"*_n)][t,ts])
                        )
            else
                @constraint(m, [ts in p.time_steps],
                        m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts] <= (p.chp_params[t][:supplementary_firing_max_steam_ratio] - 1.0) * p.production_factor[t,ts] * thermal_prod_slope * max_supplementary_firing_size
                        )
            end
        end
    end
end

function add_binCHPIsOnInTS_constraints(m, p; _n="")
    # Note, min_turn_down_fraction for CHP is only enforced in p.time_steps_with_grid
    @constraint(m, [t in p.techs.chp, ts in p.time_steps_with_grid],
        m[Symbol("dvRatedProduction"*_n)][t, ts] <= p.max_sizes[t] * m[Symbol("binCHPIsOnInTS"*_n)][t, ts]
    )
    @constraint(m, [t in p.techs.chp, ts in p.time_steps_with_grid],
        p.chp_params[t][:min_turn_down_fraction] * m[Symbol("dvSize"*_n)][t] - m[Symbol("dvRatedProduction"*_n)][t, ts] <=
        p.max_sizes[t] * (1 - m[Symbol("binCHPIsOnInTS"*_n)][t, ts])
    )
end


function add_chp_rated_prod_constraint(m, p; _n="")
    @constraint(m, [t in p.techs.chp, ts in p.time_steps],
        m[Symbol("dvSize"*_n)][t] >= m[Symbol("dvRatedProduction"*_n)][t, ts]
    )
end


function add_chp_ramp_rate_constraints(m, p; _n="")
    # Ramp rate constraints limit how quickly CHP production can change between consecutive timesteps
    # Loop through each CHP and add constraints with tech-specific ramp rate parameters
    for t in p.techs.chp
        # Ramp up constraint
        @constraint(m, [ts in p.time_steps[2:end]],
            m[Symbol("dvRatedProduction"*_n)][t, ts] - m[Symbol("dvRatedProduction"*_n)][t, ts-1] <=
            p.chp_params[t][:ramp_rate_fraction_per_hour] * m[Symbol("dvSize"*_n)][t] / p.s.settings.time_steps_per_hour
        )
        
        # Ramp down constraint
        @constraint(m, [ts in p.time_steps[2:end]],
            m[Symbol("dvRatedProduction"*_n)][t, ts-1] - m[Symbol("dvRatedProduction"*_n)][t, ts] <=
            p.chp_params[t][:ramp_rate_fraction_per_hour] * m[Symbol("dvSize"*_n)][t] / p.s.settings.time_steps_per_hour
        )
    end
end


"""
    add_chp_hourly_om_charges(m, p; _n="")

- add decision variable "dvOMByHourBySizeCHP"*_n for the hourly CHP operations and maintenance costs
- add the cost to TotalPerUnitHourOMCosts
"""
function add_chp_hourly_om_charges(m, p; _n="")
    dv = "dvOMByHourBySizeCHP"*_n
    m[Symbol(dv)] = @variable(m, [p.techs.chp, p.time_steps], base_name=dv, lower_bound=0)

    for t in p.techs.chp
        # Find the CHP object for this tech to get om_cost_per_hr_per_kw_rated
        chp_idx = findfirst(chp -> chp.name == t, p.s.chps)
        om_cost_per_hr_per_kw = p.s.chps[chp_idx].om_cost_per_hr_per_kw_rated
        
        #Constraint CHP-hourly-om-a: om per hour, per time step >= per_unit_size_cost * size for when on, >= zero when off
        @constraint(m, [ts in p.time_steps],
            om_cost_per_hr_per_kw * m[Symbol("dvSize"*_n)][t] -
            p.max_sizes[t] * om_cost_per_hr_per_kw * (1-m[Symbol("binCHPIsOnInTS"*_n)][t,ts])
                <= m[Symbol("dvOMByHourBySizeCHP"*_n)][t, ts]
        )
        #Constraint CHP-hourly-om-b: om per hour, per time step <= per_unit_size_cost * size for each hour
        @constraint(m, [ts in p.time_steps],
            om_cost_per_hr_per_kw * m[Symbol("dvSize"*_n)][t]
                >= m[Symbol("dvOMByHourBySizeCHP"*_n)][t, ts]
        )
        #Constraint CHP-hourly-om-c: om per hour, per time step <= zero when off, <= per_unit_size_cost*max_size
        @constraint(m, [ts in p.time_steps],
            p.max_sizes[t] * om_cost_per_hr_per_kw * m[Symbol("binCHPIsOnInTS"*_n)][t,ts]
                >= m[Symbol("dvOMByHourBySizeCHP"*_n)][t, ts]
        )
    end
    
    m[:TotalHourlyCHPOMCosts] = @expression(m, p.third_party_factor * p.pwf_om * 
    sum(m[Symbol(dv)][t, ts] * p.hours_per_time_step for t in p.techs.chp, ts in p.time_steps))
    nothing
end


"""
    add_chp_constraints(m, p; _n="")

Used in src/reopt.jl to add_chp_constraints if !isempty(p.techs.chp) to add CHP operating constraints and 
cost expressions.
"""
function add_chp_constraints(m, p; _n="")   
    # Check if binary variable is needed by evaluating any CHP's parameters
    # Binary is needed if any CHP has non-zero intercepts, min_turn_down, or hourly O&M
    binary_needed = false
    for t in p.techs.chp
        # Calculate fuel burn slopes/intercepts for this CHP
        fuel_burn_slope, fuel_burn_intercept = fuel_slope_and_intercept(; 
            electric_efficiency_full_load = p.chp_params[t][:electric_efficiency_full_load], 
            electric_efficiency_half_load = p.chp_params[t][:electric_efficiency_half_load], 
            fuel_higher_heating_value_kwh_per_unit=1
        )
        
        # Calculate thermal production slopes/intercepts for this CHP
        thermal_prod_full_load = 1.0 / p.chp_params[t][:electric_efficiency_full_load] * p.chp_params[t][:thermal_efficiency_full_load]
        thermal_prod_half_load = 0.5 / p.chp_params[t][:electric_efficiency_half_load] * p.chp_params[t][:thermal_efficiency_half_load]
        thermal_prod_slope = (thermal_prod_full_load - thermal_prod_half_load) / (1.0 - 0.5)
        thermal_prod_intercept = thermal_prod_full_load - thermal_prod_slope * 1.0
        
        # Check if this CHP needs binary variables
        chp_idx = findfirst(chp -> chp.name == t, p.s.chps)
        if (abs(fuel_burn_intercept) > 1.0E-7) || 
           (abs(thermal_prod_intercept) > 1.0E-7) || 
           (p.chp_params[t][:min_turn_down_fraction] > 1.0E-7) ||
           (p.s.chps[chp_idx].om_cost_per_hr_per_kw_rated > 1.0E-7)
            binary_needed = true
            break
        end
    end
    
    # Create binary variable if needed
    if binary_needed
        @warn """Adding binary variable binCHPIsOnInTS to model CHP. 
                    Some solvers are very slow with integer variables"""
        @variables m begin
            binCHPIsOnInTS[p.techs.chp, p.time_steps], Bin  # 1 If technology t is operating in time step; 0 otherwise
        end
    end
    
    m[:TotalHourlyCHPOMCosts] = 0
    m[:TotalCHPFuelCosts] = 0
    # Sum om_cost_per_kwh for each CHP tech
    m[:TotalCHPPerUnitProdOMCosts] = @expression(m, p.third_party_factor * p.pwf_om *
        sum(p.chp_params[t][:om_cost_per_kwh] * p.hours_per_time_step *
        m[:dvRatedProduction][t, ts] for t in p.techs.chp, ts in p.time_steps)
    )

    # These constraints are always needed
    add_chp_fuel_burn_constraints(m, p; _n=_n)
    add_chp_thermal_production_constraints(m, p; _n=_n)
    add_chp_rated_prod_constraint(m, p; _n=_n)
    
    # Add ramp rate constraints if any CHP has ramp_rate_fraction_per_hour < 1.0
    if any(p.chp_params[t][:ramp_rate_fraction_per_hour] < 1.0 / p.s.settings.time_steps_per_hour for t in p.techs.chp)
        add_chp_ramp_rate_constraints(m, p; _n=_n)
    end

    # These constraints are only needed if binary was created
    if binary_needed
        add_binCHPIsOnInTS_constraints(m, p; _n=_n)
        
        # Check if any CHP has hourly O&M charges
        if any(chp.om_cost_per_hr_per_kw_rated > 1.0E-7 for chp in p.s.chps)
            add_chp_hourly_om_charges(m, p; _n=_n)
        end
    end

    # Add supplementary firing constraints - function handles per-tech logic
    add_chp_supplementary_firing_constraints(m,p; _n=_n)
    
    # Fix supplementary firing variables to zero for CHPs without supplementary firing
    for t in p.techs.chp
        if p.chp_params[t][:supplementary_firing_max_steam_ratio] <= 1.0
            fix(m[Symbol("dvSupplementaryFiringSize"*_n)][t], 0.0, force=true)
            for ts in p.time_steps
                fix(m[Symbol("dvSupplementaryThermalProduction"*_n)][t,ts], 0.0, force=true)
            end
        end
    end
end
