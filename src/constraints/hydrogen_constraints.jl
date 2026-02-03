# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function add_electrolyzer_constraints(m, p; _n="") 

	if !isempty(p.techs.electrolyzer)
        
        #Constraint: Fuel cell cannot supply electrolyzer
        # TODO: Update to combustion techs (chp, fuel cell, generator) can't supply electrolyzer
        @constraint(m, [ts in p.time_steps], 
            sum(m[Symbol("dvProductionToElectrolyzer"*_n)][t, ts] for t in p.techs.fuel_cell) == 0
        )

        #Constraint: Electricity required for production of hydrogen - with grid
        @constraint(m, [ts in p.time_steps_with_grid], 
            sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.electrolyzer)
            ==
            sum(m[Symbol("dvProductionToElectrolyzer"*_n)][t, ts] for t in p.techs.elec)
            + m[Symbol("dvGridToElectrolyzer"*_n)][ts]
            + sum(m[Symbol("dvStorageToElectrolyzer"*_n)][b, ts] for b in p.s.storage.types.elec) 
        )
        
        #Constraint: Electricity required for production of hydrogen - no grid
        @constraint(m, [ts in p.time_steps_without_grid], 
            sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.electrolyzer)
            ==
            sum(m[Symbol("dvProductionToElectrolyzer"*_n)][t, ts] for t in p.techs.elec)
            + sum(m[Symbol("dvStorageToElectrolyzer"*_n)][b, ts] for b in p.s.storage.types.elec) 
        )

        #Constraint: Electricity required for production of hydrogen - grid
        @constraint(m, [ts in p.time_steps_with_grid], 
            (p.hours_per_time_step * sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.electrolyzer)) 
            >=
            sum(p.s.storage.attr[b].soc_min_fraction * m[Symbol("dvStorageEnergy"*_n)][b] for b in p.s.storage.types.hydrogen)
        )
        
        #Constraint: Dispatch hydrogen produced to compressor
        if p.s.electrolyzer.require_compression
            @constraint(m, [ts in p.time_steps], 
                (p.hours_per_time_step * sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.electrolyzer))
                / p.s.electrolyzer.efficiency_kwh_per_kg 
                ==
                (p.hours_per_time_step * sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.compressor)) 
                / p.s.compressor.efficiency_kwh_per_kg
            )
        else
            @constraint(m, [ts in p.time_steps], 
                (p.hours_per_time_step * sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.electrolyzer))
                / p.s.electrolyzer.efficiency_kwh_per_kg 
                ==
                sum(m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for b in p.s.storage.types.hydrogen, t in p.techs.electrolyzer)
            )
        end

        m[:TotalElectrolyzerPerUnitProdOMCosts] = @expression(m, p.third_party_factor * p.pwf_om *
            sum(p.s.electrolyzer.om_cost_per_kwh * p.hours_per_time_step *
            m[:dvRatedProduction][t, ts] for t in p.techs.electrolyzer, ts in p.time_steps)
        )
    end

end

function add_compressor_constraints(m, p; _n="") 

	if !isempty(p.techs.compressor)
    
        #Constraint: Electricity required for compression of hydrogen produced from electrolyzer - with grid
        @constraint(m, [ts in p.time_steps_with_grid], 
            sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.compressor)
            ==
            sum(m[Symbol("dvProductionToCompressor"*_n)][t, ts] for t in p.techs.elec)
            + m[Symbol("dvGridToCompressor"*_n)][ts]
            + sum(m[Symbol("dvStorageToCompressor"*_n)][b, ts] for b in p.s.storage.types.elec) 
        )

        #Constraint: Fuel cell cannot supply compressor
        # TODO: Update to combustion techs (chp, fuel cell, generator) can't supply compressor
        @constraint(m, [ts in p.time_steps], 
            sum(m[Symbol("dvProductionToCompressor"*_n)][t, ts] for t in p.techs.fuel_cell) == 0
        )
        
        #Constraint: Electricity required for compression of hydrogen produced from electrolyzer - no grid
        @constraint(m, [ts in p.time_steps_without_grid], 
            sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.compressor)
            ==
            sum(m[Symbol("dvProductionToCompressor"*_n)][t, ts] for t in p.techs.elec)
            + sum(m[Symbol("dvStorageToCompressor"*_n)][b, ts] for b in p.s.storage.types.elec) 
        )
        
        #Constraint: Compressor charges hydrogen storage
        if p.s.electrolyzer.require_compression
            @constraint(m, [ts in p.time_steps], 
                (p.hours_per_time_step * sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.compressor)) 
                / p.s.compressor.efficiency_kwh_per_kg 
                ==
                sum(m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for b in p.s.storage.types.hydrogen, t in p.techs.compressor) 
            )
        end

        m[:TotalCompressorPerUnitProdOMCosts] = @expression(m, p.third_party_factor * p.pwf_om *
            sum(p.s.compressor.om_cost_per_kwh * p.hours_per_time_step *
            m[:dvRatedProduction][t, ts] for t in p.techs.compressor, ts in p.time_steps)
        )
    end

end

function add_fuel_cell_constraints(m, p; _n="")

    if !isempty(p.techs.fuel_cell)        
        m[:TotalFuelCellPerUnitProdOMCosts] = @expression(m, p.third_party_factor * p.pwf_om *
            sum(p.s.fuel_cell.om_cost_per_kwh * p.hours_per_time_step *
            m[:dvRatedProduction][t, ts] for t in p.techs.fuel_cell, ts in p.time_steps)
        )
    end
end
