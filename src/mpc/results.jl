# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
MPC Scenarios will return a results Dict with the following keys: 
- `ElectricStorage`
- `HotThermalStorage`
- `ColdThermalStorage` 
- `ElectricTariff`
- `ElectricUtility`
- `PV`
- `Generator`
"""
function mpc_results(m::JuMP.AbstractModel, p::MPCInputs; _n="")
	tstart = time()
    d = Dict{String, Any}()

    add_electric_load_results(m, p, d; _n)

    for b in p.s.storage.types.elec
        if p.s.storage.attr[b].size_kwh > 0
            add_electric_storage_results(m, p, d, b; _n)
        end
    end

    for b in p.s.storage.types.hot
        if p.s.storage.attr[b].size_kwh > 0
            add_hot_storage_results(m, p, d, b; _n)
        end
    end

    for b in p.s.storage.types.cold
        if p.s.storage.attr[b].size_kwh > 0
            add_cold_storage_results(m, p, d, b; _n)
        end
    end

    add_electric_tariff_results(m, p, d; _n)
    add_electric_utility_results(m, p, d; _n)

	if !isempty(p.techs.pv)
        add_pv_results(m, p, d; _n)
	end

	if !isempty(p.techs.gen)
        add_generator_results(m, p, d; _n)
	end

    d["Costs"] = value(m[Symbol("Costs"*_n)])
	
	time_elapsed = time() - tstart
	@info "Results processing took $(round(time_elapsed, digits=3)) seconds."
	
	# if !isempty(p.s.electric_utility.outage_durations) && isempty(_n)  # outages not included in multinode model
    #     tstart = time()
	# 	add_outage_results(m, p, d)
    #     time_elapsed = time() - tstart
    #     @info "Outage results processing took $(round(time_elapsed, digits=3)) seconds."
	# end
	return d
end
