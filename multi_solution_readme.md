# Summary
The multiple solutions functionality runs REopt (like `run_reopt`) multiple times to look at the
sensitivity of a number of key results, such as Net Present Value (NPV) and capital cost, on
sizing variations around the optimal technology sizes. The `run_reopt_multi_solutions()` function first runs the optimal case to
identify the cost-effective technologies recommended by REopt. It then re-runs a number of times with user-specified scaling factors applied to each of the cost-optimal techs, and it forces those DER sizes into the solution.

## Resilience evaluation option
If resilience metrics and an estimate of the value of avoided lost load are desired, modify the `resilience` keyword argument to `resilience=true`. Additionally, the user must input the `outage_start_hour` and the `outage_duration_hours` keyword arguments to the function to evaluate the value of avoided lost load for that specific outage period. The `simulate_outages()` function gets evaluated after running REopt to calculate the number of hours the DERs serve the critical load for all possible outage start times of the year to get an average, and it outputs the specified outage from the user inputs.

Note, this resilience evaluation is not considering the user-specified outage for sizing the DERs in the model. The evaluation first runs REopt to get DER size recommendations based on economics. Then the resilience benefit of the recommended DERs are evaluated using a post-processing algorithm from `simulate_outages()` for dispatching the DERs during outages to serve the critical load (determined by `ElectricLoad.critical_load_fraction`). Therefore, the DERs may not serve any or all of the critical load during the user specified outage. The calculations describe how much of the critical load is served compared to not having DERs (where none of the critical load is served), and it estimates the value of avoided lost load based on the user input `Financial.value_of_lost_load`.

The `resilience` key in the results summary gets populated with the following information:
```
    "Input outage duration (hours)"  # The user-input outage duration
    "Average outage hours of load served (hours)"  # Average number of hours of critical load served for all (8760) start times of the year
    "Average outage load served (kWh)"  # The average amount of critical load served for all (8760) start times of the year
    "Average outage cost savings per year"  # The average yearly cost savings for all outage start times of the year 
    "Specified outage hours of load served"  # The number of hours of critical load served for the user-input outage duration
    "Specified outage load served with DERs (kWh)"  # The critical load served for the user-input outage start time
    "Specified outage cost savings per year with DERs"  # The yearly savings from serving load during the user-input outage start time
    "Specified outage cost savings as percent of annual utility bill"  # The value of avoided lost load as a percent of the annual electric bill
```

## Incentives
Incentives are pulled from the data/incentives/DSIRE.db database for the specified kwarg `state` (e.g. = "CO" for Colorado) in the `run_reopt_multi_solutions()` function. 

**The user must now input a kwarg for `state` into the `run_reopt_multi_solutions()` to evaluate the state incentives.

Incentives are filtered by those that apply to the entire state and have an end date of later than today or Null. The availability of Net metering is found and applied, as well as the following three incentives to choose from:
1. Capacity-based rebate ($/kW)
2. Production incentive ($/kWh)
3. Percent-of-cost based state tax credit (% of installed cost)
REopt is run with any of these three incentive options which are avaialable, and the one that produces the lowest lifecycle cost of energy is chosen. All of the solutions are then run with the best incentives option.

If REopt identified a state incentive to use, the `incentive_used` key at the top level of the `results_summary` will contain the `best_incentive_program_name` (`None` if none where found) and if net metering was enabled from the DSIRE database from `net_metering_from_dsire`. The user should verify that that incentive program is available and what the net metering capacity (kW) limit is. Because the net meter capacity limit is not retrieved from the DSIRE database, an arbitrarily large number is used for the net metering limit if net metering is available.

# Example use-case for multi-solutions
#### Specify path to input file:
`fp = "scenarios/eaton_multi.json"`

#### Specify fractions/ratios of size relative to the optimal size to run. The other techs will all be forced to the optimal size for each run. If you run with an empty array for size_scale, it will just run the optimal scenario.
`size_scale = [0.8, 1.2]`
#### Need to know the maximum number of JuMP models to create, so first identify the number of technologies considered. So for the eaton_multi.json scenario with PV and Battery (ElectricStorage):
`n_techs = 2`
#### Incentives scenarios, max 3 for 1. capacity-based, 2. production-based, and 3. percent cost based incentives to choose from
`n_incentives_scenarios = 3`
#### This equation uses 2 for optimal+BAU plus however many scenario combinations are possible:
`max_models = 2 + length(size_scale) * n_techs + n_incentives_scenarios`
#### Define an array of models of length `max_models` along with the specified solver and desired parameters:
`ms = [Model(optimizer_with_attributes(HiGHS.Optimizer, 
    "output_flag" => false, "mip_rel_gap" => 0.001, "log_to_console" => true)) for _ in 1:max_models]`
- Solver options for Cbc.jl: https://github.com/jump-dev/Cbc.jl
- Solver options for HiGHS.jl:  https://ergo-code.github.io/HiGHS/dev/options/definitions/
- Increasing optimality gap (ratioGap for Cbc and mip_rel_gap for HiGHS) to 0.01 (1%) is particularly useful if REopt is taking a long time to solver
#### In-series/sequential runs to reduce number of threads required to 2:
`results_all, results_summary = REopt.run_reopt_multi_solutions(fp, size_scale, ms; parallel=false)`

#### Parallel runs with resilience, requiring multiple cores for the multiple threads (see function docstring for more information):
`results_all, results_summary = REopt.run_reopt_multi_solutions(fp, size_scale, ms; parallel=true,  resilience=true, outage_start_hour=4000, outage_duration_hours=10, state="CO")`

#### Here is an example `results_summary` output for `PV` and Battery (`ElectricStorage`) with `resilience=true`:
```
    "optimal": {
        "status": "optimal",
        "incentive_used": {
            "net_metering_from_dsire: "false",
            "best_incentive_program_name": "Austin Energy - Commercial Solar PV Rebate Program"
        },
        "resilience": {
            "Specified outage hours of load served": 3.0,
            "Average outage hours of load served (hours)": 15.0,
            "Average outage load served (kWh)": 4940.0,
            "Specified outage load served with DERs (kWh)": 4090.0,
            "Specified outage cost savings per year with DERs": 2.05e7,
            "Specified outage cost savings as percent of annual utility bill": 6640.0,
            "Input outage duration (hours)": 10,
            "Average outage cost savings per year": 2.47e7
        },
        "PV": {
            "Capital cost": 2.9387651486586295e6,
            "Annual maintenance cost": 61478.709899999994,
            "Average annual energy produced": 6.131804e6,
            "Rated capacity": 3616.3947
        },
        "Financial": {
            "Simple payback period": 6.66,
            "Net Present Value": 4.1934961e6,
            "Net capital cost": 5.0679701147e6,
            "Internal Rate of Return %": 13.0
        },
        "Storage": {
            "Capital cost": 1.3586723305624602e6,
            "Rated inverter capacity": 961.82,
            "Rated energy capacity": 5350.36,
            "Total replacement cost": 770532.6255763071
        },
        "emissions": {
            "Site life cycle PM25 tonnes": 1.08,
            "Site life cycle SO2 tonnes": 1.43,
            "Site life cycle NOx tonnes": 1.43,
            "Site life cycle CO2 tonnes": 18582.68
        }
    }
```