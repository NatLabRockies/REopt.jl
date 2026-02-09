# Examples
To use REopt you will need to have a solver installed. This just requires adding one of the compatible open-source solver Julia packages to your Julia environment, along with the JuMP.jl optimization modeling package. If you want to use a commercial solver which requires a licenese, installation of that solver is required external to the Julia environment.

REopt.jl has been tested with HiGHS (preferred open-source), Xpress (commercial), Cbc, SCIP, and CPLEX (commercial) solvers, but it should work with other Linear Progam solvers (for PV and Storage scenarios) or Mixed Integer Linear Program solvers (for scenarios with outages and/or Generators).

## Basic
A REopt optimization can be run with three lines: 
```julia
using REopt, JuMP, HiGHS

m = Model(HiGHS.Optimizer)
results = run_reopt(m, "pv_storage.json")
```

The input file, in this case `pv_storage.json`, contains the set of user-defined inputs. For more on the inputs .json file, see the [REopt Inputs](@ref) section and find examples at [test/scenarios](https://github.com/NatLabRockies/REopt/blob/master/test/scenarios). For more examples of how to run REopt, see [`runtests.jl`](https://github.com/NatLabRockies/REopt.jl/blob/master/test/runtests.jl). To adjust settings such as optimality tolerance and logging, see more about relevant `Model()` arguments here: [open source solver setups](https://github.com/NatLabRockies/REopt_API/blob/master/julia_src/os_solvers.jl).

To compare the optimized case to a "Business-as-usual" case (with existing techs or no techs), you can run the [BAUScenario](@ref) scenario in parallel by providing two `JuMP.Model`s like so:
```julia
m1 = Model(HiGHS.Optimizer)
m2 = Model(HiGHS.Optimizer)
results = run_reopt([m1,m2], "pv_storage.json")
```
When the [BAUScenario](@ref) is included as shown above, the outputs will include comparative results such as the net present value and emissions reductions of the optimal system as compared to the BAU Scenario.

!!! note "BAU Scenario" 
    Note that while two JuMP models are needed to run the `BAU` and optimized cases in parallel, only a single input dict is used. The [BAUScenario](@ref) will be automatically created based on the input dict. 


## Advanced

### Modifying the mathematical model
Using the `build_reopt!` method and `JuMP` methods one can modify the REopt model before optimizing.
In the following example we add a cost for curtailed PV power.
```julia
using HiGHS
using JuMP
using REopt

m = JuMP.Model(HiGHS.Optimizer)

p = REoptInputs("pv_storage.json");

build_reopt!(m, p)

#= 
replace the original objective, which is to Min the Costs,
with the Costs + 100 * (total curtailed PV power)
=#  
JuMP.@objective(m, Min, m[:Costs] + 100 * sum(m[:dvCurtail]["PV", ts] for ts in p.time_steps));

JuMP.optimize!(m)  # normally this command is called in run_reopt

results = reopt_results(m, p)
```
One can also add variables and constraints to the model before optimizing using the JuMP commands.

!!! note
    The `JuMP.` prefixes are not necessary. We include them in the example to show which commands come from JuMP.
