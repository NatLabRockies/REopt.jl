# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.


function add_degradation_variables(m, p)
    days = 1:365*p.s.financial.analysis_years
    @variable(m, Eavg[days] >= 0)
    @variable(m, Eplus_sum[days] >= 0)
    @variable(m, Eminus_sum[days] >= 0)
    @variable(m, EFC[days] >= 0)
    @variable(m, SOH[days])
end


function constrain_degradation_variables(m, p; b="ElectricStorage")
    days = 1:365*p.s.financial.analysis_years
    ts_per_day = 24 / p.hours_per_time_step
    ts_per_year = ts_per_day * 365
    ts0 = Dict()
    tsF = Dict()
    for d in days
        ts0[d] = Int((ts_per_day * (d - 1) + 1) % ts_per_year)
        tsF[d] = Int(ts_per_day * d % ts_per_year)
        if tsF[d] == 0
            tsF[d] = Int(ts_per_day * 365)
        end
    end
    @constraint(m, [d in days],
        m[:Eavg][d] == 1/ts_per_day * sum(m[:dvStoredEnergy][b, ts] for ts in ts0[d]:tsF[d])
    )
    @constraint(m, [d in days],
        m[:Eplus_sum][d] == 
            p.hours_per_time_step * (
                sum(m[:dvProductionToStorage][b, t, ts] for t in p.techs.elec, ts in ts0[d]:tsF[d]) 
                + sum(m[:dvGridToStorage][b, ts] for ts in ts0[d]:tsF[d])
            )
    )
    @constraint(m, [d in days],
        m[:Eminus_sum][d] == p.hours_per_time_step * sum(m[:dvDischargeFromStorage][b, ts] for ts in ts0[d]:tsF[d])
    )
    @constraint(m, [d in days],
        m[:EFC][d] == (m[:Eplus_sum][d] + m[:Eminus_sum][d]) / 2
    )
end


"""
    add_degradation(m, p; b="ElectricStorage")

NOTE the average SOC and EFC variables are in absolute units. For example, the SOH variable starts 
    at the battery capacity in kWh.
"""
function add_degradation(m, p; b="ElectricStorage")
    
    # Indices
    days = 1:365*p.s.financial.analysis_years
    months = 1:p.s.financial.analysis_years*12

    strategy = p.s.storage.attr[b].degradation.maintenance_strategy

    if isempty(p.s.storage.attr[b].degradation.maintenance_cost_per_kwh)
        # Correctly account for discount rate and install cost declination rate for days over analysis period
        function pwf_bess_replacements(day::Int)
            (1-p.s.storage.attr[b].degradation.installed_cost_per_kwh_declination_rate)^(day/365) / 
            (1+p.s.financial.owner_discount_rate_fraction)^(day/365)
        end
        p.s.storage.attr[b].degradation.maintenance_cost_per_kwh = [ 
            p.s.storage.attr[b].installed_cost_per_kwh * pwf_bess_replacements(d) for d in days[1:end-1]
        ]
    end

    # Under augmentation scenario, each day's battery augmentation cost is calculated using day-1 value from maintenance_cost_per_kwh vector
    # Therefore, on last day, day-1's maintenance cost is utilized.
    if length(p.s.storage.attr[b].degradation.maintenance_cost_per_kwh) != length(days) - 1
        throw(@error("The degradation maintenance_cost_per_kwh must have a length of $(length(days)-1)."))
    end

    add_degradation_variables(m, p)
    constrain_degradation_variables(m, p, b=b)

    @constraint(m, [d in 2:days[end]],
        m[:SOH][d] == m[:SOH][d-1] - p.hours_per_time_step * (
            p.s.storage.attr[b].degradation.calendar_fade_coefficient * 
            p.s.storage.attr[b].degradation.time_exponent * 
            m[:Eavg][d-1] * d^(p.s.storage.attr[b].degradation.time_exponent-1) + 
            p.s.storage.attr[b].degradation.cycle_fade_coefficient * m[:EFC][d-1]
        )
    )
    # NOTE SOH can be negative

    @constraint(m, m[:SOH][1] == m[:dvStorageEnergy][b])
    # NOTE SOH is _not_ normalized, and has units of kWh

    if strategy == "replacement"
        #=
        When the battery degrades to 80% of purchased capacity it is replaced.
        Multiple replacements could be necessary within the analysis period.
        (The SOH is calculated for the analysis period, but not for multiple batteries.)
        So we construct a cost as a function of months that accounts for the number of replacements.
        (We use months instead of days to reduce the number of integer variables required).

        The replacment cost in a given month is:
        1. the maintenance_cost_per_kwh in (approximately) the 15th day of the month multiplied with
        2. the number of replacements required given the first month that the battery must be replaced.
        The number of months is analysis_years * 12.
        The first month that the battery is replaced is determined by d_0p8, which is the integer 
        number of days that the SOH is at least 80% of the purchased capacity.
        We define a binary for each month and only allow one month to be chosen.

            # maintenance_cost_per_kwh must have length == length(days) - 1, i.e. starts on day 2
        
        number of replacments as function of d_0p8
         ^
         |
        4-    ------
         |
        3-          -------
         |
        2-                 -----
         |
        1-                      -------------------
         |
         ------|----|------|----|-----------------|->  d_0p8
              N/5  N/4    N/3  N/2                N = 365*analysis_years
        
        The above curve is multiplied by the maintenance_cost_per_kwh to create the cost coefficients
        =#

        @warn "Adding binary decision variables for 
        ElectricStorage.degradation.maintenance_strategy = \"replacement\". 
        Some solvers are slow with integers."

        @variable(m, binSOHIndicator[months], Bin) # track SOH levels, should be 1 if SOH >= 80%, 0 otherwise
        @variable(m, binSOHIndicatorChange[months], Bin) # track which month SOH indicator drops to < 80%
        @variable(m, 0 <= dvSOHChangeTimesEnergy[months]) # track the kwh to be replaced in a replacement month

        # the big M
        if p.s.storage.attr[b].max_kwh == 1.0e6 || p.s.storage.attr[b].max_kwh == 0
            # Under default max_kwh (i.e. not modeling large batteries) or max_kwh = 0
            bigM_StorageEnergy = 24*maximum(p.s.electric_load.loads_kw)
        else
            # Select the larger value of maximum electric load or provided max_kwh size.
            bigM_StorageEnergy = max(24*maximum(p.s.electric_load.loads_kw), p.s.storage.attr[b].max_kwh)
        end

        # HEALTHY: if binSOHIndicator is 1, then SOH >= 80%. If binSOHIndicator is 0 and SOH >= very negative number
        @constraint(m, [mth in months], m[:SOH][Int(round(30.4167*mth))] >= 0.8*m[:dvStorageEnergy][b] - bigM_StorageEnergy * (1-binSOHIndicator[mth]))

        # UNHEALTHY: if binSOHIndicator is 1, then SOH <= large number. If binSOHIndicator is 0 and SOH <= 80%
        @constraint(m, [mth in months], m[:SOH][Int(round(30.4167*mth))] <= 0.8*m[:dvStorageEnergy][b] + bigM_StorageEnergy * (binSOHIndicator[mth]))

        # binSOHIndicatorChange[mth] = binSOHIndicator[mth-1] - binSOHIndicator[mth].
        # If replacement month is x, then binSOHIndicatorChange[x] = 1. All other binSOHIndicatorChange values will be 0s (either 1-1 or 0-0)
        @constraint(m, m[:binSOHIndicatorChange][1] == 1 - m[:binSOHIndicator][1])
        @constraint(m, [mth in 2:months[end]], m[:binSOHIndicatorChange][mth] == m[:binSOHIndicator][mth-1] - m[:binSOHIndicator][mth])

        @expression(m, months_to_first_replacement, sum(m[:binSOHIndicator][mth] for mth in months))

        # -> linearize the product of binSOHIndicatorChange & m[:dvStorageEnergy][b]
        @constraint(m, [mth in months], m[:dvSOHChangeTimesEnergy][mth] >= m[:dvStorageEnergy][b] - bigM_StorageEnergy * (1 - m[:binSOHIndicatorChange][mth]))
        @constraint(m, [mth in months], m[:dvSOHChangeTimesEnergy][mth] <= m[:dvStorageEnergy][b] + bigM_StorageEnergy * (1 - m[:binSOHIndicatorChange][mth]))
        @constraint(m, [mth in months], m[:dvSOHChangeTimesEnergy][mth] <= bigM_StorageEnergy * m[:binSOHIndicatorChange][mth])

        replacement_costs = zeros(length(months))  # initialize cost coefficients
        residual_values = zeros(length(months))  # initialize cost coefficients for residual_value
        N = 365*p.s.financial.analysis_years # number of days

        for mth in months
            day = Int(round((mth-1)*30.4167 + 15, digits=0))
            batt_replace_count = Int(ceil(N/day - 1)) # number of battery replacements in analysis period if they periodically happened on "day"
            maint_cost = sum(p.s.storage.attr[b].degradation.maintenance_cost_per_kwh[day*i] for i in 1:batt_replace_count)
            replacement_costs[mth] = maint_cost

            residual_factor = 1 - (p.s.financial.analysis_years*12/mth - floor(p.s.financial.analysis_years*12/mth))
            residual_value = p.s.storage.attr[b].degradation.maintenance_cost_per_kwh[end]*residual_factor
            residual_values[mth] = residual_value
        end

        # create replacement cost expression for objective
        @expression(m, degr_cost, sum(replacement_costs[mth] * m[:dvSOHChangeTimesEnergy][mth] for mth in months))

        # create residual value expression for objective
        @expression(m, residual_value, sum(residual_values[mth] * m[:dvSOHChangeTimesEnergy][mth] for mth in months))

    elseif strategy == "augmentation"

        @expression(m, degr_cost,
            sum(
                p.s.storage.attr[b].degradation.maintenance_cost_per_kwh[d-1] * (m[:SOH][d-1] - m[:SOH][d])
                for d in days[2:end]
            )
        )
        
        # No lifetime based residual value assigned to battery under the augmentation strategy
        @expression(m, residual_value, 0.0)
    else
        throw(@error("Battery maintenance strategy $strategy is not supported. Choose from augmentation and replacement."))
    end
    
    # NOTE adding to Costs expression does not modify the objective function
 end
# TODO raise error for multisite with degradation
