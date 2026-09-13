# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

"""
    chp_names_with_fuel_switch(p)

Names of CHP techs configured for the long-term fuel switch dual-fuel mode (`fuel2_switch_start_year` set).
"""
function chp_names_with_fuel_switch(p)
    return [chp.name for chp in p.s.chps if !isnothing(chp.fuel2_switch_start_year)]
end

"""
    chp_names_with_capacity_limited_dual_fuel(p)

Names of CHP techs configured for the capacity-limited (rate- and/or volume-limited) dual-fuel mode
**with** a second fuel specified (i.e. fuel 2 tops up fuel 1 beyond its cap).
"""
function chp_names_with_capacity_limited_dual_fuel(p)
    return [chp.name for chp in p.s.chps if isnothing(chp.fuel2_switch_start_year) && !isnothing(chp.fuel2_type) &&
        chp_has_fuel_capacity_limit(chp)]
end

"""
    chp_names_with_capacity_limited_single_fuel(p)

Names of CHP techs with a fuel 1 rate/volume limit but **no** second fuel — i.e. the limit is simply
a hard cap on CHP's total fuel burn, with no dual-fuel blending.
"""
function chp_names_with_capacity_limited_single_fuel(p)
    return [chp.name for chp in p.s.chps if isnothing(chp.fuel2_switch_start_year) && isnothing(chp.fuel2_type) &&
        chp_has_fuel_capacity_limit(chp)]
end

function chp_has_fuel_capacity_limit(chp::CHP)
    return !isnothing(chp.fuel_max_period)
end

"""
    add_chp_fuel1_capacity_limit_constraints!(m, p, chp::CHP, t::String, var_symbol::Symbol)

Add the constraint(s) implied by `chp.fuel_max_period`/`chp.fuel_max_mmbtu_per_period` to the JuMP
variable `m[var_symbol][t, ts]` — either `dvFuelUsageFuel1` for the capacity-limited dual-fuel mode, or
the CHP's own `dvFuelUsage` for the capacity-limited single-fuel mode. No-op if `fuel_max_period` isn't
set.

`"hour"` is a genuine rate limit and must bound *every individual* time step, not a sum: since
`dvFuelUsage`/`dvFuelUsageFuel1` are energy consumed *during* that time step (already scaled by
`hours_per_time_step` in their defining constraint), the per-time-step cap for a `fuel_max_mmbtu_per_period`
MMBtu/hour rate is `fuel_max_mmbtu_per_period * KWH_PER_MMBTU * hours_per_time_step` — applying this to
a *sum* of several sub-hourly time steps (as `get_time_steps_by_period` groups them for "day"/"week"/
"month") would silently turn the rate limit into an hourly volume limit, letting CHP use an entire
hour's allowance within a single sub-hourly time step. `"day"`/`"week"`/`"month"` are genuine volume
limits: since those time steps' energy already sums correctly to the period's total regardless of
`time_steps_per_hour`, `get_time_steps_by_period`'s grouped sum is correct for them as-is.
"""
function add_chp_fuel1_capacity_limit_constraints!(m, p, chp::CHP, t::String, var_symbol::Symbol)
    isnothing(chp.fuel_max_period) && return nothing
    cap_kwh = chp.fuel_max_mmbtu_per_period * KWH_PER_MMBTU

    if chp.fuel_max_period == "hour"
        @constraint(m, [ts in p.time_steps], m[var_symbol][t, ts] <= cap_kwh * p.hours_per_time_step)
    else
        periods = get_time_steps_by_period(chp.fuel_max_period, p.s.electric_load.year; time_steps_per_hour=p.s.settings.time_steps_per_hour)
        for period in periods
            @constraint(m, sum(m[var_symbol][t, ts] for ts in period) <= cap_kwh)
        end
    end
    return nothing
end

"""
    chp_fuel2_pwf(p, chp::CHP)

Present worth factor for `chp`'s fuel 2 cost, over the full analysis period (used for the
capacity-limited dual-fuel modes, where fuel 1 and fuel 2 are both burned every year).
"""
function chp_fuel2_pwf(p, chp::CHP)
    escalation_rate = isnothing(chp.fuel2_cost_escalation_rate_fraction) ?
        p.s.financial.chp_fuel_cost_escalation_rate_fraction : chp.fuel2_cost_escalation_rate_fraction
    return annuity(p.s.financial.analysis_years, escalation_rate, p.s.financial.offtaker_discount_rate_fraction)
end

"""
    chp_fuel2_cost_per_kwh(p, chp::CHP)

`chp.fuel2_cost_per_mmbtu` converted to a \$/kWh time series over `p.time_steps`, mirroring how
`fuel_cost_per_kwh[chp.name]` is built for fuel 1 in `setup_chp_inputs`.
"""
function chp_fuel2_cost_per_kwh(p, chp::CHP)
    cost_per_kwh = chp.fuel2_cost_per_mmbtu ./ KWH_PER_MMBTU
    return per_hour_value_to_time_series(cost_per_kwh, p.s.settings.time_steps_per_hour, chp.name)
end

"""
    add_chp_dual_fuel_constraints(m, p; _n="")

Used by add_chp_constraints to add dispatch constraints and adjust `TotalCHPFuelCosts` for any CHP
configured with a dual-fuel input (`fuel2_type`, `fuel_max_period`/`fuel_max_mmbtu_per_period`,
and/or `fuel2_switch_start_year`). No-op if no CHP has any dual-fuel input set.

`add_chp_fuel_burn_constraints` (which runs before this function) already excludes these CHPs from the
default (single-fuel) `TotalCHPFuelCosts` sum, so this function only adds their contributions.
"""
function add_chp_dual_fuel_constraints(m, p; _n="")
    switch_chps = chp_names_with_fuel_switch(p)
    dual_fuel_chps = chp_names_with_capacity_limited_dual_fuel(p)
    single_fuel_capped_chps = chp_names_with_capacity_limited_single_fuel(p)

    if isempty(switch_chps) && isempty(dual_fuel_chps) && isempty(single_fuel_capped_chps)
        return nothing
    end

    add_chp_fuel_switch_costs(m, p, switch_chps; _n=_n)
    add_chp_capacity_limited_dual_fuel_constraints(m, p, dual_fuel_chps; _n=_n)
    add_chp_capacity_limited_single_fuel_constraints(m, p, single_fuel_capped_chps; _n=_n)
    return nothing
end

"""
    chp_fuel_switch_year_counts(p, chp::CHP)

For a fuel-switch CHP, return `(n_fuel1_years, n_fuel2_years)`: how many years within
`Financial.analysis_years` use fuel 1 (years 1..fuel2_switch_start_year-1) vs fuel 2
(years fuel2_switch_start_year..analysis_years). `n_fuel2_years` is 0 (fuel 2 never reached) if
`fuel2_switch_start_year > analysis_years`.
"""
function chp_fuel_switch_year_counts(p, chp::CHP)
    analysis_years = p.s.financial.analysis_years
    n_fuel1_years = min(chp.fuel2_switch_start_year - 1, analysis_years)
    n_fuel2_years = analysis_years - n_fuel1_years
    return n_fuel1_years, n_fuel2_years
end

"""
    add_chp_fuel_switch_costs(m, p, switch_chp_names; _n="")

For each CHP with `fuel2_switch_start_year` set, add its lifecycle fuel cost to `TotalCHPFuelCosts` using
fuel 1's price/escalation for years 1..(fuel2_switch_start_year - 1) and fuel 2's price/escalation for years
fuel2_switch_start_year..analysis_years, applied to the (year-1-repeating) `dvFuelUsage` dispatch.
"""
function add_chp_fuel_switch_costs(m, p, switch_chp_names; _n="")
    isempty(switch_chp_names) && return nothing
    discount_rate = p.s.financial.offtaker_discount_rate_fraction

    for t in switch_chp_names
        chp = get_chp_by_name(t, p.s.chps)
        n_fuel1_years, n_fuel2_years = chp_fuel_switch_year_counts(p, chp)
        if n_fuel2_years <= 0
            @warn "CHP $(t): fuel2_switch_start_year ($(chp.fuel2_switch_start_year)) is beyond Financial.analysis_years " *
                "($(p.s.financial.analysis_years)); fuel2_type will never be used and fuel_type will be used for the entire analysis period."
        end

        esc1 = isnothing(chp.fuel_cost_escalation_rate_fraction) ?
            p.s.financial.chp_fuel_cost_escalation_rate_fraction : chp.fuel_cost_escalation_rate_fraction
        esc2 = isnothing(chp.fuel2_cost_escalation_rate_fraction) ?
            p.s.financial.chp_fuel_cost_escalation_rate_fraction : chp.fuel2_cost_escalation_rate_fraction
        pwf_fuel1_partial, pwf_fuel2_partial = annuity_split_periods(n_fuel1_years, n_fuel2_years, esc1, esc2, discount_rate)
        fuel2_cost_per_kwh = n_fuel2_years <= 0 ? nothing : chp_fuel2_cost_per_kwh(p, chp)

        m[:TotalCHPFuelCosts] += @expression(m,
            pwf_fuel1_partial * sum(m[Symbol("dvFuelUsage"*_n)][t, ts] * p.fuel_cost_per_kwh[t][ts] for ts in p.time_steps) +
            (n_fuel2_years <= 0 ? 0.0 : pwf_fuel2_partial * sum(m[Symbol("dvFuelUsage"*_n)][t, ts] * fuel2_cost_per_kwh[ts] for ts in p.time_steps))
        )
    end
    return nothing
end

"""
    chp_fuel_switch_yr1_emissions_contributions(m, p, t::String, pollutant::String)

For a fuel-switch CHP `t`, return `(yr1_fuel1, yr1_fuel2)`: the year-1 emissions (lbs) that the CHP's
`dvFuelUsage` dispatch would produce if attributed entirely to fuel 1 vs entirely to fuel 2, for the
given `pollutant` ("CO2", "NOx", "SO2", or "PM25"). Used in emissions_constraints.jl to correct the
lifecycle emissions/cost roll-ups for the portion of the analysis period that uses fuel 2.
"""
function chp_fuel_switch_yr1_emissions_contributions(m, p, t::String, pollutant::String)
    chp = get_chp_by_name(t, p.s.chps)
    factor1 = getproperty(p, Symbol("tech_emissions_factors_$(pollutant)"))[t]
    factor2 = getproperty(chp, Symbol("fuel2_emissions_factor_lb_$(pollutant)_per_mmbtu")) / KWH_PER_MMBTU
    yr1_fuel1 = @expression(m, p.hours_per_time_step * sum(m[:dvFuelUsage][t, ts] * factor1 for ts in p.time_steps))
    yr1_fuel2 = @expression(m, p.hours_per_time_step * sum(m[:dvFuelUsage][t, ts] * factor2 for ts in p.time_steps))
    return yr1_fuel1, yr1_fuel2
end

"""
    add_chp_capacity_limited_dual_fuel_constraints(m, p, chp_names; _n="")

For each CHP with a fuel 1 rate/volume limit **and** `fuel2_type` set, split `dvFuelUsage` into
`dvFuelUsageFuel1` + `dvFuelUsageFuel2`, cap fuel 1's rate and/or volume, and add each fuel's cost to
`TotalCHPFuelCosts`. No tier-ordering (big-M/binary) logic is needed: since fuel 1 is capped and the
model minimizes cost, the LP naturally fills the (typically cheaper) capped fuel 1 first.
"""
function add_chp_capacity_limited_dual_fuel_constraints(m, p, chp_names; _n="")
    isempty(chp_names) && return nothing

    dv1 = "dvFuelUsageFuel1"*_n
    dv2 = "dvFuelUsageFuel2"*_n
    m[Symbol(dv1)] = @variable(m, [chp_names, p.time_steps], base_name=dv1, lower_bound=0)
    m[Symbol(dv2)] = @variable(m, [chp_names, p.time_steps], base_name=dv2, lower_bound=0)

    @constraint(m, [t in chp_names, ts in p.time_steps],
        m[Symbol(dv1)][t, ts] + m[Symbol(dv2)][t, ts] == m[Symbol("dvFuelUsage"*_n)][t, ts]
    )

    for t in chp_names
        chp = get_chp_by_name(t, p.s.chps)

        add_chp_fuel1_capacity_limit_constraints!(m, p, chp, t, Symbol(dv1))

        pwf_fuel2 = chp_fuel2_pwf(p, chp)
        fuel2_cost_per_kwh = chp_fuel2_cost_per_kwh(p, chp)
        m[:TotalCHPFuelCosts] += @expression(m,
            p.pwf_fuel[t] * sum(m[Symbol(dv1)][t, ts] * p.fuel_cost_per_kwh[t][ts] for ts in p.time_steps) +
            pwf_fuel2 * sum(m[Symbol(dv2)][t, ts] * fuel2_cost_per_kwh[ts] for ts in p.time_steps)
        )
    end
    return nothing
end

"""
    chp_fuel_cost_breakdown(m, p, chp_name::String)

Return a `NamedTuple` `(yr1_fuel1, yr1_fuel2, yr1_equivalent_fuel2, lifecycle_fuel1, lifecycle_fuel2)`
of \$ fuel costs for the (solved) CHP `chp_name`, correctly split across fuel 1 and fuel 2 for both
dual-fuel modes. `yr1_*` are the actual year-1 dollar costs (for the long-term fuel-switch mode,
`yr1_fuel2` is always `0.0` since fuel 2 is never used in year 1). `yr1_equivalent_fuel2` is the basis
used to escalate fuel 2's cost in `chp_annual_fuel_cost_nominal_series` (for the fuel-switch mode this
is fuel 2's year-1-equivalent price applied to the year-1-repeating dispatch — not a real year-1 cost,
purely the present-worth-factor/escalation multiplicand from `add_chp_fuel_switch_costs`; for the
capacity-limited dual-fuel mode it equals `yr1_fuel2`, a real year-1 cost). For a CHP with no dual-fuel
input set, all `*_fuel2` terms are `0.0` and `*_fuel1` equal the combined (single-fuel) fuel cost. Used
by `src/results/chp.jl` and `src/results/proforma.jl`; note that neither results file exposes a
separate "fuel 1" result field — the existing combined `annual_fuel_consumption_mmbtu`/
`year_one_fuel_cost_before_tax`/`lifecycle_fuel_cost_after_tax` fields already equal fuel 1's value in
the single-fuel case, and fuel 1's share of a dual-fuel CHP is simply that combined total minus fuel 2's
(newly added) result field, so a redundant "fuel 1" field isn't exposed.
"""
function chp_fuel_cost_breakdown(m, p, chp_name::String)
    chp = get_chp_by_name(chp_name, p.s.chps)

    if !isnothing(chp.fuel2_switch_start_year)
        n_fuel1_years, n_fuel2_years = chp_fuel_switch_year_counts(p, chp)
        esc1 = isnothing(chp.fuel_cost_escalation_rate_fraction) ?
            p.s.financial.chp_fuel_cost_escalation_rate_fraction : chp.fuel_cost_escalation_rate_fraction
        esc2 = isnothing(chp.fuel2_cost_escalation_rate_fraction) ?
            p.s.financial.chp_fuel_cost_escalation_rate_fraction : chp.fuel2_cost_escalation_rate_fraction
        pwf1, pwf2 = annuity_split_periods(n_fuel1_years, n_fuel2_years, esc1, esc2, p.s.financial.offtaker_discount_rate_fraction)

        yr1_fuel1 = sum(value(m[:dvFuelUsage][chp_name, ts]) * p.fuel_cost_per_kwh[chp_name][ts] for ts in p.time_steps)
        lifecycle_fuel1 = yr1_fuel1 * pwf1
        if n_fuel2_years <= 0
            yr1_equivalent_fuel2, lifecycle_fuel2 = 0.0, 0.0
        else
            fuel2_cost_per_kwh = chp_fuel2_cost_per_kwh(p, chp)
            yr1_equivalent_fuel2 = sum(value(m[:dvFuelUsage][chp_name, ts]) * fuel2_cost_per_kwh[ts] for ts in p.time_steps)
            lifecycle_fuel2 = yr1_equivalent_fuel2 * pwf2
        end
        return (yr1_fuel1=yr1_fuel1, yr1_fuel2=0.0, yr1_equivalent_fuel2=yr1_equivalent_fuel2,
            lifecycle_fuel1=lifecycle_fuel1, lifecycle_fuel2=lifecycle_fuel2)

    elseif !isnothing(chp.fuel2_type) && chp_has_fuel_capacity_limit(chp)
        yr1_fuel1 = sum(value(m[:dvFuelUsageFuel1][chp_name, ts]) * p.fuel_cost_per_kwh[chp_name][ts] for ts in p.time_steps)
        lifecycle_fuel1 = yr1_fuel1 * p.pwf_fuel[chp_name]
        fuel2_cost_per_kwh = chp_fuel2_cost_per_kwh(p, chp)
        yr1_fuel2 = sum(value(m[:dvFuelUsageFuel2][chp_name, ts]) * fuel2_cost_per_kwh[ts] for ts in p.time_steps)
        lifecycle_fuel2 = yr1_fuel2 * chp_fuel2_pwf(p, chp)
        return (yr1_fuel1=yr1_fuel1, yr1_fuel2=yr1_fuel2, yr1_equivalent_fuel2=yr1_fuel2,
            lifecycle_fuel1=lifecycle_fuel1, lifecycle_fuel2=lifecycle_fuel2)

    else
        yr1_fuel1 = sum(value(m[:dvFuelUsage][chp_name, ts]) * p.fuel_cost_per_kwh[chp_name][ts] for ts in p.time_steps)
        lifecycle_fuel1 = yr1_fuel1 * p.pwf_fuel[chp_name]
        return (yr1_fuel1=yr1_fuel1, yr1_fuel2=0.0, yr1_equivalent_fuel2=0.0,
            lifecycle_fuel1=lifecycle_fuel1, lifecycle_fuel2=0.0)
    end
end

"""
    chp_annual_fuel_cost_nominal_series(p, chp::CHP, yr1_fuel1::Real, yr1_equivalent_fuel2::Real)

Nominal (undiscounted) annual CHP fuel cost for each year 1..`Financial.analysis_years`, escalating
fuel 1 and fuel 2 at their own escalation rates. For the long-term fuel-switch mode, only fuel 1's term
applies for years 1..(fuel2_switch_start_year-1) and only fuel 2's term applies from fuel2_switch_start_year on (fuel
2 escalates from its own start year, per `add_chp_fuel_switch_costs`); otherwise (capacity-limited dual
fuel, or no dual-fuel input) both terms apply every year. Used to build the pro forma cash flow series
in `src/results/proforma.jl`, consistent with the lifecycle cost calculated in
`add_chp_fuel_switch_costs`/`add_chp_capacity_limited_dual_fuel_constraints`/`chp_fuel_cost_breakdown`.
"""
function chp_annual_fuel_cost_nominal_series(p, chp::CHP, yr1_fuel1::Real, yr1_equivalent_fuel2::Real)
    years = p.s.financial.analysis_years
    esc1 = isnothing(chp.fuel_cost_escalation_rate_fraction) ?
        p.s.financial.chp_fuel_cost_escalation_rate_fraction : chp.fuel_cost_escalation_rate_fraction
    esc2 = isnothing(chp.fuel2_cost_escalation_rate_fraction) ?
        p.s.financial.chp_fuel_cost_escalation_rate_fraction : chp.fuel2_cost_escalation_rate_fraction

    if !isnothing(chp.fuel2_switch_start_year)
        n_fuel1_years, n_fuel2_years = chp_fuel_switch_year_counts(p, chp)
        return [
            yr <= n_fuel1_years ?
                yr1_fuel1 * (1 + esc1)^yr :
                yr1_equivalent_fuel2 * (1 + esc2)^(yr - n_fuel1_years)
            for yr in 1:years
        ]
    else
        return [yr1_fuel1 * (1 + esc1)^yr + yr1_equivalent_fuel2 * (1 + esc2)^yr for yr in 1:years]
    end
end

"""
    add_chp_capacity_limited_single_fuel_constraints(m, p, chp_names; _n="")

For each CHP with a fuel 1 rate/volume limit and **no** `fuel2_type`, simply cap `dvFuelUsage` (no
blending, no cost/emissions changes — the limit constrains CHP's total fuel burn).
"""
function add_chp_capacity_limited_single_fuel_constraints(m, p, chp_names; _n="")
    isempty(chp_names) && return nothing

    for t in chp_names
        chp = get_chp_by_name(t, p.s.chps)
        add_chp_fuel1_capacity_limit_constraints!(m, p, chp, t, Symbol("dvFuelUsage"*_n))
    end
    return nothing
end
