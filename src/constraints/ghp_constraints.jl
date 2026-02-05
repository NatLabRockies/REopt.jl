# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_ghp_constraints(m, p; _n="")
    # add_ghp_heating_elec was used in API's reopt_model.jl for "NewMaxSize" values, but these are not in REopt.jl currently
    # add_ghp_heating_elec = 1.0

    m[:GHPCapCosts] = @expression(m, p.third_party_factor *
        sum(p.ghp_installed_cost[g] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options)
    )

    m[:GHPOMCosts] = @expression(m, p.third_party_factor * p.pwf_om *
        sum(p.ghp_om_cost_year_one[g] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options)
    )

    if p.require_ghp_purchase == 1
        @constraint(m, GHPOptionSelect,
            sum(m[Symbol("binGHP"*_n)][g] for g in p.ghp_options) == 1
        )
    else
        @constraint(m, GHPOptionSelect,
            sum(m[Symbol("binGHP"*_n)][g] for g in p.ghp_options) <= 1
        )
    end

    m[:AvoidedCapexByGHP] = @expression(m,
        sum(p.avoided_capex_by_ghp_present_value[g] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options)
    )

    m[:ResidualGHXCapCost] = @expression(m,
        sum(p.ghx_residual_value[g] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options)
    )

    if length(p.ghp_options) == 1
        g = p.ghp_options[1]
        if p.s.ghp_option_list[g].can_serve_dhw
            @constraint(m, GHPDHWandSpaceHeatingCon[s in 1:p.n_scenarios, ts in p.time_steps],
                m[Symbol("dvHeatingProduction"*_n)][s, "GHP","DomesticHotWater",ts] + m[Symbol("dvHeatingProduction"*_n)][s, "GHP","SpaceHeating",ts] == 
                (p.space_heating_thermal_load_reduction_with_ghp_kw[g,ts] + p.ghp_heating_thermal_load_served_kw[g,ts]) * m[Symbol("binGHP"*_n)][g]
            )
            @constraint(m, GHPDHWLimitCon[s in 1:p.n_scenarios, ts in p.time_steps],
                m[Symbol("dvHeatingProduction"*_n)][s, "GHP","DomesticHotWater",ts] <= 
                p.ghp_heating_thermal_load_served_kw[g,ts] * m[Symbol("binGHP"*_n)][g]
            )
        else
            @constraint(m, GHPDHWCon[s in 1:p.n_scenarios, ts in p.time_steps],
                m[Symbol("dvHeatingProduction"*_n)][s, "GHP","DomesticHotWater",ts] == 0.0
            )

            @constraint(m, GHPSpaceHeatingCon[s in 1:p.n_scenarios, ts in p.time_steps],
                m[Symbol("dvHeatingProduction"*_n)][s, "GHP","SpaceHeating",ts] == 
                (p.space_heating_thermal_load_reduction_with_ghp_kw[g,ts] + p.ghp_heating_thermal_load_served_kw[g,ts]) * m[Symbol("binGHP"*_n)][g]
            )
        end        

        @constraint(m, GHPCoolingCon[s in 1:p.n_scenarios, ts in p.time_steps],
            m[Symbol("dvCoolingProduction"*_n)][s, "GHP",ts] == 
            (p.cooling_thermal_load_reduction_with_ghp_kw[g,ts] + p.ghp_cooling_thermal_load_served_kw[g,ts]) * m[Symbol("binGHP"*_n)][g]
        )

    else
        dv = "dvGHPHeatingProduction"*_n
        m[Symbol(dv)] = @variable(m, [1:p.n_scenarios, p.ghp_options, p.heating_loads, p.time_steps], base_name=dv, lower_bound=0)
        
        dv = "dvGHPCoolingProduction"*_n
        m[Symbol(dv)] = @variable(m, [1:p.n_scenarios, p.ghp_options, p.time_steps], base_name=dv, lower_bound=0)
        

        for g in p.ghp_options
            if !isnothing(p.s.ghp_option_list[g])
                if p.s.ghp_option_list[g].can_serve_dhw
                    con = "GHPDHWandSpaceHeatingConOption"*string(g)*_n
                    m[Symbol(con)] = @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
                        m[Symbol("dvGHPHeatingProduction"*_n)][s, g,"DomesticHotWater",ts] + m[Symbol("dvGHPHeatingProduction"*_n)][s, g,"SpaceHeating",ts] == 
                        (p.space_heating_thermal_load_reduction_with_ghp_kw[g,ts] + p.ghp_heating_thermal_load_served_kw[g,ts]) * m[Symbol("binGHP"*_n)][g]
                    )
                    con = "GHPSpaceHeatingLimitConOption"*string(g)*_n
                    m[Symbol(con)] = @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
                        m[Symbol("dvGHPHeatingProduction"*_n)][s, g,"DomesticHotWater",ts] <= 
                        p.ghp_heating_thermal_load_served_kw[g,ts] * m[Symbol("binGHP"*_n)][g]
                    )
                else
                    con = "GHPDHWConOption"*string(g)*_n
                    m[Symbol(con)] = @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
                        m[Symbol("dvGHPHeatingProduction"*_n)][s, g,"DomesticHotWater",ts] == 0.0
                    )
                    con = "GHPSpaceHeatingConOption"*string(g)*_n
                    m[Symbol(con)] = @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
                        m[Symbol("dvGHPHeatingProduction"*_n)][s, g,"SpaceHeating",ts] == 
                        (p.space_heating_thermal_load_reduction_with_ghp_kw[g,ts] + p.ghp_heating_thermal_load_served_kw[g,ts]) * m[Symbol("binGHP"*_n)][g]
                    )
                end
                con = "GHPCoolingConOption"*string(g)*_n
                m[Symbol(con)] = @constraint(m, [s in 1:p.n_scenarios, g in p.ghp_options, ts in p.time_steps],
                    m[Symbol("dvGHPCoolingProduction"*_n)][s, g,ts] == 
                    (p.cooling_thermal_load_reduction_with_ghp_kw[g,ts] + p.ghp_cooling_thermal_load_served_kw[g,ts]) * m[Symbol("binGHP"*_n)][g]
                )
            end
        end
        
        @constraint(m, GHPHeatingReconciliation[s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps],
            m[Symbol("dvHeatingProduction"*_n)][s, "GHP",q,ts] == sum(m[Symbol("dvGHPHeatingProduction"*_n)][s, g,q,ts] for g in p.ghp_options)
        )
        @constraint(m, GHPCoolingReconciliation[s in 1:p.n_scenarios, ts in p.time_steps],
            m[Symbol("dvCoolingProduction"*_n)][s, "GHP",ts] == sum(m[Symbol("dvGHPCoolingProduction"*_n)][s, g,ts] for g in p.ghp_options)
        )

    end
    # TODO determine whether process heat or steam turbine input is feasible with GHP, or is this sufficient?
    
    @constraint(m, GHPProcessHeatCon[s in 1:p.n_scenarios, ts in p.time_steps], m[Symbol("dvHeatingProduction"*_n)][s, "GHP","ProcessHeat",ts] == 0.0)
    @constraint(m, GHPHeatFlowCon[s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps], m[Symbol("dvProductionToWaste"*_n)][s, "GHP",q,ts] + sum(m[Symbol("dvHeatToStorage"*_n)][s, b,"GHP",q,ts] for b in p.s.storage.types.hot) <= m[Symbol("dvHeatingProduction"*_n)][s, "GHP",q,ts])
end