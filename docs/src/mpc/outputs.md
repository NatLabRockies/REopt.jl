# [Outputs](@id mpc-outputs)
```@docs
REopt.mpc_results
```

## MPC ElectricStorage outputs
```@docs
REopt.add_electric_storage_results(::JuMP.AbstractModel, ::MPCInputs, ::Dict, ::String)
```

## MPC HotThermalStorage outputs
```@docs
REopt.add_hot_storage_results(::JuMP.AbstractModel, ::MPCInputs, ::Dict, ::String)
```

## MPC ColdThermalStorage outputs
```@docs
REopt.add_cold_storage_results(::JuMP.AbstractModel, ::MPCInputs, ::Dict, ::String)
```

## MPC ElectricTariff outputs
```@docs
REopt.add_electric_tariff_results(::JuMP.AbstractModel, ::MPCInputs, ::Dict)
```

## MPC ElectricUtility outputs
```@docs
REopt.add_electric_utility_results(::JuMP.AbstractModel, ::MPCInputs, ::Dict)
```

## MPC PV outputs
```@docs
REopt.add_pv_results(::JuMP.AbstractModel, ::MPCInputs, ::Dict)
```

## MPC Generator outputs
```@docs
REopt.add_generator_results(::JuMP.AbstractModel, ::MPCInputs, ::Dict)
```

