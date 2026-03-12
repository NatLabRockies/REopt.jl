# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`FlexibleHVAC` results keys:
- `purchased` 
- `temperatures_degC_node_by_time`
- `upgrade_cost`
"""
function add_flexible_hvac_results(m::JuMP.AbstractModel, p::REoptInputs{Scenario}, d::Dict; _n="")
    r = Dict{String, Any}()
    binFlexHVAC = value(m[:binFlexHVAC]) > 0.5 ? 1.0 : 0.0
    r["purchased"] = string(Bool(binFlexHVAC))
    r["temperatures_degC_node_by_time"] = value.(m[Symbol("dvTemperature"*_n)]).data
    r["upgrade_cost"] = Int(binFlexHVAC) * p.s.flexible_hvac.installed_cost

    if binFlexHVAC ≈ 1.0
        if any(value.(m[:lower_comfort_slack]) .>= 1.0) || any(value.(m[:upper_comfort_slack]) .>= 1.0)
            @warn "The comfort limits were violated by at least one degree Celcius to keep the problem feasible."
        end
    end

    d["FlexibleHVAC"] = r
	nothing
end

function add_flexible_hvac_results(m::JuMP.AbstractModel, p::REoptInputs{BAUScenario}, d::Dict; _n="")
    r = Dict{String, Any}()

    r["temperatures_degC_node_by_time"] = m[Symbol("dvTemperature"*_n)]

    d["FlexibleHVAC"] = r
	nothing
end