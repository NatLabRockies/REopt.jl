# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Guidelines
- When working in feature branch, start a new double-hash header with the name of the branch and record changes under that
- When merging `develop` into a feature branch, keep the feature branch section and the "Develop" section separate to simplify merge conflicts
- When making a Pull Request into `develop`, merge the feature branch section into the "Develop" section (if it exists), else rename the feature branch header to "Develop"
- When making a Pull Request into `master` change "Develop" to the next version number

### Formatting
- Use **bold** markup for field and model names (i.e. **outage_start_time_step**)
- Use `code` markup for  REopt-specific file names, functions, and endpoints (e.g. `src/REopt.jl`)
- Use _italic_ for code terms (i.e. _list_)
- Prepend change with tag(s) directing where it is in the repository:  
`src`,`constraints`,`*.jl`

Classify the change according to the following categories:
    
    ### Added
    ### Changed
    ### Fixed
    ### Deprecated
    ### Removed

## Develop 
### Fixed
- Include boiler emissions in emissions calculations
- Update links that broke with NLR domain change and update other references to NREL
### Changed
- Updated defaults for **Financial** inputs **elec_cost_escalation_rate_fraction**, **boiler_fuel_cost_escalation_rate_fraction**, **existing_boiler_fuel_cost_escalation_rate_fraction**, **chp_fuel_cost_escalation_rate_fraction**, **generator_fuel_cost_escalation_rate_fraction**, **om_cost_escalation_rate_fraction**, and **offtaker_discount_rate_fraction** when **sector** is "federal" (based on the 2025 NIST Handbook and Annual Supplement)

## v0.56.4
### Fixed
- Bug where storage input with only _Int_ values restricted _Dict_ subtype passed into `set_sector_defaults!` and caused _InexactError_
- Bug where **ElectricStorage** input with only _Real_ values restricted _Dict_ subtype, causing **off_grid_flag** to be added as an _Int_ instead of _Bool_, leading to a conversion error in **ElectricStorageDefaults**
- Fixed a bug in the type handling of **emissions_factor_series_lb_XXX_per_kwh** in which `xxx` is in the group **[CO2, SO2, NOx, PM25]**.
- Handle "HIMS" region incorrectly named "HI" in avert_102008.shp

## v0.56.3
### Fixed
- Correctly escape the \$ symbol in docstring for `REopt.add_electric_tariff_results` in `results/electric_tariff.jl`

## v0.56.2
### Fixed
- Robust fix for type error with `ElectricLoad.monthly_peaks_kw` so that it now converts Vector{Any} to Vector{Float64} in scenario.jl before constructing `ElectricLoad`. Also converted `ElectricLoad.monthly_totals_kwh` to Vector{Float64} for good measure even though we weren't getting errors with that.

## v0.56.1
### Fixed
- `CST` bypassing constraints for not serving (`can_serve_.. = false`) heating load types by going through the `HighTempThermalStorage`
- Type error with `ElectricLoad.monthly_peaks_kw` so that it now converts Vector{Any} to Vector{<:Real}
- `ElectricTariff.urdb_metadata.rate_effective_date` with the right URDB parameter

## v0.56.0
### Added
- **ElectricLoad** input **monthly_peaks_kw**. Can be used to scale loads_kw or doe_reference loads to monthly peaks while maintaining monthly energy.
- Ability to use monthly energy and peak scaling with timesteps_per_hour > 1
- `ElectricTariff` and `ElectricLoad` inputs and outputs; mostly outputs related to monthly and per-timestep series rates and costs, and `urdb_metadata` which contains additional information about the URDB rate.
- New function in **utils.jl** called get_load_metrics() which gets the annual and monthly energy and peak load values (units depends on the input `load_profile`, so that it can be used with any load type).

## v0.55.2
### Fixed 
- fixed a bug in which demand and energy charges are applied to incorrect tiers in instances where tiered rates decrease as consumption increases, and the limits on the last tier are very large.

## v0.55.1
### Fixed
- Updated from the deprecated NSRDB API call to the suggested new URL which uses the GOES dataset
- Added `CST` to `Financial.initial_capital_costs` output
### Changed
- The solar resource data for CST changed with the new API call for the GOES dataset

## v0.55.0
### Added
- Added **Site** inputs **sector**, **federal_sector_state**, and **federal_procurement_type**
- Alternative defaults used when **sector** is "federal"
- **GHPOutputs** fields **hybrid_solution_type**, **solve_time_min**, **number_of_boreholes_nonhybrid**, **number_of_boreholes_auto_guess**,
**number_of_boreholes_flipped_guess**, **iterations_nonhybrid**, **iterations_auto_guess**, **iterations_flipped_guess**
### Changed
- Change hybrid GHP workflow from (1) running a 2-year simulation to guess if an auxiliary heating or cooling unit is required and outputting results to (2) running non-hybrid first in all hybrid runs and comparing to hybrid outputs to guarantee an actual hybrid solution where possible

## v0.54.1
### Added 
- Added attribute `can_waste_heat` to CST module, allowing for CST to curtail heat.
### Changed
- Use ARM version of SAM library file if processor architecture is ARM
- Fixed some docstrings in the CST source code.
### Fixed
- Fix `CHP` and `Boiler` results when there is HighTempThermalStorage

## v0.54.0
### Changed
Update the following inputs from the previous --> new values:
- `Financial.offtaker_discount_rate_fraction`: 0.0638 --> 0.0624
- `Financial.owner_discount_rate_fraction`: 0.0638 --> 0.0624
- `Financial.elec_cost_escalation_rate_fraction`: 0.017 --> 0.0166
- `Financial.existing_boiler_fuel_cost_escalation_rate_fraction `: 0.015 --> 0.0348
- `Financial.boiler_fuel_cost_escalation_rate_fraction `: 0.015 --> 0.0348
- `Financial.chp_fuel_cost_escalation_rate_fraction `: 0.015 --> 0.0348
- `Financial.generator_fuel_cost_escalation_rate_fraction `: 0.012 --> 0.0197
- `Generator.fuel_cost_per_gallon`: 3.61 --> 2.25
- `ColdThermalStorage`, `HotThermalStorage`, `ElectricStorage` `macrs_option_years`: 7 --> 5
-  `CHP`, `ColdThermalStorage`, `HotThermalStorage`, `ElectricStorage`, `PV`, `Wind` `macrs_bonus_fraction` 0.6 --> 1.0
- `GHP.macrs_bonus_fraction`: 0.4 --> 0.0
- `GHP.macrs_option_years`: 5 --> 0
- `SteamTurbine.macrs_bonus_fraction`: 0 --> 1.0 
- `SteamTurbine.macrs_option_years`: 0 --> 5 (in order for 100% bonus depr to apply)
- `CHP.federal_itc_fraction`: 0.3 --> 0.0
- `Wind.om_cost_per_kw`: 36.0 --> 42.0 
- `Wind.size_class_to_installed_cost` = Dict(
        "residential"=> 6339.0, --> 7692.0
        "commercial"=> 4760.0, --> 5776.0
        "medium"=> 3137.0, --> 3807.0
        "large"=> 2386.0 --> 2896.0)
- Changed **cycle_fade_coefficient** input to be a vector and accept vector of inputs.
- Changed default inputs for degradation module to match parameters for NMC-Gr Kokam 75Ah cell.
- Changed residual battery fraction calculation to calculate useful healthy capacity for residual value and capacity calculations.
- Require NREL Developer API email set as ENV["NREL_DEVELOPER_EMAIL"] = 'your contact email' for CST runs (also requires ENV["NREL_DEVELOPER_API_KEY"])
### Added
- Added constraints in `src/constraints/battery_degradation.jl` to allow use of segmented cycle fade coefficients in the model.
- Added **cycle_fade_fraction** as an input for portion of BESS that is tied to each cycle fade coefficient.
- Added **total_residual_kwh** output which captures healthy residual battery capacity due to degradation and the replacement strategy
- Added ARM version of SAM library file `src/sam/libssc_arm.dylib`, which can be renamed to `libssc.dylib` for running REopt.jl locally on an ARM Mac.
- Added new file `src/core/cst.jl` with new technology **CST**, which provides heating as output; technology-specific sets and results have been updated and added accordingly.
- Added new file `src/core/cst_ssc.jl` to interface with SAM when populating inputs (i.e., performance profile) with new technology **CST**.
- Added to file `src/core/energy_storage/thermal_storage.jl` with new technology **HighTempThermalStorage**, which stores heat for industrial processes primarily; technology-specific sets have been updated and added accordingly.
- Added new file `src/results/cst.jl` to provide results from new technology **CST**.
- Added to file `src/results/thermal_storage.jl` to provide results from new storage technology **HighTempThermalStorage**.
- Added new file `test/scenarios/cst.json` with new test for technologies **CST**.
### Fixed
- Corrected pv_defaults.jl "Small Commercial" "om_premium" from 0.95 to 1.0 

## v0.53.2
### Fixed
- `PV` `size_class` and cost defaults not updating correctly when both `max_kw` and the site's land or roof space are input

## v0.53.1
### Fixed
- Issue with `CHP` and `PV` cost curves when with-incentives segments is greater than no-incentives segments

## v0.53.0
### Added
- Add new **ElectricStorage** input fields **installed_cost_constant**, **replace_cost_constant** (both default to 0), and **cost_constant_replacement_year** (defaults to year 10).
- Added new binary variable **binIncludeStorageCostConstant** which is indexed on `p.s.storage.types.elec`
- Added `ElectricStorage.om_cost_fraction_of_installed_cost` input, default, and model expression as the main battery O&M
- New inputs for `PV` to determine default cost parameters and optional piece-wise linear (PWL) cost curves: `size_class`, `tech_sizes_for_cost_curve`, and `use_detailed_cost_curve`. The `installed_cost_per_kw` can also now be an array to go along with the `tech_sizes_for_cost_curve` input.
- New function for calculating `PV` size class and cost parameters from other inputs
- Memory-clearing commands after each JuMP model instance in `runtests.jl` to avoid memory buildup which were slowing down Actions test job
- Added back `ubuntu` OS as an additional runner OS for the tests Action job, now that memory buildup is reduced (removed a year ago due to memory crashing the runner)
- Add `installed_cost...` for `ExistingBoiler` and `ExistingChiller` which is incurred in the BAU scenario, and may be avoided with other heating and cooling technologies in the Optimal scenario.
### Changed
- Updated default `ElectricStorage` cost values per ATB 2024
- Zeroed-out `ElectricStorage` replacement costs because they are now included in the default O&M as fraction of installed cost
- `PV.installed_cost_per_kw` and `PV.om_cost_per_kw` does not have a fixed default value, and instead it is dependent on other inputs such as the `ElectricLoad.annual_kwh` and `Site.roof_squarefeet` to determine the `size_class` based on an estimated `PV` size which is calculated from those inputs.
- The default `installed_cost_per_kw` is a fixed/single value for the calculated `size_class`, but if `use_detailed_cost_curve` is set to `true`, then it will use a 2-point PWL cost curve with `tech_sizes_for_cost_curve`.
### Fixed
- Correctly apply zero/no MACRS for `ElectricStorage`, `HotThermalStorage`, and `ColdThermalStorage` which were always using 5 years MACRS schedules if not the default 7
- Fixed bug by setting `min_initial_capital_costs_before_incentives` and `max_initial_capital_costs_before_incentives` to nothing for BAU Scenario
- Fixed handling of non-hourly (e.g. 15-min interval) fuel cost

## v0.52.0
### Added
- Add **Financial** inputs `min_initial_capital_costs_before_incentives` and `max_initial_capital_costs_before_incentives` which, when provided, provide upper and lower bounds on initial capital costs for all technologies.
- Add **SteamTurbine** inputs `production_incentive_per_kwh`, `production_incentive_max_benefit`, `production_incentive_years`, and `production_incentive_max_kw`
- Add **CHP** output `initial_capital_costs`
### Fixed
- Fix implementation of production-based incentives

## v0.51.1
### Added
- Added the following output fields: `year_one_fuel_cost_after_tax` for `ExistingBoiler`, `CHP`, `Generator`, and `Boiler`; `ElectricTariff`: `year_one_bill_after_tax` and `year_one_export_benefit_after_tax`, `Financial`: `capital_costs_after_non_discounted_incentives`, `year_one_total_operating_cost_savings_before_tax`, `year_one_total_operating_cost_savings_after_tax`, `year_one_total_operating_cost_before_tax`, `year_one_total_operating_cost_after_tax`, `year_one_fuel_cost_before_tax`, `year_one_fuel_cost_after_tax`, `year_one_chp_standby_cost_after_tax`, `year_one_chp_standby_cost_after_tax`, `GHP.avoided_capex_by_ghp_present_value`
- Add a warning so that when **SteamTurbine** is included, renewable energy fractions may not be accurate.
- Added new attribute **fuel_renewable_energy_fraction** to the technology **Boiler**.
### Changed
- Updated and fixed some `docs` pages: improved setup, using HiGHS solver, fixed docstrings 
- Changed the name of the following output fields: `Financial.capital_costs_after_incentives_without_macrs` to `Financial.capital_costs_after_non_discounted_incentives_without_macrs`
### Fixed
- Update the **REoptInputs** parameter **tech_renewable_energy_fraction** so that only electricity-producing and fuel-burning heating technologies are included (instead of all technologies).
- Included the following in the `Financial.lifecycle_capital_costs` and `Financial.initial_capital_costs`: `m[Symbol("OffgridOtherCapexAfterDepr"*_n)] - m[Symbol("AvoidedCapexByGHP"*_n)] - m[Symbol("ResidualGHXCapCost"*_n)] - m[Symbol("AvoidedCapexByASHP"*_n)]`

## v0.51.0
### Added 
- Add the following inputs to account for the clean or renewable energy fraction of grid-purchased electricity: 
  - **ElectricUtility** **cambium_cef_metric** to utilize clean energy data from NREL's Cambium database
  - **ElectricUtility** **renewable_energy_fraction_series** to supply a custom grid clean or renewable energy scalar or series
  - **Site** **include_grid_renewable_fraction_in_RE_constraints** - to allow user to choose whether to include grid RE in min max constraints
- Add the following outputs: 
  - **ElectricUtility** **annual_renewable_electricity_supplied_kwh**
  - **Site** **onsite_and_grid_renewable_electricity_fraction_of_elec_load**
  - **Site** **onsite_and_grid_renewable_energy_fraction_of_total_load**
  - **ElectricLoad** **annual_electric_load_with_thermal_conversions_kwh** which calculates end-use electrical load after including electric consumption by heaters and chillers
- Add input option **optimize_soc_init_fraction** (defaults to false) to **ElectricStorage**, which makes the optimization choose the inital SOC (equal to final SOC) instead of using soc_init_fraction. The initial SOC is also constrained to equal the final SOC, which eliminates the "free energy" issue. We currently do not fix SOC when soc_init_fraction is used because this has caused infeasibility.
### Changed
- Change name of the following inputs: 
  - **ElectricUtility** input **cambium_metric_col** changed to **cambium_co2_metric**
- Change name of the following outputs:
  - **ElectricUtility** **cambium_emissions_region** changed to **cambium_region**
  - **Site** **annual_renewable_electricity_kwh** changed to **annual_onsite_renewable_electricity_kwh**
  - **Site** **renewable_electricity_fraction** changed to **onsite_renewable_electricity_fraction_of_elec_load** 
  - **Site** **total_renewable_energy_fraction** changed to **onsite_renewable_energy_fraction_of_total_load**
- Change name of function (also available as endpoint through REopt API) from **cambium_emissions_profile** to **cambium_profile**
- Update AVERT emissions data to v4.3, which uses Regional Data Files for year 2023 for CONUS. For Alaska and Hawaii (regions AKGD, HIMS, HIOA), updated eGRID data to eGRID2022 datafile, adjusted to CO2e values. Emissions profiles are saved in `data/emissions/AVERT_Data`. 
- Update Cambium API call for CO2e emissions within CONUS to Cambium 2023 dataset. This includes updates to the default values and valid options for the following **ElectricUtility** inputs:  **cambium_scenario**, **cambium_location_type**, and **cambium_start_year**
- Update EMISSIONS_DECREASE_DEFAULTS from 0.02163 to 0.0459 based on Cambium 2023 data
- Update Julia version
### Fixed
- Make **ElectricTariff** **export_rate_beyond_net_metering_limit** and **wholesale_rate** with sub-hour time step work
- Update the expression `m[:AnnualEleckWh]` to include electrified thermal loads
- Update expressions `m[:AnnualREHeatkWh]` and `m[:AnnualHeatkWh]` so that only non-electrified thermal loads are included and storage losses are proportional to the contribution of fuel-burning technologies to charging storage

## v0.50.0
### Added
- New parameter `force_dispatch` in the **ASHPSpaceHeater** and **ASHPWaterHeater** technologies (default = `true`).  When kept at `true`, the ASHP's thermal output will be the minimum of the site load(s) served and the system size (adjusted for timestep-specific capacity factor) in each period. If set to `false`, ASHP will do economic dispatch considering COP and CF along with electricity prices.
### Fixed
- Align heating and cooling load profiles based on electric load year input, if using custom electric load profile with simulated (CRB or schedule-based flatloads) heating/cooling loads
- Handling of leap years for `ElectricLoad.loads_kw` inputs to align with URDB rate structures
### Changed
- Make `year` input required with any custom load profile input (e.g. `ElectricLoad.loads_kw`, `SpaceHeatingLoad.fuel_loads_mmbtu_per_hour`)
- Shift and adjust CRB load profiles (i.e. with `doe_reference_name` input) based on the `year` input


## v0.49.1
### Changed
- Swap an error for a warning with inconsistent load-year between electric and heating

## v0.49.0
### Added
- Ability to normalize and scale a custom load profile input to annual or monthly energy input values, for all load types
### Changed
- Internal refactoring of the three types of heating loads into a single `HeatingLoad` struct
- Moved the annual_[energy] data from the load src files into the /data/load_profiles folder
### Fixed
- Constrained export to grid in the NEM bin (`dvProductionToGrid"*_n)][t, :NEM, ts`) to be 0 when system is sized over NEM limit (i.e., when binNEM =0)

## v0.48.2
### Added
- Add new optional parameter **max_ton** to GHP module to allow user to size GHP smaller than peak load
- Battery residual value if choosing replacement strategy for degradation
- Add new **ElectricStorage** parameters **max_duration_hours** and **min_duration_hours** to bound the energy duration of battery storage
### Changed
- Revised the battery degradation model, refactoring some methods to increase model-building efficiency and reformulating indicator constraints as big-M constraints with smaller big-M's to reduce solve time.
- Edited several documentation entries and docstrings for clarity.
### Removed
- 80% scaling of battery maintenance costs when using augmentation strategy
### Fixed 
- Fixed conditions for which a warning is presented indicating that the wholesale benefit threshold is met. 
- When setting **thermal_production_series_mmbtu_per_hour** output in **ExistingBoiler**, sum over heating loads instead of time steps

## v0.48.1
### Changed
- Replace all `1/p.s.settings.time_steps_per_hour` with `p.hours_per_time_step` for simplicity/consistency
- Rename function `add_storage_sum_constraints` to `add_storage_sum_grid_constraints` for clarity
### Added
- Constraints to prevent simultaneous charge/discharge of storage
- Specify in docstrings that **PV** **max_kw** and **size_kw** are kW-DC
- Add the Logging package to `test/Project.toml` because it is used in `runtests.jl`
### Fixed
- Force **ElectricLoad** **critical_load_kw** to be _nothing_ when **off_grid_flag** is _true_ (**critical_load_fraction** was already being forced to 1, but the user was still able to get around this by providing **critical_load_kw**)
- Removed looping over storage name in functions `add_hot_thermal_storage_dispatch_constraints` and `add_cold_thermal_storage_dispatch_constraints` because this loop is already done when calling these functions and storage name is passed in as argument `b`
- Remove extraneous line of code in `results/wind.jl`
- Change type of **value_of_lost_load** in **FinancialInputs** struct to fix convert error when user provides an _Int_
- Change international location in "Solar Dataset" test set from Cameroon to Oulu because the locations in the NSRDB have been expanded significantly so there is now an NSRDB point at Cameroon
- Handle edge case where the values of **outage_start_time_steps** and **outage_durations** makes an outage extend beyond the end of the year. The outage will now wrap around to the beginning of the year.
- Enforce minimum allowable sizes for ASHP technologies by introducing improved big-M values for segmented size constraints.
- Removed default values from ASHP functions that calculate minimum allowable size and performance.

## v0.48.0
### Added
- Added new file `src/core/ASHP.jl` with new technology **ASHP**, which uses electricity as input and provides heating and/or cooling as output; load balancing and technology-specific constraints have been updated and added accordingly
- In `src/core/existing_chiller.jl`, Added new atttribute **retire_in_optimal** to the **ExistingChiller** struct
- Financial output **initial_capital_costs_after_incentives_without_macrs** which has "net year one" CapEx after incentives except for MACRS, which helps with users defining their own "simple payback period"

### Changed
- Improve the full test suite reporting with a verbose summary table, and update the structure to reflect long-term open-source solver usage.
- Removed MacOS from the runner list and just run with Windows OS, since MacOS commonly freezes and gets cancelled. We have not seen Windows OS pass while other OS's fail.
- Suppress JuMP warning messages from 15-minute and multiple PVs test scenarios to avoid flooding the test logs with those warnings.
- Updated/specified User-Agent header of "REopt.jl" for PVWatts and Wind Toolkit API requests; default before was "HTTP.jl"; this allows specific tracking of REopt.jl usage which call PVWatts and Wind Toolkit through api.data.gov.
- Improves DRY coding by replacing multiple instances of the same chunks of code for MACRS deprecation and CHP capital cost into functions that are now in financial.jl.
- Simplifies the CHP sizing test to avoid a ~30 minute solve time, by avoiding the fuel burn y-intercept binaries which come with differences between full-load and part-load efficiency.
- For third party analysis proforma.jl metrics, O&M cost for existing Generator is now kept with offtaker, not the owner/developer
### Fixed
- Proforma calcs including "simple" payback and IRR for thermal techs/scenarios.
  - The operating costs of fuel and O&M were missing for all thermal techs such as ExistingBoiler, CHP, and others; this adds those sections of code to properly calculate the operating costs.
- Added a test to validate the simple payback calculation with CHP (and ExistingBoiler) and checks the REopt result value against a spreadsheet proforma calculation (see Bill's spreadsheet).
- Added a couple of missing techs for the initial capital cost calculation in financial.jl.
- An issue with setup_boiler_inputs in reopt_inputs.jl.
- Fuel costs in proforma.jl were not consistent with the optimization costs, so that was corrected so that they are only added to the offtaker cashflows and not the owner/developer cashflows for third party.


## v0.47.2
### Fixed
- Increased the big-M bound on maximum net metering benefit to prevent artificially low export benefits.
- Fixed a bug in which tier limits did not load correctly when the number of tiers vary by period in the inputs.
- Set a limit for demand and energy tier maxes to avoid errors returned by HiGHS due to numerical limits.
- Index utility rate demand and energy tier limits on month and/or ratchet in addition to tier.  This allows for the inclusion of multi-tiered energy and demand rates in which the rates may vary by month or ratchet, whereas previously only the maximum tier limit was used.
### Added
- Added thermal efficiency as input to chp defaults function.

## v0.47.1
### Fixed
- Type issue with `CoolingLoad` monthly energy input
- `simulated_load()` response for `annual_mmbtu` for individual heating loads (fixed to fuel instead of thermal)

## v0.47.0
### Added
- Added inputs options and handling for ProcessHeatLoad for scaling annual or monthly fuel consumption values with reference hourly profiles, same as other loads
### Changed
- Updated `test/scenarios/thermal_load.json` to include **ProcessHeatLoad** in both hourly and monthly fuel load tests.
- Refactored test sets in `test/runtests.jl` to include **ProcessHeatLoad** and ensure it is treated similarly to **DomesticHotWaterLoad** and **SpaceHeatingLoad**.
- Modified **dvHeatingProduction** to account for **ProcessHeatLoad** with relevant addressable load fractions.
- Updated test values and expectations to include contributions from **ProcessHeatLoad**.
- Updated `src/core/doe_commercial_reference_building_loads.jl` to include **ProcessHeatLoad** for built-in load handling.
- Refactored various functions to ensure **ProcessHeatLoad** is processed correctly in line with other heating loads.
- When the URDB response `energyratestructure` has a "unit" value that is not "kWh", throw an error instead of averaging rates in each energy tier.
- Refactored heating flow constraints to be in ./src/constraints/thermal_tech_constraints.jl instead of its previous separate locations in the storage and turbine constraints.
- Changed default Financial **owner_tax_rate_fraction** and **offtaker_tax_rate_fraction** from 0.257 to 0.26 to align with API and user manual defaults. 
### Fixed
- Updated the PV result **lifecycle_om_cost_after_tax** to account for the third-party factor for third-party ownership analyses.
- Convert `max_electric_load_kw` to _Float64_ before passing to function `get_chp_defaults_prime_mover_size_class`
- Fixed a bug in which excess heat from one heating technology resulted in waste heat from another technology.
- Modified thermal waste heat constraints for heating technologies to avoid errors in waste heat results tracking.

## v0.46.1
### Changed
- Updated the GHP testset .json `./test/scenarios/ghp_inputs.json` to include a nominal HotThermalStorage and ColdThermalStorage system.
### Fixed
- Fixed a bug in which the model fails to build when both GHP and either Hot or Cold Thermal Storage are present.

## v.0.46.0
### Added 
- In `src/core/absorption_chiller.jl` struct, added field **heating_load_input** to the AbsorptionChiller struct
- Added new variables **dvHeatToStorage** and **dvHeatFromStorage** which are indexed on `p.heating_loads` and added reconciliation constraints so that **dvProductionToStorage** and **dvDischargeFromStorage** maintain their relationship to state of charge for Hot thermal energy storage.
- In `src/constraints/thermal_tech_constraints.jl`, added function **no_existing_boiler_production** which prevents ExistingBoiler from producing heat in optimized (non-BAU) scenarios 
- for all heating techs and CHP, added fields **can_serve_space_heating**, **can_serve_dhw**, and **can_serve_process_heat** in core structs and added new results fields **thermal_to_dhw_load_series_mmbtu_per_hour**, **thermal_to_space_heating_load_series_mmbtu_per_hour**, and **thermal_to_process_heat_load_series_mmbtu_per_hour**
- In `src/core/techs.jl`, added new sets **ghp_techs**, **cooling_techs**, **techs_can_serve_space_heating**, **techs_can_serve_dhw**, and **techs_can_serve_process_heat**
- In `src/core/reopt_inputs.jl`, added new fields **heating_loads**, **heating_loads_kw**, **heating_loads_served_by_tes**, and **absorption_chillers_using_heating_load** to the REoptInputs and BAUInputs structs. in the math, new set `p.heating_loads` has index q (to represent "qualities" of heat).
- In `src/core/heating_cooling_loads.jl`, added new struct **ProcessHeatLoad**
- In `src/core/scenario.jl`, added new field **process_heat_load**
- In `src/mpc/inputs.jl`, added new field **heating_loads**
- In `src/core/existing_boiler.jl`, added field **retire_in_optimal** to the ExistingBoiler struct
- Info to user including name of PV and/or temperature datasource used and distance from site location to datasource location
- Warning to user if data is not from NSRDB or if data is more than 200 miles away
- In `results/heating_cooling_load.jl`, added new fields **process_heat_thermal_load_series_mmbtu_per_hour**, **process_heat_boiler_fuel_load_series_mmbtu_per_hour**, **annual_calculated_process_heat_thermal_load_mmbtu**, and **annual_calculated_process_heat_boiler_fuel_load_mmbtu** to HeatingLoad results, with sum heating loads now including process heat 
### Changed
- Change the way we determine which dataset to utilize in the PVWatts API call. Previously, we utilized defined lat-long bounds to determine if "nsrdb" or "intl" data should be used in PVWatts call. Now, we call the Solar Dataset Query API (v2) (https://developer.nrel.gov/docs/solar/data-query/v2/) to determine the dataset to use, and include "tmy3" as an option, as this is currently the best-available data for many locations in Alaska. 
- Refactored **dvThermalProduction** to be separated in **dvCoolingProduction** and **dvHeatingProduction** with **dvHeatingProduction** now indexed on `p.heating_loads`
- Refactored heating load balance constraints so that a separate flow balance is reconciled for each heating load in `p.heating_loads`
- Renamed **dvThermalProductionYIntercept** to **dvHeatingProductionYIntercept**
- Divided **ThermalStorage** into **HotThermalStorage** and **ColdThermalStorage** as the former now has attributes related to the compatible heat loads as input or output.
- Changed technologies included **dvProductionToWaste** to all heating techs.  NOTE: this variable is forced to zero to allow steam turbine tests to pass, but I believe that waste heat should be allowed for the turbine.  A TODO is in place to review this commit (a406cc5df6e4a27b56c92815c35d04815904e495).
- Changed test values and tolerances for CHP Sizing test.
- Updated test sets "Emissions and Renewable Energy Percent" and "Minimize Unserved Load" to decrease computing time.
- Test for tiered TOU demand rates in `test/runtests.jl`
- Updated `pop_year` and `income_year` used in call to EASIUR data (`get_EASIUR2005`) each to 2024, from 2020. 
- Updated usd conversion used for EASIUR health cost calcs from USD_2010_to_2020 = 1.246 to USD_2010_to_2024 = 1.432
### Fixed  
- Added a constraint in `src/constraints/steam_turbine_constraints.jl` that allows for heat loads to reconcile when thermal storage is paired with a SteamTurbine. 
- Fixed a bug in which net-metering system size limits could be exceeded while still obtaining the net-metering benefit due to a large "big-M".
- Fixed a reshape call in function `parse_urdb_tou_demand` that incorrectly assumed row major instead of column major ordering
- Fixed a loop range in function `parse_urdb_tou_demand` that incorrectly started at 0 instead of 1
- Added the missing tier index when accessing `p.s.electric_tariff.tou_demand_rates` in function `add_elec_utility_expressions`

## v0.45.0
### Fixed 
- Fixed bug in call to `GhpGhx.jl` when sizing hybrid GHP using the fractional sizing method
- Added `export_rate_beyond_net_metering_limit` to list of inputs to be converted to type Real, to avoid MethodError if type is vector of Any. 
- Fix blended CRB processing when one or more load types have zero annual energy
- When calculating CHP fuel intercept and slope, use 1 for the HHV because CHP fuel measured in units of kWh, instead of using non-existent **CHP.fuel_higher_heating_value_kwh_per_gal**
- Changed instances of indexing using i in 1:length() paradigm to use eachindex() or axes() instead because this is more robust
- In `src/core/urdb.jl`, ensure values from the "energyweekdayschedule" and "energyweekendschedule" arrays in the URDB response dictionary are converted to _Int_ before being used as indices
- Handle an array of length 1 for CHP.installed_cost_per_kw which fixes the API using this parameter
### Changed
- add **ElectricStorage** input option **soc_min_applies_during_outages** (which defaults to _false_) and only apply the minimum state of charge constraint in function `add_MG_storage_dispatch_constraints` if it is _true_
- Renamed function `generator_fuel_slope_and_intercept` to `fuel_slope_and_intercept` and generalize to not be specific to diesel measured in units of gal, then use for calculating non diesel fuel slope and intercept too

## v0.44.0
### Added 
- in `src/settings.jl`, added new const **INDICATOR_COMPATIBLE_SOLVERS**
- in `src/settings.jl`, added new member **solver_name** within the settings object.  This is currently not connected to the solver but does determine whether indicator constraints are modeled or if their big-M workarounds are used.
- added replacements for indicator constraints with the exception of battery degradation, which is implemented in a separate model, and FlexibleHVAC.  TODO's have been added for these remaining cases.
### Fixed
- Fixed previously broken tests using HiGHS in `test/runtests.jl` due to solver incompatibility.

## v0.43.0
### Fixed
- `simple_payback_years` calculation when there is export credit
- Issue with `SteamTurbine` heuristic size and default calculation when `size_class` was input
- BAU emissions calculation with heating load which was using thermal instead of fuel

## v0.42.0
### Changed
- In `core/pv.jl` a change was made to make sure we are using the same assumptions as PVWatts guidelines, the default `tilt` angle for a fixed array should be 20 degrees, irrespective of it being a rooftop `(1)` or ground-mounted (open-rack)`(2)` system. By default the `tilt` will be set to 20 degrees for ground-mount and rooftop, and 0 degrees for axis-tracking (`array_type = (3) or (4)`)
> "The PVWatts® default value for the tilt angle depends on the array type: For a fixed array, the default value is 20 degrees, and for one-axis tracking the default value is zero. A common rule of thumb for fixed arrays is to set the tilt angle to the latitude of the system's location to maximize the system's total electrical output over the year. Use a lower tilt angle favor peak production in the summer months when the sun is high in the sky, or a higher tilt angle to increase output during winter months. Higher tilt angles tend to cost more for racking and mounting hardware, and may increase the risk of wind damage to the array."

## v0.41.0
### Changed
- Changed default source for CO2 grid emissions values to NREL's Cambium 2022 Database (by default: CO2e, long-run marginal emissions rates levelized (averaged) over the analysis period, assuming start year 2024). Added new emissions inputs and call to Cambium API in `src/core/electric_utility.jl`. Included option for user to use AVERT data for CO2 using **co2_from_avert** boolean. 
- Updated `electric_utility` **emissions_region** to **avert_emissions_region** and **distance_to_emissions_region_meters** to **distance_to_avert_emissions_region_meters** in `src/electric_utility.jl` and `results/electric_utility.jl`. 
- Updated default **emissions_factor_XXX_decrease_fraction** (where XXX is CO2, NOx, SO2, and PM2.5) from 0.01174 to 0.02163 based on Cambium 2022 Mid-Case scenario, LRMER CO2e (Combustion+Precombustion) 2024-2049 projected values. CO2 projected decrease defaults to 0 if Cambium data are used for CO2 (Cambium API call will levelize values).  
- Updated AVERT emissions data to v4.1, which uses Regional Data Files (RDFs) for year 2022. Data is saved in `data/emissions/AVERT_Data`. For Alaska and Hawaii (regions AKGD, HIMS, HIOA), updated eGRID data to eGRID2021 datafile and adjusted CO2 values to CO2e values to align with default used for Cambium data. 
- Updated default fuel emissions factors from CO2 to CO2-equivalent (CO2e) values. In `src/core/generator.jl`, updated **emissions_factor_lb_CO2_per_gal** from 22.51 to 22.58. In `src/REopt.jl` updated **emissions_factor_lb_CO2_per_mmbtu** => Dict(
        "natural_gas"=>116.9 to 117.03,
        "landfill_bio_gas"=>114,8 to 115.38,
        "propane"=>138.6 to 139.16,
        "diesel_oil"=>163.1 to 163.61
    )
- Changed calculation of all `annual` emissions results (e.g. **Site.annual_emissions_tonnes_CO2**) to simple annual averages (lifecycle emissions divided by analysis_years). This is because the default climate emissions from Cambium are already levelized over the analysis horizon and therefore "year_one" emissions cannot be easily obtained. 
- Changed name of exported function **emissions_profiles** to **avert_emissions_profiles**
### Added
- In `src/REopt.jl` and `src/electric_utility.jl`, added **cambium_emissions_profile** as an export for use via the REopt_API. 
- In `src/REopt.jl`, added new const **EMISSIONS_DECREASE_DEFAULTS**
- In `src/results/electric_utility.jl` **cambium_emissions_region**
- In `test/runtests.jl` and `test/test_with_xpress.jl`, added testset **Cambium Emissions**
### Fixed 
- Adjust grid emissions profiles for day of week alignment with load_year.
- In `test_with_xpress.jl`, updated "Emissions and Renewable Energy Percent" expected values to account for load year adjustment. 
- In `src/core/electric_utility.jl`, error when user-provided emissions series does not match timestep per hour, as is done in other cases of incorrect user-provided data.
- Avoid adjusting rates twice when time_steps_per_hour > 1 

## v0.40.0
### Changed
- Changed **macrs_bonus_fraction** to from 0.80 to 0.60 (60%) for CHP, ElectricStorage, ColdThermalStorage, HotThermalStorage GHP, PV, Wind
### Fixed
- In `reopt.jl`, group objective function incentives (into **ObjectivePenalties**) and avoid directly modifying m[:Costs]. Previously, some of these were incorrectly included in the reported **Financial.lcc**. 

## v0.39.1
### Changed
- Changed testing suite from using Xpress to using HiGHS, an open-source solver.  This has led to a reduction in the number of tests due to incompatibility with indicator constraints.
### Fixed
- Fixed issue with running Wind on Windows: add execute permission for ssc.dll

## v0.39.0
### Added
- Added new technology `ElectricHeater` which uses electricity as input and provides heating as output; load balancing constraints have been updated accordingly

## v0.38.2
### Added 
- Added the following BAU outputs:  lifecycle_chp_standby_cost_after_tax, lifecycle_elecbill_after_tax, lifecycle_production_incentive_after_tax, lifecycle_outage_cost, lifecycle_MG_upgrade_and_fuel_cost
### Fixed
- Don't allow **Site** **min_resil_time_steps** input to be greater than the maximum value element in **ElectricUtility** **outage_durations**

## v0.38.1
### Fixed
- Fix CHP standby charge modeling - bad reference to pwf_e
- Avoid breaking backward compatibility with type declaration of (global) const urdb_api_key

## v0.38.0
### Changed
- Require NREL Developer API Key set as ENV["NREL_DEVELOPER_API_KEY"] = 'your API key' for PVWatts and Wind Toolkit

## v0.37.5
### Fixed
- Fixed AVERT emissions profiles for NOx. Were previously the same as the SO2 profiles. AVERT emissions profiles are currently generated from AVERT v3.2 https://www.epa.gov/avert/download-avert. See REopt User Manual for more information.
- Fix setting of equal demand tiers in `scrub_urdb_demand_tiers`, now renamed `scrub_urdb_tiers`. 
- When calling REopt.jl from a python environment using PyJulia and PyCall, some urdb_response fields get converted from a list-of-lists to a matrix type, when REopt.jl expects an array type. This fix adds checks on the type for two urdb_response fields and converts them to an array if needed.
- Update the outages dispatch results to align with CHP availability during outages

## v0.37.4
### Fixed
- Include `year` in creation of electric-only CHP for unavailability profile

## v0.37.3
### Changed
- Ignore `CHP` unavailability during stochastic, multiple outages; this is consistent with deterministic single outage

## v0.37.2
### Changed
- Do not enforce `CHP.min_turn_down_fraction` for outages

## v0.37.1
### Fixed
- CHP-only for multiple/stochastic outages
- Allow negative fuel_burn and thermal_prod intercepts for CPH
- Correct after_tax CHP results

## v0.37.0
### Added
- Added Bool attribute `is_electric_only` to CHP; if true, default installed and O&M costs are reduced by 25% and, for the reciprocating engine and combustion turbine prime movers, the federal ITC fraction is reduced to zero.
- Las Vegas CRB data was missing from ElectricLoad, but the climate_cities.shp file does not distinguish between Las Angeles and Las Vegas
### Changed
- Update `CHP.size_class` after heuristic size is determined based on size_class=0 guess (not input)
### Fixed
- Use the user-input `ExistingBoiler.efficiency` value for converting fuel input to thermal to preserve annual fuel energy input
- Fix heating loads monthly_mmbtu and addressable_load_fraction handling (type issues mostly)
- Bug fix for user-supplied 8760 WHL rates with tiered energy rate

## v0.36.0
### Changed
- Changed default values by prime mover for CHP technologies in `data/chp/chp_defaults.json`.  See user manual for details by prime mover and size class.
- Updated the package dependencies to be compatible with recent changes to HiGHS (for testing) and MathOptInterface
### Fixed
- The present worth factor for fuel (pwf_fuel) was not properly multiplying for lifecycle fuel costs

## v0.35.1
### Fixed
- Add GHP to proforma metrics for when GHP is evaluated (should have been there)
### Added
- Add different BAU outputs for heating and cooling systems

## v0.35.0
### Changed
- ANNUAL UPDATE TO DEFAULT VALUES. Changes outlined below with (old value) --> (new value). See user manual for references. 
  - Owner Discount rate, nominal (%): : **Financial** **owner_discount_rate_fraction** 0.0564	--> 0.0638
  - Offtaker Discount rate, nominal (%): **Financial**  **offtaker_discount_rate_fraction** 0.0564 --> 0.0638
  - Electricity cost escalation rate, nominal (%): **Financial** **elec_cost_escalation_rate_fraction** 0.019	--> 0.017
  - Existing boiler fuel cost escalation rate, nominal (%): **Financial**  **existing_boiler_fuel_cost_escalation_rate_fraction**	0.034	--> 0.015
  - Boiler fuel cost escalation rate, nominal (%): **Financial** **boiler_fuel_cost_escalation_rate_fraction**	0.034	--> 0.015
  - CHP fuel cost escalation rate, nominal (%): **Financial**  **chp_fuel_cost_escalation_rate_fraction**	0.034	--> 0.015
  - Generator fuel cost escalation rate, nominal (%): **Financial**  **generator_fuel_cost_escalation_rate_fraction**	0.027	--> 0.012
  - Array tilt – Ground mount, Fixed: **PV** **tilt** latitude	--> 20
  - O&M cost ($/kW/year): **PV** **om_cost_per_kw**	17	--> 18
  - System capital cost ($/kW): **PV** **installed_cost_per_kw**	1592	--> 1790
  - Energy capacity cost ($/kWh): **ElectricStorage** **installed_cost_per_kwh**	388	--> 455
  - Power capacity cost ($/kW): **ElectricStorage**	**installed_cost_per_kw**	775	--> 910
  - Energy capacity replacement cost ($/kWh): **ElectricStorage** **replace_cost_per_kwh**	220	--> 318
  - Power capacity replacement cost ($/kW): **ElectricStorage**	**replace_cost_per_kw**	440	--> 715
  - Fuel burn rate by generator capacity (gal/kWh): **Generator** **fuel_slope_gal_per_kwh**	0.076	--> removed and replaced with full and half-load efficiencies
  - Electric efficiency at 100% load (% HHV-basis): **Generator** **electric_efficiency_full_load**	N/A - new input	--> 0.322
  - Electric efficiency at 50% load (% HHV-basis): **Generator** **electric_efficiency_half_load**	N/A - new input	--> 0.322
  - Generator fuel higher heating value (HHV): **Generator** **fuel_higher_heating_value_kwh_per_gal**	N/A - new input	--> 40.7
  - System capital cost ($/kW): **Generator**  **installed_cost_per_kw** 500	--> $650 if the generator only runs during outages; $800 if it is allowed to run parallel with the grid; $880 for off-grid
  - Fixed O&M ($/kW/yr): **Generator** **om_cost_per_kw** Grid connected: 10 Off-grid: 20 --> Grid connected: 20 Off-grid: 10
  - System capital cost ($/kW) by Class: **Wind** **size_class_to_installed_cost**	residential - 5675 commercial - 4300 medium - 2766 large - 2239 --> residential - 6339 commercial - 4760 medium - 3137 large - 2386
  - O&M cost ($/kW/year): **Wind** **om_cost_per_kw** 35 --> 36
 
## v0.34.0
### Added
- Ability to run hybrid GHX sizing using **GhpGhx.jl** (automatic and fractional sizing)
- Added financial inputs for **GHP** and updated objective and results to reflect these changes
- Added central plant **GHP**
### Fixed
- Fix output of `get_tier_with_lowest_energy_rate(u::URDBrate)` to return an index and not cartesian coordinates for multi-tier energy rates.
- Updated **GHP** cost curve calculations so incentives apply to all GHP components
### Changed
- If a `REoptInputs` object solves with termination status infeasible, altert user and return a dictionary insteadof JuMP model

## v0.33.0
### Added
- Functionality to evaluate scenarios with Wind can in the ERP (`backup_reliability`)
- Dispatch data for outages: Wind, ElectricStorage SOC, and critical load
### Fixed
- Fix `backup_reliability_reopt_inputs(d, p, r)` so doesn't ignore `CHP` from REopt scenario
- In `backup_reliability_reopt_inputs(d, p, r)`, get `Generator` and `CHP` fuel related values from REopt results _Dict_ d and `REoptInputs` _struct_ p, unless the user overrides the REopt results by providing **generator_size_kw**
- Remove use of non-existent **tech_upgraded** `Outages` outputs, using **tech_microgrid_size_kw** instead
- Added missing **electric_storage_microgrid_upgraded** to `Outages` results
- Fix bug causing _InexactError_ in `num_battery_bins_default`
- Update docstrings in `backup_reliability.jl`
- Avoid supply > critical load during outages by changing load balance to ==
### Changed
- Updated REopt license
- Changed `backup_reliability` results key from **fuel_outage_survival_final_time_step** to **fuel_survival_final_time_step** for consistency with other keys

## v0.32.7
### Fixed
- Bugs in EASIUR health cost calcs
- Type handling for CoolingLoad monthly_tonhour input

## v0.32.6
### Changed
- Required **fuel_cost_per_mmbtu** for modeling **Boiler** tech, otherwise throw a handled error.
### Fixed
- Additional **SteamTurbine** defaults processing updates and bug fixes

## v0.32.5
### Changed
- Updated `get_existing_chiller_cop` function to accept scalar values instead of vectors to allow for faster API transactions.
- Refactored `backup_reliability.jl` to enable easier development: added conversion of all scalar generator inputs to vectors in `dictkeys_to_symbols` and reduced each functions with two versions (one with scalar and one with vector generator arguments) to a single version
- Simplify generator sizing logic in function `backup_reliability_reopt_inputs` (if user sets `generator_size_kw` or `num_generators`to 0, don't override based on REopt solution) and add a validation error
### Fixed
- Steamturbine defaults processing
- simulated_load monthly values processing
- Fixed incorrect name when accessing result field `Outages` **generator_microgrid_size_kw** in `outag_simulator.jl`

## v0.32.4
### Changed
- Consolidated PVWatts API calls to 1 call (previously 3 separate calls existed). API call occurs in `src/core/utils.jl/call_pvwatts_api()`. This function is called for PV in `src/core/production_factor.jl/get_production_factor(PV)` and for GHP in `src/core/scenario.jl`. If GHP and PV are evaluated together, the GHP PVWatts call for ambient temperature is also used to assign the pv.production_factor_series in Scenario.jl so that the PVWatts API does not get called again downstream in `get_production_factor(PV)`.  
- In `src/core/utils.jl/call_pvwatts_api()`, updated NSRDB bounds used in PVWatts query (now includes southern New Zealand)
- Updated PV Watts version from v6 to v8. PVWatts V8 updates the weather data to 2020 TMY data from the NREL NSRDB for locations covered by the database. (The NSRDB weather data used in PVWatts V6 is from around 2015.) See other differences at https://developer.nrel.gov/docs/solar/pvwatts/.
- Made PV struct mutable: This allows for assigning pv.production_factor_series when calling PVWatts for GHP, to avoid a extra PVWatts calls later.
- Changed unit test expected values due to update to PVWatts v8, which slightly changed expected PV production factors.
- Changed **fuel_avail_gal** default to 1e9 for on-grid scenarios (same as off-grid)
### Fixed
- Issue with using a leap year with a URDB rate - the URDB rate was creating energy_rate of length 8784 instead of intended 8760
- Don't double add adjustments to urdb rates with non-standard units
- Corrected `Generator` **installed_cost_per_kw** from 500 to 650 if **only_runs_during_grid_outage** is _true_ or 800 if _false_
- Corrected `SteamTurbine` defaults population from `get_steam_turbine_defaults_size_class()`

## v0.32.3
### Fixed
- Calculate **num_battery_bins** default in `backup_reliability.jl` based on battery duration to prevent significant discretization error (and add test)
- Account for battery (dis)charge efficiency after capping power in/out in `battery_bin_shift()`
- Remove _try_ _catch_ in `backup_reliability(d::Dict, p::REoptInputs, r::Dict)` so can see where error was thrown

## v0.32.2
### Fixed
- Fixed bug in multiple PVs pv_to_location dictionary creation. 
- Fixed bug in reporting of grid purchase results when multiple energy tiers are present.
- Fixed bug in TOU demand charge calculation when multiple demand tiers are present.

## v0.32.1
### Fixed
- In `backup_reliability.jl`:
    - Check if generator input is a Vector instead of has length greater than 1
    - Correct calculation of battery SOC adjustment in `fuel_use()` function
    - Correct outage time step survival condition in `fuel_use()` function
- Add test to ensure `backup_reliability()` gives the same results for equivalent scenarios (1. battery only and 2. battery plus generator with no fuel) and that the survival probability decreases monotonically with outage duration
- Add test to ensure `backup_reliability()` gives the same results as `simulate_outages()` when operational availability inputs are 1, probability of failure to run is 0, and mean time to failure is a very large number.

## v0.32.0
### Fixed
- Fixed calculation of `wind_kw_ac_hourly` in `outagesim/outage_simulator.jl`
- Add  a test of multiple outages that includes wind
- Add a timeout to PVWatts API call so that if it does not connect within 10 seconds, it will retry. It seems to always work on the first retry.

## v0.31.0
### Added
- Created and exported easiur_data function (returns health emissions costs and escalations) for the API to be able to call for it's easiur_costs endpoint
- Added docstrings for easiur_data and emissions_profiles

## v0.30.0
### Added
- `Generator` input **fuel_higher_heating_value_kwh_per_gal**, which defaults to the constant KWH_PER_GAL_DIESEL
### Changed
- Added more description to **production_factor_series inputs**
### Fixed
- Fixed spelling of degradation_fraction
- use push! instead of append() for array in core/cost_curve.jl
- Fixed calculation of batt_roundtrip_efficiency in outage_simulator.jl

## v0.29.0
### Added
- Add `CHP` `FuelUsed` and `FuelCost` modeling/tracking for stochastic/multi-outages
- Add `CHP` outputs for stochastic/multi-outages
### Changed
- Made outages output names not dynamic to allow integration into API
- Add missing units to outages results field names: **unserved_load_series_kw**, **unserved_load_per_outage_kwh**, **generator_fuel_used_per_outage_gal**
- Default `Financial` field **microgrid_upgrade_cost_fraction** to 0
- Add conditional logic to make `CHP.min_allowable_kw` 25% of `max_kw` if there is a conflicting relationship 
- Iterate on calculating `CHP` heuristic size based on average heating load which is also used to set `max_kw` if not given: once `size_class` is determined, recalculate using the efficiency numbers for that `size_class`.
### Fixed
- Fix non-handling of cost-curve/segmented techs in stochastic outages
- Fix issues with `simulated_load.jl` monthly heating energy input to return the heating load profile

## v0.28.1
### Added
- `emissions_profiles` function, exported for external use as an endpoint in REopt_API for the webtool/UI

## v0.28.0
### Changed 
- Changed Financial **breakeven_cost_of_emissions_reduction_per_tonnes_CO2** to **breakeven_cost_of_emissions_reduction_per_tonne_CO2**
- Changed `CHP.size_class` to start at 0 instead of 1, consistent with the API, and 0 represents the average of all `size_class`s
- Change `CHP.max_kw` to be based on either the heuristic sizing from average heating load (if heating) or peak electric load (if no heating, aka Prime Generator in the UI)
  - The "big_number" for `max_kw` was causing the model to take forever to solve and some erroneous behavior; this is also consistent with the API to limit max_kw to a reasonable number
### Added 
- Added previously missing Financial BAU outputs: **lifecycle_om_costs_before_tax**, **lifecycle_om_costs_after_tax**, **year_one_om_costs_before_tax**
### Fixed
- Fixed if statement to determing ElectricLoad "year" from && to ||, so that defaults to 2017 if any CRB input is used
    
## v0.27.0
### Added
- Energy Resilience Performance tool: capability to model limited reliability of backup generators and RE, and calculate survival probability metrics during power outages for a DER scenario
- Exported `backup_reliability` function to run the reliability based calculations
### Changed
- Changed `Generator` inputs **fuel_slope_gal_per_kwh** and **fuel_intercept_gal_per_hr** to **electric_efficiency_full_load** and **electric_efficiency_half_load** to represent the same fuel burn curve in a different way consistent with `CHP`

## v0.26.0
### Added 
- Added `has_stacktrace` boolean which is returned with error messages and indicates if error is of type which contains stacktrace
- Constraint on wind sizing based on Site.land_acres
- New Wind input **acres_per_kw**, defaults to 0.03
- Descriptions/help text for many inputs and outputs
- Add and modify the `GHP` results to align with the existing/expected results from the v2 REopt_API
- Add `CSV` and `DataFrames` packages to REopt.jl dependencies 
### Changed
- Update REopt.jl environment to Julia v1.8
- Changed default **year** in ElectricLoad to be 2017 if using a CRB model and 2022 otherwise. 
- Removed default year in URDBrate() functions, since year is always supplied to this function.
- In `scenario.jl`, `change heating_thermal_load_reduction_with_ghp_kw` to `space_heating_thermal_load_reduction_with_ghp_kw` to be more explicit
- Round Hot and Cold TES size result to 0 digits
- Use CoolProp to get water properties for Hot and Cold TES based on average of temperature inputs
### Fixed
- `Wind` evaluations with BAU - was temporarily broken because of an unconverted **year_one** -> **annual** expected name
- Fixed calculation of **year_one_coincident_peak_cost_before_tax** in `ElectricTariff` results to correctly calculate before-tax value. Previously, the after-tax value was being calculated for this field instead.
- Fixed `outage_simulator` to work with sub-hourly outage simulation scenarios
- Fixed a bug which threw an error when providing time-series thermal load inputs in a scenario inputs .json.
- Fixed calculation of ["Financial"]["lifecycle_om_costs_before_tax_bau"] (was previously showing after tax result)
- Added **bau_annual_emissions_tonnes_SO2** to the bau_outputs dict in results.jl and removed duplicate **bau_annual_emissions_tonnes_NOx** result
### Removed
- Removed duplicate **thermal_production_hot_water_or_steam** field from the absorption chiller defaults response dictionary. 

## v0.25.0
### Added
- multi-node MPC modeling capability
- more MPC outputs (e.g. Costs, ElectricStorage.to_load_series_kw)
- throw error if outage_durations and outage_probabilities not the same length
- throw error if length of outage_probabilities is >= 1 and sum of outage_probabilities is not equal to 1
- small incentive to minimize unserved load in each outage, not just the max over outage start times (makes expected outage results more realist and fixes same inputs giving different results)
- add `Outages` output **generator_fuel_used_per_outage** which is the sum over backup generators
### Changed
- remove _series from non-timeseries outage output names
- make the use of _ in multiple outages output names consistent
- updates multiple outage test values that changed due to fixing timestep bug
- Updated the following default values:
   - PV, Wind, Storage, CHP, GHP, Hot Water Storage, Cold Water Storage, Electric Storage: **federal_itc_fraction(PV,Wind, CHP,GHP)** and **total_itc_fraction(Hot Water Storage, Cold Water Storage, Electric Storage)** to 0.3 (30%)
   - PV, Wind, Storage, CHP, GHP, Hot Water Storage, Cold Water Storage, Electric Storage: **macrs_bonus_fraction** to 0.8 (80%)
   - Hot Water Storage and Cold Water Storage: **macrs_itc_reduction** to 0.5 (50%)
   - Hot Water Storage and Cold Water Storage: **macrs_option_years** to 7 years
### Fixed
- PV results for all multi-node scenarios
- MPC objective definition w/o ElectricStorage
- fixed mulitple outages timestep off-by-one bug
### Removed 
- Wind ITC no longer determined based on size class. Removed all size class dependencies from wind.jl

## v0.24.0
### Changed
- Major name change overall for outputs/results. Changed energy-related outputs with "year_one" in name to "annual" to reflect that they are actually average annual output values. Changed any "average_annual" naming to "annual" to simplify. Changed `to_tes` and `to_battery` outputs to `to_storage` for consistency
### Added 
- Added **thermal_production_series_mmbtu_per_hour** to CHP results. 
### Removed 
- Removed `Wind` and `Generator` outputs **year_one_energy_produced_kwh** since these techs do not include degradation

## v0.23.0
### Added
- Add **REoptLogger** type of global logger with a standard out to the console and to a dictionary
    - Instantiate `logREopt` as the global logger in `__init()__` function call as a global variable
    - Handle Warn or Error logs to save them along with information on where they occurred
    - Try-catch `core/reopt.jl -> run_reopt()` functions. Process any errors when catching the error.
    - Add Warnings and Errors from `logREopt` to results dictionary. If error is unhandled in REopt, include a stacktrace
    - Add a `status` of `error` to results for consistency
    - Ensure all error text is returned as strings for proper handling in the API
- Add `handle_errors(e::E, stacktrace::V) where {E <: Exception, V <: Vector}` and `handle_errors()` to `core/reopt.jl` to include info, warn and errors from REopt input data processing, optimization, and results processing in the returned dictionary.
- Tests for user-inputs of `ElectricTariff` `demand_lookback_months` and `demand_lookback_range` 
### Changed
- `core/reopt.jl` added try-catch statements to call `handle_errors()` when there is a REopt error (handled or unhandled) and return it to the requestor/user.
### Fixed
- URDB lookback was not incorporated based on the descriptions of how the 3 lookback variables should be entered in the code. Modified `parse_urdb_lookback_charges` function to correct.
- TOU demand for 15-min load was only looking at the first 8760 timesteps.
- Tiered energy rates jsons generated by the webtool errored and could not run.
- Aligned lookback parameter names from URDB with API

## v0.22.0
### Added
- Simulated load function which mimicks the REopt_API /simulated_load endpoint for getting commercial reference building load data from annual or monthly energy data, or blended/hybrid buildings
- `AbsorptionChiller` default values for costs and thermal coefficient of performance (which depend on maximum cooling load and heat transfer medium)
### Changed
- Pruned the unnecessary chp_defaults data that were either zeros or not dependent on `prime_mover` or `size_class`, and reorganized the CHP struct.

## v0.21.0
### Changed
For `CHP` and `SteamTurbine`, the `prime_mover` and/or `size_class` is chosen (if not input) based on the average heating load and the type of heating load (hot water or steam).
 - This logic replicates the current REopt webtool behavior which was implemented based on CHP industry experts, effectively syncing the webtool and the REopt.jl/API behavior.
 - This makes `prime_mover` **NOT** a required input and avoids a lot of other required inputs if `prime_mover` is not input.
 - The two functions made for `CHP` and `SteamTurbine` are exported in `REopt.jl` so they can be exposed in the API for communication with the webtool (or other API users).
### Removed 
`ExistingBoiler.production_type_by_chp_prime_mover` because that is no longer consistent with the logic added above.
 - The logic from 1. is such that `ExistingBoiler.production_type` determines the `CHP.prime_mover` if not specified, not the other way around.
 - If `ExistingBoiler.production_type` is not input, `hot_water` is used as the default.

## v0.20.1
### Added
- `CoolingLoad` time series and annual summary data to results
- `HeatingLoad` time series and annual summary data to results

## v0.20.0
### Added
- `Boiler` tech from the REopt_API (known as NewBoiler in API)
- `SteamTurbine` tech from the REopt_API
### Changed
- Made some modifications to thermal tech results to be consistent with naming conventions of REopt.jl
### Fixed
- Bug for scalar `ElectricTariff.wholesale_rate`
- Bug in which CHP could not charge Hot TES

## v0.19.0
### Changed
The following name changes were made: 
- Change "pct" to "rate_fraction" for "discount", "escalation", names containing "tax_pct" (financial terms)
- Change "pct" to "fraction" for all other variable names (e.g., "min_soc", "min_turndown_")
- Change `prod_factor_series` to `production_factor_series` and rename some internal methods and variables to match
- Change four (4) CHP input field names to spell out `electric` (from `elec`) and `efficiency` (from `effic`) for electric and thermal efficiencies
### Added
- Add schedule-based `FlatLoad`s which take the annual or monthly energy input and create a load profile based on the specified type of schedule. The load is "flat" (the same) for all hours within the chosen schedule.
- Add `addressable_load_fraction` inputs for `SpaceHeatingLoad` and `DomesticHotWaterLoad` which effectively ignores a portion of the entered loads. These inputs can be scalars (applied to all time steps of the year), monthly (applied to the timesteps of each month), or of length 8760 * `time_steps_per_hour`.
- Add a validation error for cooling in the case that the cooling electric load is greater than the total electric load.
  
## v0.18.1
### Removed
- **include_climate_in_objective**, **pwf_emissions_cost_CO2_grid**, and **pwf_emissions_cost_CO2_onsite** unnecessarily included in Site results

## v0.18.0
### Added
- Add geothermal heat pump (`GHP`), also known as ground-source heat pump (GSHP), to the REopt model for serving heating and cooling loads (typically the benefits include electrifying the heating load and improving the efficiency of cooling).
    - The unregistered `GhpGhx` package (https://github.com/NREL/GhpGhx.jl) is a "conditional" dependency of REopt by using the Requires.jl package, and this package sizes the ground heat exchanger (GHE) and gets the hourly electric consumption of the `GHP` for the specified heating and cooling loads that it serves.
    - The `GhpGhx` module calls for sizing the GHE can only be done if you first "add https://github.com/NREL/GhpGhx.jl" to the environment and then load the package by "using GhpGhx" before running REopt with `GHP`.
    - The `GHP` size and dispatch of the different `GHP` options is pre-determined by the `GhpGhx` package, so the REopt model just chooses one or none of the `GHP` options with a binary decision variable.
### Changed
- Change default value for `wind.jl` **operating_reserve_required_pct** from 0.1 to 0.5 (only applicable when **off_grid_flag**=_True_.)
- allow user to specify emissions_region in ElectricUtility, which is used instead of lat/long to look up AVERT data if emissions factors aren't provided by the user
- Updated results keys in `results/absorption_chiller.jl`
### Fixed
- Add **wholesale_rate** and **emissions_factor_series_lb_\<pollutant\>_per_kwh** inputs to the list of inputs that `dictkeys_tosymbols()` tries to convert to type _Array{Real}_. Due to serialization, when list inputs come from the API, they are of type _Array{Any}_ so must be converted to match type required by the constructors they are passed to.
- Fixed bug in calcuation of power delivered to cold thermal storage by the electric chiller in `results/existing_chiller.jl`.

## v0.17.0
### Added
- Emissions
    - add emissions factors for CO2, NOx, SO2, and PM25 to inputs of all fuel burning technologies
    - add emissions factor series for CO2, NOx, SO2, and PM25 to `ElectricUtility` inputs and use [AVERT v3.2](https://www.epa.gov/avert/download-avert) (2021 data) if not provided
    - add `include_climate_in_objective` and `include_health_in_objective` to `Settings` inputs
    - constrain CO2 emissions based on `CO2_emissions_reduction_min_pct`, `CO2_emissions_reduction_max_pct`, and `include_exported_elec_emissions_in_total` added to `Site` inputs
    - add emissions costs to `Financial` inputs and use EASIUR data for NOx, SO2, and PM25 if not provided
    - report emissions and their cost in `Site` (on-site and total) and `ElectricUtility` (grid) results
    - calculate `breakeven_cost_of_emissions_reduction_per_tonnes_CO2` for `Financial` results
- Renewable energy percentage
    - calculate renewable energy percentage (electric only and total) and add to `Site` results
    - add `renewable_electricity_min_pct`, `renewable_electricity_max_pct`, and `include_exported_renewable_electricity_in_total` to `Site` inputs
    - add `fuel_renewable_energy_pct` input for all fuel burning technologies
    - constrain renewable electricity percentage based on user inputs
- Add "Emissions and Renewable Energy Percent" testset
### Changed
- Allow Wind tech to be included when `off_grid_flag` is true
- Add `operating_reserve_required_pct` to Wind struct and incorporate wind into operating reserve constraints
- Add hot, cold TES results for MPC model
- Update documentation and add `docs/devdeploy.jl` to locally host the REopt.jl documentation 
- Make `ExistingBoiler` `fuel_cost_per_mmbtu` a required input
- In `production_factor.jl`, include lat-long coordinates if-statement to determine whether the "nsrdb" dataset should be used in call to PVWatts. Accounts for recent updates to NSRDB data used by PVWatts (v6). If outside of NSRDB range, use "intl" (international) dataset.
- Don't trigger GitHub 'Run test' workflow on a push that only changes README.md and/or CHANGELOG.md
- Avoid triggering duplicate GitHub workflows. When pushing to a branch that's in a PR, only trigger tests on the push not on the PR sync also.
### Fixed
- Bug fix to constrain dvCurtail in `time_steps_without_grid`
- Bug fix to report accurate wind ["year_one_to_load_series_kw"] in results/wind.jl (was previously not accounting for curtailed wind)

## v0.16.2
### Changed
- Update PV defaults to tilt=10 for rooftop, tilt = abs(lat) for ground mount, azimuth = 180 for northern lats, azimuth = 0 for southern lats.
### Fixed
- bug fix for Generator inputs to allow for time_steps_per_hour > 1
- change various `Float64` types to `Real` to allow integers too

## v0.16.1
### Fixed
- bug fix for outage simulator when `microgrid_only=true`

## v0.16.0
### Added
Allows users to model "off-grid" systems as a year-long outage: 
- add flag to "turn on" off-grid modeling `Settings.off_grid_flag` 
- when `off_grid_flag` is "true", adjust default values in core/ `electric_storage`, `electric_load`, `financial`, `generator`, `pv` 
- add operating reserve requirement inputs, outputs, and constraints based on load and PV generation 
- add minimum load met percent input and constraint
- add generator replacement year and cost (for off-grid and on-grid) 
- add off-grid additional annual costs (tax deductible) and upfront capital costs (depreciable via straight line depreciation)
### Changed
Name changes: 
- consistently append `_before_tax` and `_after_tax` to results names 
- change all instances of `timestep` to `time_step` and `timesteps` to `time_steps`
Other changes:
- report previously missing lcc breakdown components, all reported in `results/financial.jl`  
- change variable types from Float to Real to allow users to enter Ints (where applicable)
- `year_one_coincident_peak_cost_after_tax` is now correctly multiplied by `(1 - p.s.financial.offtaker_tax_pct)`

## v0.15.2
### Fixed
- bug fix for 15 & 30 minute electric, heating, and cooling loads
- bug fix for URDB fixed charges
- bug fix for default `Wind` `installed_cost_per_kw` and `federal_itc_pct`

## v0.15.1
### Added
- add `AbsorptionChiller` technology
- add `ElectricStorage.minimum_avg_soc_fraction` input and constraint

## v0.15.0
### Fixed
- bug fix in outage_simulator
### Changed
- allow Real Generator inputs (not just Float64)
- add "_series" to "Outages" outputs that are arrays [breaking]

## v0.14.0
### Changed
- update default values from v2 of API [breaking]
### Added
- add ElectricStorage degradation accounting and maintenance strategies
- finish cooling loads

## v0.13.0
### Added
- add FlexibleHVAC model (still testing)
- start thermal energy storage modeling
- add `ExistingBoiler` and `ExistingChiller`
- add `MPCLimits` inputs:
    - `grid_draw_limit_kw_by_time_step`
    - `export_limit_kw_by_time_step`
### Changed
- refactor `Storage` as `ElectricStorage`
### Fixed
- fix bugs for time_steps_per_hour != 1


## v0.12.4
### Removed
- rm "Lite" from docs
### Changed
- prioritize `urdb_response` over `urdb_label` in `ElectricTariff`

## v0.12.3
### Added
- add utils for PVwatts: `get_ambient_temperature` and `get_pvwatts_prodfactor`

## v0.12.2
### Added
- add CHP technology, including supplementary firing
- add URDB "sell" value from `energyratestructure` to wholesale rate
- update docs
### Changed
- allow annual or monthly energy rate w/o demand rate
- allow integer latitude/longitude

## v0.12.1
### Added
- add ExistingBoiler and CRB heating loads

## v0.12.0
### Changed
- change all output keys starting with "total_" or "net_" to "lifecycle_" (except "net_present_cost")
- update pv results for single PV in an array
### Fixed
- bug fix in urdb.jl when rate_name not found

## v0.11.0
### Added
- add ElectricLoad.blended_doe_reference_names & blended_doe_reference_percents
- add ElectricLoad.monthly_totals_kwh builtin profile scaling
- add ElectricTariff inputs: `add_monthly_rates_to_urdb_rate`, `tou_energy_rates_per_kwh`, 
    `add_tou_energy_rates_to_urdb_rate`, `coincident_peak_load_charge_per_kw`, `coincident_peak_load_active_time_steps`
### Fixed
- handle multiple PV outputs

## v0.10.0
### Added
- add modeling capability for tiered rates (energy, TOU demand, and monthly demand charges)
    - all of these tiered rates require binaries, which are conditionally added to the model
- add modeling capability for lookback demand charges
- add more outputs from the API (eg. `initial_capital_costs`)
- add option to run Business As Usual scenario in parallel with optimal scenario (default is `true`)
- add incentives (and cost curves) to `Wind` and `Generator`
### Changed
- removed "_us_dollars" from all names and generally aligned names with API
- renamed `outage_start(end)_time_step` to `outage_start(end)_time_step`
### Fixed
- fixed bug in URDB fixed charges

## v0.9.0
### Changed
- `ElectricTariff.NEM` boolean is now determined by `ElectricUtility.net_metering_limit_kw` (true if limit > 0)
### Added
- add `ElectricUtility` inputs for `net_metering_limit_kw` and `interconnection_limit_kw`
- add binary choice for net metering vs. wholesale export
- add `ElectricTariff.export_rate_beyond_net_metering_limit` input (scalar or vector allowed)
- add `can_net_meter`, `can_wholesale`, `can_export_beyond_nem_limit` tech inputs (`PV`, `Wind`, `Generator`)

## v0.8.0
### Added
- add `Wind` module, relying on System Advisor Model Wind module for production factors and Wind Toolkit for resource data
- new `ElectricTariff` input options:
    - `urdb_utility_name` and `urdb_rate_name`
    - `blended_annual_energy_rate` and `blended_annual_demand_rate`
- add two capabilities that require binary variables:
    - tax, production, and capacity incentives for PV (compatible with any energy generation technology)
    - technology cost curve modeling capability
    - both of these capabilities are only used for the technologies that require them (based on input values), unlike the API which always models these capabilities (and therefore always includes the binary variables).
- Three new tests: Wind, Blended Tariff and Complex Incentives (which aligns with API results)
### Changed
- `cost_per_kw[h]` input fields are now `installed_cost_per_kw[h]` to distinguish it from other costs like `om_cost_per_kw[h]`
- Financial input field refactored: `two_party_ownership` -> `third_party_ownership`
- `total_itc_pct` -> `federal_itc_pct` on technology inputs

## v0.7.3
### Fixed
- outage results processing would fail sometimes when an integer variable was not exact (e.g. 1.000000001)
- fixed `simulate_outages` for revised results formats (key names changed to align with the REopt API)

## v0.7.2
### Added
- add PV.production_factor_series input (can skip PVWatts call)
- add `run_mpc` capability, which dispatches DER for minimum energy cost over an arbitrary time horizon

## v0.7.1
### Fixed
- ElectricLoad.city default is empty string, must be filled in before annual_kwh look up

## v0.7.0
### Removed
- removed Storage.can_grid_export
### Added
- add optional integer constraint to prevent simultaneous export and import of power
- add warnings when adding integer variables
- add ability to add LinDistFlow constraints to multinode models
### Changed
- no longer require `ElectricLoad.city` input (look up ASHRAE climate zone from lat/lon)
- compatible with Julia 1.6

## v0.6.0
### Added
- add multi-node (site) capability for PV and Storage
- started documentation process using Github Pages and Documenter.jl
### Changed
- restructured outputs to align with the input structure, for example top-level keys added for `ElectricTariff` and `PV` in the outputs

## v0.5.3
### Changed
- compatible with Julia 1.5

## v0.5.2
### Fixed
- outage_simulator.jl had bug with summing over empty `Any[]`
### Added
- add optional `microgrid_only` arg to simulate_outages

## v0.5.1
### Added
- added outage dispatch outputs and speed up their derivation
### Removed
- removed redundant generator minimum turn down constraint

## v0.5.0
### Fixed
- handle missing input key for `year_one_soc_series_pct` in `outage_simulator` 
- remove erroneous `total_unserved_load = 0` output
- `dvUnservedLoad` definition was allowing microgrid production to storage and curtailment to be double counted towards meeting critical load
### Added
- add `unserved_load_per_outage` output

## v0.4.1
### Fixed
- removed `total_unserved_load` output because it can take hours to generate and can error out when outage indices are not consecutive
### Added
- add @info for time spent processing results

## v0.4.0
### Added
- add `simulate_outages` function (similar to REopt API outage simulator)
- removed MutableArithmetics package from Project.toml (since JuMP now has method for `value(::MutableArithmetics.Zero)`)
- add outage related outputs:
    - Generator_mg_kw
    - mg_Generator_upgrade_cost
    - mg_Generator_fuel_used
    - mg_PV_upgrade_cost
    - mg_storage_upgrade_cost
    - dvUnservedLoad array
    - max_outage_cost_per_outage_duration
### Changed
- allow value_of_lost_load_per_kwh values to be subtype of Real (rather than only Real)
- add `run_reopt` method for scenario Dict

## v0.3.0
### Added
- add separate decision variables and constraints for microgrid tech capacities
    - new Site input `mg_tech_sizes_equal_grid_sizes` (boolean), when _false_ the microgrid tech capacities are constrained to be <= the grid connected tech capacities
### Fixed
- allow non-integer `outage_probabilities`
- correct `total_unserved_load` output
- don't `add_min_hours_crit_ld_met_constraint` unless `min_resil_time_steps <= length(elecutil.outage_time_steps)`

## v0.2.0
### Added
- add support for custom ElectricLoad `loads_kw` input
- include existing capacity in microgrid upgrade cost
    - previously only had to pay to upgrade new capacity
- implement ElectricLoad `loads_kw_is_net` and `critical_loads_kw_is_net`
    - add existing PV production to raw load profile if `true`
- add `min_resil_time_steps` input and optional constraint for minimum time_steps that critical load must be met in every outage
### Fixed
- enforce storage cannot grid charge

## v0.1.1 Fix build.jl
deps/build.jl had a relative path dependency, fixed with an absolute path.

## v0.1.0 Initial release
This package is currently under development and only has a subset of capabilities of the REopt model used in the REopt API. For example, the Wind model, tiered electric utility tariffs, and piecewise linear cost curves are not yet modeled in this code. However this code is easier to use than the API (only dependencies are Julia and a solver) and has a novel model for uncertain outages.
