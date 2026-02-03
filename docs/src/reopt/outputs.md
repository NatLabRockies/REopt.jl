# Outputs

## Financial outputs
```@docs
REopt.add_financial_results
```

## Financial outputs adders with BAU Scenario
```@docs
REopt.combine_results(p::REoptInputs, bau::Dict, opt::Dict, bau_scenario::BAUScenario)
```

## ElectricTariff outputs
```@docs
REopt.add_electric_tariff_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict)
```

## ElectricLoad outputs
```@docs
REopt.add_electric_load_results
```

## ElectricUtility outputs
```@docs
REopt.add_electric_utility_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict)
```

## PV outputs
```@docs
REopt.add_pv_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict)
```

## Wind outputs
```@docs
REopt.add_wind_results
```

## ElectricStorage outputs
```@docs
REopt.add_electric_storage_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict, ::String)
```

## HotThermalStorage outputs
```@docs
REopt.add_hot_storage_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict, ::String)
```

## HighTempThermalStorage outputs
```@docs
REopt.add_high_temp_storage_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict, ::String)
REopt.add_high_temp_thermal_storage_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict, ::String)
```

## ColdThermalStorage outputs
```@docs
REopt.add_cold_storage_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict, ::String)
```

## Generator outputs
```@docs
REopt.add_generator_results(::JuMP.AbstractModel, ::REoptInputs, ::Dict)
```

## ExistingBoiler outputs
```@docs
REopt.add_existing_boiler_results
```

## CHP outputs
```@docs
REopt.add_chp_results
```

## Boiler outputs
```@docs
REopt.add_boiler_results
```

## HeatingLoad outputs
```@docs
REopt.add_heating_load_results
```

## CoolingLoad outputs
```@docs
REopt.add_cooling_load_results
```

## Outages outputs
```@docs
REopt.add_outage_results
```

## AbsorptionChiller outputs
```@docs
REopt.add_absorption_chiller_results
```

## FlexibleHVAC outputs
```@docs
REopt.add_flexible_hvac_results
```

## SteamTurbine outputs
```@docs
REopt.add_steam_turbine_results
```

## HydrogenLoad outputs
```@docs
REopt.add_hydrogen_load_results
```

## Electrolyzer outputs
```@docs
REopt.add_electrolyzer_results
```

## Compressor outputs
```@docs
REopt.add_compressor_results
```

## HydrogenStorage outputs
```@docs
REopt.add_hydrogen_storage_results
```

## FuelCell outputs
```@docs
REopt.add_fuel_cell_results
```

## CST outputs
```@docs
REopt.add_concentrating_solar_results
```
