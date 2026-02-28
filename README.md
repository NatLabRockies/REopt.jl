# REopt® Julia package
REopt.jl is the core module of the [REopt® techno-economic decision support platform](https://www.nlr.gov/reopt/), developed by the National Laboratory of the Rockies (NLR). REopt optimizes the sizing and dispatch of energy systems for buildings, campuses, communities, microgrids, and more. REopt identifies the cost-optimal mix of generation, storage, and heating and cooling technologies to meet cost savings, resilience, emissions reductions, and energy performance goals.

REopt.jl (this package) is used within the publicly-accessible and open-source [REopt API](https://github.com/NatLabRockies/REopt_API), and the publicly-available [REopt Web Tool](https://reopt.nlr.gov/tool) calls the REopt API.

For more information about REopt.jl please see the Julia documentation:
<!-- [![](https://img.shields.io/badge/docs-stable-blue.svg)](https://natlabrockies.github.io/REopt.jl/stable) -->
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://natlabrockies.github.io/REopt.jl/dev)


## Quick Start
Evaluating simple `PV` and `ElectricStorage` scenarios requires a linear program solver. Evaluating net-metering, `Generator`, multiple outages, or other more complex scenario makes the problem mixed-integer linear, and thus requires a MILP solver. See https://jump.dev/JuMP.jl/stable/installation/ for a list of solvers. The REopt package has been tested with , `HiGHS`, `Cbc`, `SCIP`, `Xpress` (commercial), and `CPLEX` (commercial).

### Example
```
using REopt, JuMP, HiGHS

m = Model(HiGHS.Optimizer)
results = run_reopt(m, "pv_storage.json")
```
See the `test/scenarios` directory for examples of `scenario.json`.

For more details, including installation instructions, see the [documentation](https://natlabrockies.github.io/REopt.jl/dev).
