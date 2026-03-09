# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_flexible_hvac_constraints(m, p::REoptInputs; _n="") 

    binFlexHVAC = @variable(m, binary = true)
    (N, J) = size(p.s.flexible_hvac.input_matrix)
    dvTemperature = @variable(m, [1:N, p.time_steps])
    @variable(m, lower_comfort_slack[p.time_steps] >= 0)
    @variable(m, upper_comfort_slack[p.time_steps] >= 0)

    # initialize space temperatures
    @constraint(m, dvTemperature[:, 1] .== p.s.flexible_hvac.initial_temperatures)

    # TODO time scaling for dt?
    input_vec = zeros(N)
    input_vec[p.s.flexible_hvac.control_node] = 1

    if !isempty(p.techs.heating) && !isempty(p.techs.cooling)
        # space temperature evolution based on state-space model
        # TODO: Add indicator constraint workaround for FlexibleHVAC
        @constraint(m, [n in 1:N, ts in 2:length(p.time_steps)],
            binFlexHVAC => { dvTemperature[n, ts] == dvTemperature[n, ts-1] + 
                sum(p.s.flexible_hvac.system_matrix[n, i] * dvTemperature[i, ts-1] for i=1:N) + 
                sum(p.s.flexible_hvac.input_matrix[n, j] * p.s.flexible_hvac.exogenous_inputs[j, ts-1] for j=1:J) + 
                input_vec[n] * p.s.flexible_hvac.input_matrix[n, p.s.flexible_hvac.control_node] * (
                    sum(m[Symbol("dvHeatingProduction"*_n)][t, "SpaceHeating", ts-1] for t in p.techs.heating) -
                    sum(m[Symbol("dvCoolingProduction"*_n)][t, ts-1] for t in p.techs.cooling) 
                )}
        )
        @constraint(m, [ts in p.time_steps], 
            p.s.flexible_hvac.temperature_lower_bound_degC - lower_comfort_slack[ts] <= 
            dvTemperature[p.s.flexible_hvac.control_node, ts]
        )
        @constraint(m, [ts in p.time_steps],
            dvTemperature[p.s.flexible_hvac.control_node, ts] <= 
            p.s.flexible_hvac.temperature_upper_bound_degC + upper_comfort_slack[ts]
        )

    elseif !isempty(p.techs.heating)

        @constraint(m, [n in 1:N, ts in 2:length(p.time_steps)],
            binFlexHVAC => { dvTemperature[n, ts] == dvTemperature[n, ts-1] + 
            sum(p.s.flexible_hvac.system_matrix[n, i] * dvTemperature[i, ts-1] for i=1:N) + 
            sum(p.s.flexible_hvac.input_matrix[n, j] * p.s.flexible_hvac.exogenous_inputs[j, ts-1] for j=1:J) + 
            input_vec[n] * p.s.flexible_hvac.input_matrix[n, p.s.flexible_hvac.control_node] * (
                sum(m[Symbol("dvHeatingProduction"*_n)][t, "SpaceHeating", ts-1] for t in p.techs.heating)
            )}
        )
        @constraint(m, [ts in p.time_steps], 
            p.s.flexible_hvac.temperature_lower_bound_degC - lower_comfort_slack[ts] <= 
            dvTemperature[p.s.flexible_hvac.control_node, ts]
        )
        # when only heating the upper temperature limit is the highest temperature seen naturally
        @constraint(m, [ts in p.time_steps],
            dvTemperature[p.s.flexible_hvac.control_node, ts] <= 
            maximum(p.s.flexible_hvac.bau_hvac.temperatures[p.s.flexible_hvac.control_node, :]) + 
            upper_comfort_slack[ts]
        )

    elseif !isempty(p.techs.cooling)

        @constraint(m, [n in 1:N, ts in 2:length(p.time_steps)],
            binFlexHVAC => { dvTemperature[n, ts] == dvTemperature[n, ts-1] + 
            sum(p.s.flexible_hvac.system_matrix[n, i] * dvTemperature[i, ts-1] for i=1:N) + 
            sum(p.s.flexible_hvac.input_matrix[n, j] * p.s.flexible_hvac.exogenous_inputs[j, ts-1] for j=1:J) -
            input_vec[n] * p.s.flexible_hvac.input_matrix[n, p.s.flexible_hvac.control_node] * (
                sum(m[Symbol("dvCoolingProduction"*_n)][t, ts-1] for t in p.techs.cooling) 
            )}
        )
        # when only cooling the lower temperature limit is the lowest temperature seen naturally
        @constraint(m, [ts in p.time_steps], 
            minimum(p.s.flexible_hvac.bau_hvac.temperatures[p.s.flexible_hvac.control_node, :]) - 
            lower_comfort_slack[ts] <= 
            dvTemperature[p.s.flexible_hvac.control_node, ts]
        )
        @constraint(m, [ts in p.time_steps],
            dvTemperature[p.s.flexible_hvac.control_node, ts] <= 
            p.s.flexible_hvac.temperature_upper_bound_degC + upper_comfort_slack[ts]
        )
    end

    dvComfortLimitViolationCost = @expression(m,  
        1e9 * sum(lower_comfort_slack[ts] + upper_comfort_slack[ts] for ts in p.time_steps)
    )
    # TODO convert dvHeatingProduction and dvCoolingProduction units? to ? shouldn't the conversion be in input_matrix coef? COP in Xiang's test is 4-5, fan_power_ratio = 0, hp prod factor generally between 1 and 2
    ## TODO check eigen values / stability of system matrix?


    @variable(m, dvFlexHVACcost >= 0)
    @constraint(m, binFlexHVAC => { dvFlexHVACcost >= p.s.flexible_hvac.installed_cost})
    m[:TotalTechCapCosts] += dvFlexHVACcost

    # If not buying FlexibleHVAC then the BAU (deadband) thermal loads must be met
    # TODO account for different tech efficiencies in following?

    if !isempty(p.techs.heating)
        @constraint(m, [ts in p.time_steps],
            !binFlexHVAC => { sum(m[Symbol("dvHeatingProduction"*_n)][t, "SpaceHeating", ts] for t in p.techs.heating) == p.s.flexible_hvac.bau_hvac.existing_boiler_kw_thermal[ts]
            }
        )
    end
    if !isempty(p.techs.cooling)
        @constraint(m, [ts in p.time_steps],
            !binFlexHVAC => { sum(m[Symbol("dvCoolingProduction"*_n)][t, ts] for t in p.techs.cooling) == p.s.flexible_hvac.bau_hvac.existing_chiller_kw_thermal[ts]
            }
        )
    end

    m[Symbol("binFlexHVAC"*_n)] = binFlexHVAC
    m[Symbol("dvTemperature"*_n)] = dvTemperature
    m[Symbol("dvComfortLimitViolationCost"*_n)] = dvComfortLimitViolationCost
    nothing
end


"""
    function add_flexible_hvac_constraints(m, p::REoptInputs{BAUScenario}; _n="")

For the BAU scenario we enforce the deadband control pattern using the values from BAU_HVAC.
"""
function add_flexible_hvac_constraints(m, p::REoptInputs{BAUScenario}; _n="") 

    # If not buying FlexibleHVAC then the BAU (deadband) thermal loads must be met
    # TODO account for different tech efficiencies in following?

    if !isempty(p.techs.heating)
        @constraint(m, [ts in p.time_steps],
            sum(m[Symbol("dvHeatingProduction"*_n)][t, "SpaceHeating", ts] for t in p.techs.heating) == 
            p.s.flexible_hvac.existing_boiler_kw_thermal[ts]
        )
    end
    if !isempty(p.techs.cooling)
        @constraint(m, [ts in p.time_steps],
            sum(m[Symbol("dvCoolingProduction"*_n)][t, ts] for t in p.techs.cooling) == 
            p.s.flexible_hvac.existing_chiller_kw_thermal[ts]
        )
    end

    m[Symbol("binFlexHVAC"*_n)] = 0
    m[Symbol("dvTemperature"*_n)] = p.s.flexible_hvac.temperatures
    m[Symbol("dvComfortLimitViolationCost"*_n)] = 0.0
    nothing
end
