# The REoptInputs structure
The REoptInputs structure uses the [Scenario](@ref) to build all of the data necessary to construct the JuMP mathematical model.

## REoptInputs
```@docs
REoptInputs
REoptInputs(fp::String)
REoptInputs(s::REopt.AbstractScenario)
```

## Design Concepts for REoptInputs
At a high level the REoptInputs constructor does the following tasks:
- build index sets for the JuMP model decision variables,
- create maps from one set to another set,
- and generate coefficient arrays necessary for model constraints.

#### Index Sets
There are a few `String[]` that are built by REoptInputs that are then used as index sets in the model constraints.
The primary index set is the `techs.all` array of strings, which contains all the technolgy names that are being modeled.
With the `techs.all` array we can easily apply a constraint over all technolgies. For example:
```julia
@constraint(m, [t in p.techs.all],
    m[Symbol("dvSize"*_n)][t] <= p.max_sizes[t]
)
```
where `p` is the `REoptInputs` struct. There are a couple things to note from this last example:
1. The decision variable `dvSize` is accessed in the JuMP.Model `m` using the `Symbol` notation so that this constraint can be used in the multi-node case in addition to the single node case. The `_n` input value is an empty string by default and in the case of a multi-node model the `_n` string will be set by the `Site.node` integer. For example, if `Site.node` is `3` then `_n` is "_3".
2. The `p.max_sizes` array is also indexed on `p.techs.all`. The `max_sizes` is built in the REoptInputs constructor by using all the technologies in the `Scenario` that have `max_kw` values greater than zero.

Besides the `techs.all` array the are many sub-sets, such as `techs.pv`, `techs.gen`, `techs.elec`, `p.techs.segmented`, `techs.no_curtail`, that allow us to apply constraints to those sets. For example:
```julia
for t in p.techs.no_curtail
    for ts in p.time_steps
        fix(m[Symbol("dvCurtail"*_n)][t, ts] , 0.0, force=true)
    end
end
```

#### Set maps
The set maps are best explained with an example. The `techs_by_exportbin` map uses each technology'sattributes (eg. `PV`) to map each technology to which export bins that technology can access. The export bins include:
1. `:NEM` (Net Energy Metering)
2. `:WHL` (Wholesale)
3. `:EXC` (Excess, beyond NEM)
The bins that a technology can access are determined by the technologies attributes `can_net_meter`, `can_wholesale`, and `can_export_beyond_nem_limit`. So if `PV.can_net_meter = true`, `Wind.can_net_meter = true` and all the other attributes are `false` then the `techs_by_exportbin` will only have one non-empty key:
```julia
techs_by_exportbin = Dict(
    :NEM => ["PV", "Wind"],
    :WHL => [],
    :EXC => []
)
```
A use-case example for the `techs_by_exportbin` map is defining the net metering benefit:
```julia
NEM_benefit = @expression(m, p.pwf_e * p.hours_per_time_step *
    sum( sum(p.s.electric_tariff.export_rates[:NEM][ts] * m[Symbol("dvProductionToGrid"*_n)][t, :NEM, ts] 
        for t in p.techs_by_exportbin[:NEM]) for ts in p.time_steps)
)
```
Other set maps include: `export_bins_by_tech` and `n_segs_by_tech`. The latter tells how many cost curve segments each technology has.

#### Coefficient Arrays
The JuMP model costs are formulated in net present value terms, accounting for all benefits (production, capacity, and investment incentives) and the total cost over the `analysis_period`. The `REoptInputs` constructor translates the raw input parameters, such as the operations and maintenance costs, into present value terms using the provided discount rate. For example, the `pwf_e` is the present worth factor for electricity that accounts for the `elec_cost_escalation_rate_fraction`, the `analysis_period`, and the `offtaker_discount_rate_fraction`. Note that tax benefits are applied directly in the JuMP model for clarity on which costs are tax-deductible and which are not.

Besides econimic parameters, the `REoptInputs` constructor also puts together the important `production_factor` array. The `production_factor` array is simple for continuously variable generators (such as the `Generator`), for which the `production_factor` is 1 in all time steps. However, for variable generators (such as `Wind` and `PV`) the `production_factor` varies by time step. If the user does not provide the `PV` production factor, for example, then the `REoptInputs` constructor uses the PVWatts API to download the location specific `PV` production factor. `REoptInputs` also accounts for the `PV.degradation_fraction` in building the `production_factor` array.