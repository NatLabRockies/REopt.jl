# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function add_water_power_constraints(m,p; _n="")
	@info "Adding constraints for water_power"
	
	if p.s.water_power.computation_type == "average_power_conversion" # This is a simplified constraint that uses an average conversion for water flow and kW output
		@info "Adding water_power power output constraint using the average power conversion"

		Hydro_techs = p.techs.water_power_turbines
		for t in 1:Int(length(Hydro_techs))
			@constraint(m, [ts in p.time_steps],
					m[Symbol("dvRatedProduction"*_n)][Hydro_techs[t],ts] == m[Symbol("dvWaterOutFlow"*_n)][Hydro_techs[t],ts] * (1/p.s.water_power.average_cubic_meters_per_second_per_kw)* (1- (t/1000))  # convert to kW/time step, for instance: m3/15min  * kwh/m3 * (0.25 hrs/1hr); the "1 - (t/1000)" is for turbine prioritization
						)
		end

	#TODO: add other formuations
	#elseif p.s.water_power.computation_type == "" 
			
	#elseif p.s.water_power.computation_type == ""
		
	else 
		throw(@error("Invalid input for the computation_type field"))
	end

	# Create variable for the upper reservoir capacity

	dv = "dvUpperReservoirCapacity"*_n
	m[Symbol(dv)] = @variable(m, base_name=dv)
	@constraint(m, p.s.upper_reservoir.minimum_capacity_cubic_meters_upper_reservoir <= m[Symbol(dv)] <= p.s.upper_reservoir.maximum_capacity_cubic_meters_upper_reservoir)
	
	# The upper reservoir water volume must be between the max and min levels
	@constraint(m, [ts in p.time_steps],
		m[Symbol("dvWaterVolume"*_n)][ts] <= p.s.upper_reservoir.maximum_volume_fraction_upper_reservoir * m[Symbol("dvUpperReservoirCapacity"*_n)]
				)
	@constraint(m, [ts in p.time_steps],
		m[Symbol("dvWaterVolume"*_n)][ts] >= p.s.upper_reservoir.minimum_volume_fraction_upper_reservoir * m[Symbol("dvUpperReservoirCapacity"*_n)] 
				)
	
	# Water flow rate from all turbines combined is above the required minimum water flow
	@constraint(m, [ts in p.time_steps],
		 sum(m[Symbol("dvWaterOutFlow"*_n)][t, ts] for t in p.techs.water_power_turbines) + m[Symbol("dvSpillwayWaterFlow"*_n)][ts] >= p.s.water_power.minimum_water_output_cubic_meter_per_second_total_of_all_turbines   
				)
	
	# Each turbine must meet the minimum water flow requirement of an individual turbine, if it is on
	@constraint(m, [t in p.techs.water_power_turbines, ts in p.time_steps], 
			m[Symbol("dvWaterOutFlow"*_n)][t, ts] >=  m[Symbol("binTurbineActive"*_n)][t,ts]*p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine  
				)
	
	# Upstream Reservoir: The total water volume changes based on the water flow rates
	final_time_step = Int(p.s.settings.time_steps_per_hour * 8760)
	time_steps_without_first_time_step = p.time_steps[2:final_time_step]
	
	@constraint(m, [ts in time_steps_without_first_time_step], 
					m[Symbol("dvWaterVolumeChange"*_n)][ts] == p.s.upper_reservoir.water_inflow_cubic_meter_per_second[ts] - m[Symbol("dvSpillwayWaterFlow"*_n)][ts] - sum(m[Symbol("dvWaterOutFlow"*_n)][t,ts] for t in p.techs.water_power_turbines) + sum(m[Symbol("dvPumpedWaterFlow"*_n)][t,ts] for t in p.techs.water_power_pumps)
				)
	
	@constraint(m, [ts in time_steps_without_first_time_step], 
					m[Symbol("dvWaterVolume"*_n)][ts] == 
					m[Symbol("dvWaterVolume"*_n)][ts-1]  
					+ ((3600/p.s.settings.time_steps_per_hour) * m[Symbol("dvWaterVolumeChange"*_n)][ts])   # The (3600/p.s.settings.time_steps_per_hour) converts from m^3 per second, to m^3 per timestep
				)
	
	@constraint(m, m[Symbol("dvWaterVolume"*_n)][1] == p.s.upper_reservoir.initial_reservoir_volume_fraction_upper_reservoir * m[Symbol("dvUpperReservoirCapacity"*_n)]) 
		
	# Upstream Reservoir: Total water volume must be the same in the beginning and the end
	@constraint(m, m[Symbol("dvWaterVolume"*_n)][1] == m[Symbol("dvWaterVolume"*_n)][maximum(p.time_steps)])
		
	# Limit power output from the water_power turbines:
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[Symbol("dvRatedProduction"*_n)][t,ts] <= m[Symbol("TurbinePowerGenerationMaximum"*_n)][t,ts]) 
	
	# Method for linearizing the product of a binary variable and a continuous variable:
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[Symbol("TurbinePowerGenerationMaximum"*_n)][t,ts] <= m[Symbol("binTurbineActive"*_n)][t,ts] * 1000000)
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[Symbol("TurbinePowerGenerationMaximum"*_n)][t,ts] <= m[Symbol("turbine_power_rating"*_n)][t])
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[Symbol("TurbinePowerGenerationMaximum"*_n)][t,ts] >= m[Symbol("turbine_power_rating"*_n)][t] - (1000000*(1-m[Symbol("binTurbineActive"*_n)][t,ts])))
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[Symbol("TurbinePowerGenerationMaximum"*_n)][t,ts] >= 0)

	# Limit the water flow through the spillway, if a value was input
	if !isnothing(p.s.water_power.spillway_maximum_cubic_meter_per_second)
		@constraint(m, [ts in p.time_steps], m[Symbol("dvSpillwayWaterFlow"*_n)][ts] <= p.s.water_power.spillway_maximum_cubic_meter_per_second)
	end 

	# Set the dvSize for the turbines
	@constraint(m, [t in p.techs.water_power_turbines],
		m[Symbol("dvSize"*_n)][t] >= m[Symbol("turbine_power_rating"*_n)][t]
	)

	# Model a downstream reservoir
	if "downstream_reservoir" in p.s.water_storage
		print("\n Adding downstream reservoir variables and constraints")
		
		final_time_step = Int(p.s.settings.time_steps_per_hour * 8760)
		time_steps_without_first_time_step = p.time_steps[2:final_time_step]

		@constraint(m, [ts in time_steps_without_first_time_step], 
						m[Symbol("dvDownstreamReservoirNetWaterFlow"*_n)][ts] == p.s.downstream_reservoir.tributary_water_inflow_cubic_meter_per_second[ts] + m[Symbol("dvSpillwayWaterFlow"*_n)][ts] + sum(m[Symbol("dvWaterOutFlow"*_n)][t,ts] for t in p.techs.water_power_turbines) - sum(m[Symbol("dvPumpedWaterFlow"*_n)][t,ts] for t in p.techs.water_power_pumps) - m[Symbol("dvDownstreamReservoirWaterOutflow"*_n)][ts]
					)
		
		# Downstream Reservoir: The total water volume changes based on the water flow rates
		@constraint(m, [ts in time_steps_without_first_time_step], m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][ts] == m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][ts-1] + ((3600/p.s.settings.time_steps_per_hour)* (m[Symbol("dvDownstreamReservoirNetWaterFlow"*_n)][ts]))
		)
		
		# Downstream Reservoir: Total water volume must be the same in the beginning and the end
		@constraint(m, m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][1] == m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][maximum(p.time_steps)])

		# Downstream Reservoir: Minimum and maximum water volumes
		@constraint(m, [ts in p.time_steps], m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][ts] >= p.s.downstream_reservoir.minimum_volume_fraction_downstream_reservoir * m[Symbol("dvDownstreamReservoirCapacity"*_n)])
		@constraint(m, [ts in p.time_steps], m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][ts] <= p.s.downstream_reservoir.maximum_volume_fraction_downstream_reservoir * m[Symbol("dvDownstreamReservoirCapacity"*_n)])

		# Downstream Reservoir: define the initial water volume
		@constraint(m, m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][1] == p.s.downstream_reservoir.initial_reservoir_volume_fraction_downstream_reservoir * m[Symbol("dvDownstreamReservoirCapacity"*_n)]) 

		# Downstream Reservoir: constrain the optimized reservoir capacity
		@constraint(m, m[Symbol("dvDownstreamReservoirCapacity"*_n)] >= p.s.downstream_reservoir.minimum_capacity_cubic_meters_downstream_reservoir) 
		@constraint(m, m[Symbol("dvDownstreamReservoirCapacity"*_n)] <= p.s.downstream_reservoir.maximum_capacity_cubic_meters_downstream_reservoir)

		# Downstream Reservoir outflow: minimum and maximum flow rates
		@constraint(m, [ts in p.time_steps], 
						m[Symbol("dvDownstreamReservoirWaterOutflow"*_n)][ts] >= p.s.downstream_reservoir.minimum_outflow_from_downstream_reservoir_cubic_meter_per_second 
			   		)
					
		@constraint(m, [ts in p.time_steps], 
					   m[Symbol("dvDownstreamReservoirWaterOutflow"*_n)][ts] <= p.s.downstream_reservoir.maximum_outflow_from_downstream_reservoir_cubic_meter_per_second
					)
		
		# The pumps cannot act as power generators
		for pump in p.techs.water_power_pumps
			@constraint(m, [ts in p.time_steps], m[Symbol("dvRatedProduction"*_n)][pump,ts] == 0)
		end

		# Ensure that the turbines aren't on when the pumping is happening; binTurbineOrPump is 1 when the turbines are on; binTurbineOrPump is 0 when the pumps are operating
		@constraint(m, [ts in p.time_steps], sum(m[Symbol("binTurbineActive"*_n)][t,ts] for t in p.techs.water_power_turbines) <= p.s.water_power.number_of_turbines * m[Symbol("binTurbineOrPump"*_n)][ts] )
		
		@constraint(m, [ts in p.time_steps], sum(m[Symbol("binPumpingWaterActive"*_n)][t,ts] for t in p.techs.water_power_pumps) <= p.s.water_power.number_of_pumps * (1 - m[Symbol("binTurbineOrPump"*_n)][ts]))
		
		# Each pump must meet the minimum water flow requirement, if it is on
		@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], 
						m[Symbol("dvPumpedWaterFlow"*_n)][t, ts] >= m[Symbol("binPumpingWaterActive"*_n)][t,ts]*p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine
							)
		
		# Set the dvSize for the pumps
		@constraint(m, [t in p.techs.water_power_pumps],
			m[Symbol("dvSize"*_n)][t] == m[Symbol("pump_power_rating"*_n)][t]
		)

		# Pump size constraints
		if p.s.water_power.are_pumps_reversible 
			@constraint(m, [t in p.techs.water_power_pumps], m[Symbol("pump_power_rating"*_n)][t] == p.s.water_power.pump_kw_to_turbine_kw_ratio_for_reversible_pumps *  m[Symbol("turbine_power_rating"*_n)][t])
		else
			@constraint(m, [t in p.techs.water_power_pumps], m[Symbol("pump_power_rating"*_n)][t] >= p.s.water_power.min_kw_pump)
			@constraint(m, [t in p.techs.water_power_pumps], m[Symbol("pump_power_rating"*_n)][t] <= p.s.water_power.max_kw_pump)
		end

		# The electric power input into each pump must be below the pump's electric power rating
		@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], m[Symbol("dvPumpPowerInput"*_n)][t, ts] <= m[Symbol("PumpPowerInputMaximum"*_n)][t, ts])
				
		# Method for linearizing the product of a binary variable and a continuous variable (PumpPowerInputMaximum * binPumpingWaterActive)
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_pumps], m[Symbol("PumpPowerInputMaximum"*_n)][t,ts] <= m[Symbol("binPumpingWaterActive"*_n)][t,ts] * 1000000)
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_pumps], m[Symbol("PumpPowerInputMaximum"*_n)][t,ts] <= m[Symbol("pump_power_rating"*_n)][t])
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_pumps], m[Symbol("PumpPowerInputMaximum"*_n)][t,ts] >= m[Symbol("pump_power_rating"*_n)][t] - (1000000*(1-m[Symbol("binPumpingWaterActive"*_n)][t,ts])))
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_pumps], m[Symbol("PumpPowerInputMaximum"*_n)][t,ts] >= 0)

		if p.s.water_power.computation_type == "average_power_conversion"
			# Conversion between pumped water flow rate and power input into the pump
			@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], 
						m[Symbol("dvPumpedWaterFlow"*_n)][t, ts] == m[Symbol("dvPumpPowerInput"*_n)][t, ts] * p.s.water_power.water_pump_average_cubic_meters_per_second_per_kw )

		else
			throw(@error("A downstream reservoir is only compatible with average_power_conversion at the moment"))
		end
	else	
		@info("Preventing use of the water pump variables because there is no downstream reservoir")
		for t in p.techs.water_power_pumps
			for ts in p.time_steps
				fix(m[Symbol("dvPumpedWaterFlow"*_n)][t, ts], 0.0, force=true)
				fix(m[Symbol("dvPumpPowerInput"*_n)][t, ts], 0.0, force=true)
			end
		end				
	end

	# Create an array of binary variable names for turbine or turbine and pumps
	dvs = []
	if !isempty(p.techs.water_power_pumps)
		dvs = ["binTurbineActive"*_n,"binPumpingWaterActive"*_n]
	else
		dvs = ["binTurbineActive"*_n]
	end

	solvers_incompatible_with_indicator_constraints = ["HiGHS", "Cbc"]

	# Define the minimum operating time (in time steps) for the water_power turbine
	if (p.s.water_power.minimum_operating_time_steps_individual_turbine > 1) || (p.s.water_power.minimum_operating_time_steps_individual_pump > 1)
		@warn "Setting minimum_operating_time_steps_individual_turbine to greater than 1 requires an optimization solver that can handle indicator constraints."
		
		if p.s.settings.solver_name in solvers_incompatible_with_indicator_constraints
			throw(@error("A solver that can handle indicator constraints must be used if minimum_turbine_off_time_steps is set to greater than 1"))
		end

		print("\n Adding minimum operating time constraint \n")
		for dv in dvs
			if dv == "binTurbineActive"*_n
				techs = p.techs.water_power_turbines
				min_operating_timesteps = p.s.water_power.minimum_operating_time_steps_individual_turbine
			elseif dv == "binPumpingWaterActive"*_n
				techs = p.techs.water_power_pumps
				min_operating_timesteps = p.s.water_power.minimum_operating_time_steps_individual_pump 
			else
				throw(@error("Error in applying the local maximum operating time constraint"))
			end
			for t in techs, ts in 1:Int(length(p.time_steps)- min_operating_timesteps - 1 )
				@constraint(m, m[Symbol("indicator_min_operating_time"*_n)][t, ts, dv] =>  { sum(m[Symbol(dv)][t,ts+i] for i in 1:min_operating_timesteps) >= min_operating_timesteps} ) 
				@constraint(m, !m[Symbol("indicator_min_operating_time"*_n)][t, ts, dv] => { m[Symbol(dv)][t,ts+1] - m[Symbol(dv)][t,ts] <= 0  } )
			end
		end
	end
	
	# Define the minimum operating time for the maximum water flow (in time steps) for a water_power turbine
	if p.s.water_power.minimum_operating_time_steps_at_local_maximum_turbine_output > 1
		@warn "Setting minimum_operating_time_steps_at_local_maximum_turbine_output to greater than 1 requires an optimization solver that can handle indicator constraints."
		
		if p.s.settings.solver_name in solvers_incompatible_with_indicator_constraints
			throw(@error("A solver that can handle indicator constraints must be used if minimum_turbine_off_time_steps is set to greater than 1"))
		end

		print("\n Adding a constraint for the minimum operating time at a local maximum water flow \n")
		for dv in dvs
			if dv == "binTurbineActive"*_n
				variable = Symbol("dvWaterOutFlow")
				techs = p.techs.water_power_turbines
			elseif dv == "binPumpingWaterActive"*_n
				variable = Symbol("dvPumpedWaterFlow")
				techs = p.techs.water_power_pumps
			else
				throw(@error("Error in applying the local maximum operating time constraint"))
			end
			for t in techs, ts in (2 + p.s.water_power.minimum_operating_time_steps_at_local_maximum_turbine_output):Int(length(p.time_steps))
				for i in 1:p.s.water_power.minimum_operating_time_steps_at_local_maximum_turbine_output
					@constraint(m, m[Symbol("indicator_turn_down"*_n)][t, ts, dv] => {m[variable][t, ts-i] == m[variable][t,ts-i-1]})
				end
				@constraint(m, !m[Symbol("indicator_turn_down"*_n)][t, ts, dv] => { m[variable][t,ts] >= m[variable][t,ts-1]  })
			end
		end
	end

	if p.s.water_power.minimum_turbine_off_time_steps > 1
		@warn "Setting minimum_turbine_off_time_steps to greater than 1 requires an optimization solver that can handle indicator constraints."
		
		if p.s.settings.solver_name in solvers_incompatible_with_indicator_constraints
			throw(@error("A solver that can handle indicator constraints must be used if minimum_turbine_off_time_steps is set to greater than 1"))
		end
	
		print("\n Adding minimum off duration for the turbines \n")
		for t in p.techs.water_power_turbines, ts in 1:Int(length(p.time_steps)- p.s.water_power.minimum_turbine_off_time_steps - 1 )
			@constraint(m, m[Symbol("indicator_turbine_turn_off"*_n)][t, ts] =>  { sum(m[Symbol("binTurbineActive"*_n)][t,ts+i] for i in 1:p.s.water_power.minimum_turbine_off_time_steps) <= 0 } ) 
			@constraint(m, !m[Symbol("indicator_turbine_turn_off"*_n)][t, ts] => { m[Symbol("binTurbineActive"*_n)][t,ts+1] - m[Symbol("binTurbineActive"*_n)][t,ts] >= 0  } )
		end
	end
	
	# TODO: remove this constraint, which prevents a spike in the spillway use during the first time step
	@constraint(m, [ts in p.time_steps], m[Symbol("dvSpillwayWaterFlow"*_n)][1] == 0)

end

