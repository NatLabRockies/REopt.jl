# REopt.jl
REopt.jl is the core module of the [REopt® techno-economic decision support platform](https://www.nlr.gov/reopt/), developed by the National Laboratory of the Rockies (NLR). REopt optimizes the sizing and dispatch of integrated energy systems for buildings, campuses, communities, microgrids, and more. REopt identifies the cost-optimal mix of generation, storage, and heating and cooling technologies to meet cost savings, resilience, emissions reductions, and energy performance goals. The open-source REopt.jl code is available on GitHub: https://github.com/NatLabRockies/REopt.jl. 

!!! note
    This REopt.jl package is used as the core model of the [REopt API](https://github.com/NatLabRockies/REopt_API) and the [REopt Web Tool](https://reopt.nlr.gov/tool). This package contains additional functionality and flexibility to run locally and customize.

## Installing
REopt evaluations for all system types except GHP (see below) can be performed using the following installation instructions from the package manager mode (`]`) of the Julia REPL:
```sh
(active_env) pkg> add REopt JuMP HiGHS
```

### Add NLR developer API key for PV, CST, and Wind
If you don't have an NLR developer network API key, [sign up here on https://developer.nrel.gov to get one (free)](https://developer.nrel.gov/signup); this is required to load PV and Wind resource profiles from PVWatts and the Wind Toolkit APIs from within REopt.jl.
Assign your API key to the expected environment variable:
```julia
ENV["NREL_DEVELOPER_API_KEY"]="your API key"
```
before running PV or Wind scenarios, and also assign your email to the expected environment variable as well before running CST scenarios: 
```julia
ENV["NREL_DEVELOPER_EMAIL"]="your contact email"
```

### Additional package loading for GHP
GHP evaluations must load in the [`GhpGhx.jl`](https://github.com/NatLabRockies/GhpGhx.jl) package separately because it has a more [restrictive license](https://github.com/NatLabRockies/GhpGhx.jl/blob/main/LICENSE.md) and is not a registered Julia package.

Install gcc via homebrew (if running on a Mac).

Add the GhpGhx.jl package to the project's dependencies from the package manager (`]`):
```sh
(active_env) pkg> add "https://github.com/NatLabRockies/GhpGhx.jl"
```

Load in the package from the script where `run_reopt()` is called:
```julia
using GhpGhx
```
