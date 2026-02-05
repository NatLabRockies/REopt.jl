# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
module REopt

export
    Scenario,
    BAUScenario,
    REoptInputs,
    run_reopt,
    build_reopt!,
    reopt_results,
    simulate_outages,
    add_variables!,
    add_objective!,
    LinDistFlow,
    MPCScenario,
    MPCInputs,
    run_mpc,
    build_mpc!, 
    backup_reliability,
    get_chp_defaults_prime_mover_size_class,
    get_steam_turbine_defaults_size_class,
    simulated_load,
    get_absorption_chiller_defaults,
    avert_emissions_profiles,
    cambium_profile,
    easiur_data,
    get_existing_chiller_default_cop,
    get_electric_heater_defaults,
    get_ashp_defaults,
    get_pv_cost_params,
    get_sector_defaults,
    get_load_metrics

import HTTP
import JSON
using LinDistFlow  # required to export LinDistFlow
import LinDistFlow 
const LDF = LinDistFlow
using JuMP
using JuMP.Containers: DenseAxisArray
using Logging
using DelimitedFiles
using Dates
import MathOptInterface
import Dates: daysinmonth, Date, isleapyear
import DelimitedFiles: readdlm
const MOI = MathOptInterface
using ArchGDAL
using Statistics
using Roots: fzero  # for IRR
global hdl = nothing
using JLD
using Requires
using CoolProp
using LinearAlgebra
using CSV
using DataFrames

function __init__()
    @require GhpGhx="7ce85f02-24a8-4d69-a3f0-14b5daa7d30c" println("using GhpGhx module in REopt")
end

const EXISTING_BOILER_EFFICIENCY = 0.8
const GAL_PER_M3 = 264.172              # [gal/m^3]
const KWH_PER_GAL_DIESEL = 40.7         # [kWh/gal_diesel] higher heating value of diesel
const KWH_PER_MMBTU = 293.07107         # [kWh/mmbtu]
const KWH_THERMAL_PER_TONHOUR = 3.51685
const TONNE_PER_LB = 1/2204.62          # [tonne/lb]
const TONNE_PER_MMBTU_HOUR = 0.012      # [tonne/mmbtu-hour]
const FUEL_TYPES = ["natural_gas", "landfill_bio_gas", "propane", "diesel_oil"]
const BIG_NUMBER = 1.0e10  #used for max size.  TODO use this number elsewhere.
const PRIME_MOVERS = ["recip_engine", "micro_turbine", "combustion_turbine", "fuel_cell"]  #TODO replace `prime_movers` references in CHP code
const HOT_WATER_OR_STEAM = ["steam", "hot_water"]  #TODO replace references to this list in chp, boiler
const CST_TYPES = ["ptc", "lf", "mst", "swh_evactube", "swh_flatplate"]
const FUEL_DEFAULTS = Dict(
    "fuel_renewable_energy_fraction" => Dict(
        "natural_gas"=>0.0,
        "landfill_bio_gas"=>1.0,
        "propane"=>0.0,
        "diesel_oil"=>0.0
    ),
    "emissions_factor_lb_CO2_per_mmbtu" => Dict(
        "natural_gas"=>117.03,
        "landfill_bio_gas"=>115.38,
        "propane"=>139.16,
        "diesel_oil"=>163.61
    ),
    "emissions_factor_lb_NOx_per_mmbtu" => Dict(
        "natural_gas"=>0.09139,
        "landfill_bio_gas"=>0.14,
        "propane"=>0.15309,
        "diesel_oil"=>0.56
    ),
    "emissions_factor_lb_SO2_per_mmbtu" => Dict(
        "natural_gas"=>0.000578592,
        "landfill_bio_gas"=>0.045,
        "propane"=>0.0,
        "diesel_oil"=>0.28897737
    ),
    "emissions_factor_lb_PM25_per_mmbtu" => Dict(
        "natural_gas"=>0.007328833,
        "landfill_bio_gas"=>0.02484,
        "propane"=>0.009906836,
        "diesel_oil"=>0.0
    )
)
const EMISSIONS_DECREASE_DEFAULTS = Dict(
    "CO2e" => 0.0459,
    "NOx" => 0.0459,
    "SO2" => 0.0459,
    "PM25" => 0.0459
)
const INDICATOR_COMPATIBLE_SOLVERS = ["CPLEX","Xpress"]

include("logging.jl")

include("core/types.jl")
include("core/utils.jl")

include("core/settings.jl")
include("core/site.jl")
include("core/financial.jl")
include("core/pv.jl")
include("core/wind.jl")
include("core/energy_storage/storage.jl")
include("core/energy_storage/electric_storage.jl")
include("core/energy_storage/thermal_storage.jl")
include("core/generator.jl")
include("core/doe_commercial_reference_building_loads.jl")
include("core/electric_load.jl")
include("core/existing_boiler.jl")
include("core/boiler.jl")
include("core/existing_chiller.jl")
include("core/flexible_hvac.jl")
include("core/heating_cooling_loads.jl")
include("core/absorption_chiller.jl")
include("core/electric_utility.jl")
include("core/production_factor.jl")
include("core/urdb.jl")
include("core/electric_tariff.jl")
include("core/chp.jl")
include("core/ghp.jl")
include("core/steam_turbine.jl")
include("core/electric_heater.jl")
include("core/cst_ssc.jl")
include("core/cst.jl")
include("core/ashp.jl")
include("core/scenario.jl")
include("core/bau_scenario.jl")
include("core/reopt_inputs.jl")
include("core/bau_inputs.jl")
include("core/cost_curve.jl")
include("core/simulated_load.jl")

include("constraints/outage_constraints.jl")
include("constraints/storage_constraints.jl")
include("constraints/flexible_hvac.jl")
include("constraints/load_balance.jl")
include("constraints/tech_constraints.jl")
include("constraints/electric_utility_constraints.jl")
include("constraints/generator_constraints.jl")
include("constraints/cost_curve_constraints.jl")
include("constraints/production_incentive_constraints.jl")
include("constraints/thermal_tech_constraints.jl")
include("constraints/chp_constraints.jl")
include("constraints/operating_reserve_constraints.jl")
include("constraints/battery_degradation.jl")
include("constraints/ghp_constraints.jl")
include("constraints/steam_turbine_constraints.jl")
include("constraints/renewable_energy_constraints.jl")
include("constraints/emissions_constraints.jl")

include("mpc/structs.jl")
include("mpc/scenario.jl")
include("mpc/inputs.jl")
include("mpc/constraints.jl")

include("core/techs.jl")
include("results/results.jl")
include("results/site.jl")
include("results/electric_tariff.jl")
include("results/electric_utility.jl")
include("results/proforma.jl")
include("results/financial.jl")
include("results/generator.jl")
include("results/pv.jl")
include("results/electric_storage.jl")
include("results/thermal_storage.jl")
include("results/outages.jl")
include("results/wind.jl")
include("results/electric_load.jl")
include("results/heating_cooling_load.jl")
include("results/existing_boiler.jl")
include("results/boiler.jl")
include("results/existing_chiller.jl")
include("results/absorption_chiller.jl")
include("results/chp.jl")
include("results/flexible_hvac.jl")
include("results/ghp.jl")
include("results/steam_turbine.jl")
include("results/electric_heater.jl")
include("results/cst.jl")
include("results/ashp.jl")

include("core/reopt.jl")
include("core/reopt_multinode.jl")
include("outagesim/outage_simulator.jl")
include("outagesim/backup_reliability.jl")

include("lindistflow/extend.jl")

include("mpc/results.jl")
include("mpc/model.jl")
include("mpc/model_multinode.jl")

end
