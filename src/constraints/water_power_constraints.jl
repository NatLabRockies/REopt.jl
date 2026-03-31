# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function add_water_power_constraints(m,p)
	@info "Adding constraints for water_power"
	
	if p.s.water_power.computation_type == "average_power_conversion" # This is a simplified constraint that uses an average conversion for water flow and kW output
		@info "Adding water_power power output constraint using the average power conversion"

		Hydro_techs = p.techs.water_power_turbines
		for t in 1:Int(length(Hydro_techs))
			@constraint(m, [ts in p.time_steps],
					m[:dvRatedProduction][Hydro_techs[t],ts] == m[:dvWaterOutFlow][Hydro_techs[t],ts] * (1/p.s.water_power.average_cubic_meters_per_second_per_kw)* (1- (t/1000))  # convert to kW/time step, for instance: m3/15min  * kwh/m3 * (0.25 hrs/1hr); the "1 - (t/1000)" is for turbine prioritization
						)
		end

	#TODO: add other formuations
	#elseif p.s.water_power.computation_type == "" 
			
	#elseif p.s.water_power.computation_type == ""
		
	else 
		throw(@error("Invalid input for the computation_type field"))
	end

	# Create variable for the upper reservoir capacity
	@variable(m, p.s.upper_reservoir.minimum_capacity_cubic_meters_upper_reservoir <= dvUpperReservoirCapacity <= p.s.upper_reservoir.maximum_capacity_cubic_meters_upper_reservoir)
	
	# The upper reservoir water volume must be between the max and min levels
	@constraint(m, [ts in p.time_steps],
		m[:dvWaterVolume][ts] <= p.s.upper_reservoir.maximum_volume_fraction_upper_reservoir * m[:dvUpperReservoirCapacity]
				)
	@constraint(m, [ts in p.time_steps],
		m[:dvWaterVolume][ts] >= p.s.upper_reservoir.minimum_volume_fraction_upper_reservoir * m[:dvUpperReservoirCapacity] 
				)
	
	# Water flow rate from all turbines combined is above the required minimum water flow
	@constraint(m, [ts in p.time_steps],
		 sum(m[:dvWaterOutFlow][t, ts] for t in p.techs.water_power_turbines) + m[:dvSpillwayWaterFlow][ts] >= p.s.water_power.minimum_water_output_cubic_meter_per_second_total_of_all_turbines   
				)
	
	# Each turbine must meet the minimum water flow requirement of an individual turbine, if it is on
	@constraint(m, [t in p.techs.water_power_turbines, ts in p.time_steps], 
			m[:dvWaterOutFlow][t, ts] >=  m[:binTurbineActive][t,ts]*p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine  
				)
	
	# Upstream Reservoir: The total water volume changes based on the water flow rates
	final_time_step = Int(p.s.settings.time_steps_per_hour * 8760)
	time_steps_without_first_time_step = p.time_steps[2:final_time_step]
		
	@variable(m, dvWaterVolumeChange[ts in time_steps_without_first_time_step] >= -100000 )
	
	@constraint(m, [ts in time_steps_without_first_time_step], 
					m[:dvWaterVolumeChange][ts] == p.s.upper_reservoir.water_inflow_cubic_meter_per_second[ts] - m[:dvSpillwayWaterFlow][ts] - sum(m[:dvWaterOutFlow][t,ts] for t in p.techs.water_power_turbines) + sum(m[:dvPumpedWaterFlow][t,ts] for t in p.techs.water_power_pumps)
				)
	
	@constraint(m, [ts in time_steps_without_first_time_step], 
					m[:dvWaterVolume][ts] == 
					m[:dvWaterVolume][ts-1]  
					+ ((3600/p.s.settings.time_steps_per_hour) * m[:dvWaterVolumeChange][ts])   # The (3600/p.s.settings.time_steps_per_hour) converts from m^3 per second, to m^3 per timestep
				)
	
	@constraint(m, m[:dvWaterVolume][1] == p.s.upper_reservoir.initial_reservoir_volume_fraction_upper_reservoir * m[:dvUpperReservoirCapacity]) 
		
	# Upstream Reservoir: Total water volume must be the same in the beginning and the end
	@constraint(m, m[:dvWaterVolume][1] == m[:dvWaterVolume][maximum(p.time_steps)])
	
	# Define the power rating for each turbine
	@variable(m, turbine_power_rating[t in p.techs.water_power_turbines] >= 0)

	# If the existing power ratings are defined, limit the power rating to the existing kw
	if (p.s.water_power.existing_kw_per_turbine != nothing) && (p.s.water_power.existing_kw_per_turbine != 0)
		@constraint(m, [t in p.techs.water_power_turbines], m[:turbine_power_rating][t] == p.s.water_power.existing_kw_per_turbine)
	else
		@constraint(m, [t in p.techs.water_power_turbines], m[:turbine_power_rating][t] >= p.s.water_power.min_kw_turbine)
		@constraint(m, [t in p.techs.water_power_turbines], m[:turbine_power_rating][t] <= p.s.water_power.max_kw_turbine)
	end
	
	# Define the TurbinePowerGeneration variable
	@variable(m, TurbinePowerGenerationMaximum[t in p.techs.water_power_turbines, ts in p.time_steps] >= 0)

	# Limit power output from the water_power turbines:
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:dvRatedProduction][t,ts] <= m[:TurbinePowerGenerationMaximum][t,ts]) 
	
	# Method for linearizing the product of a binary variable and a continuous variable:
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:TurbinePowerGenerationMaximum][t,ts] <= m[:binTurbineActive][t,ts] * 1000000)
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:TurbinePowerGenerationMaximum][t,ts] <= m[:turbine_power_rating][t])
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:TurbinePowerGenerationMaximum][t,ts] >= m[:turbine_power_rating][t] - (1000000*(1-m[:binTurbineActive][t,ts])))
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:TurbinePowerGenerationMaximum][t,ts] >= 0)

	# Limit the water flow through the spillway, if a value was input
	if !isnothing(p.s.water_power.spillway_maximum_cubic_meter_per_second)
		@constraint(m, [ts in p.time_steps], m[:dvSpillwayWaterFlow][ts] <= p.s.water_power.spillway_maximum_cubic_meter_per_second)
	end 

	# Set the dvSize for the turbines
	@constraint(m, [t in p.techs.water_power_turbines],
		m[:dvSize][t] >= m[:turbine_power_rating][t]
	)

	# Model a downstream reservoir
	if "downstream_reservoir" in p.s.water_storage
		print("\n Adding downstream reservoir variables and constraints")
		
		final_time_step = Int(p.s.settings.time_steps_per_hour * 8760)
		time_steps_without_first_time_step = p.time_steps[2:final_time_step]

		@variable(m, dvDownstreamReservoirNetWaterFlow[ts in time_steps_without_first_time_step] >= -100000 )
		
		@constraint(m, [ts in time_steps_without_first_time_step], 
						m[:dvDownstreamReservoirNetWaterFlow][ts] == m[:dvSpillwayWaterFlow][ts] + sum(m[:dvWaterOutFlow][t,ts] for t in p.techs.water_power_turbines) - sum(m[:dvPumpedWaterFlow][t,ts] for t in p.techs.water_power_pumps) - m[:dvDownstreamReservoirWaterOutflow][ts]
					)
		
		# Downstream Reservoir: The total water volume changes based on the water flow rates
		@constraint(m, [ts in time_steps_without_first_time_step], m[:dvDownstreamReservoirWaterVolume][ts] == m[:dvDownstreamReservoirWaterVolume][ts-1] + ((3600/p.s.settings.time_steps_per_hour)* (m[:dvDownstreamReservoirNetWaterFlow][ts]))
		)
		
		# Downstream Reservoir: Total water volume must be the same in the beginning and the end
		@constraint(m, m[:dvDownstreamReservoirWaterVolume][1] == m[:dvDownstreamReservoirWaterVolume][maximum(p.time_steps)])

		# Create variable for the downstream reservoir capacity
		@variable(m, p.s.downstream_reservoir.minimum_capacity_cubic_meters_downstream_reservoir <= dvDownstreamReservoirCapacity <= p.s.downstream_reservoir.maximum_capacity_cubic_meters_downstream_reservoir)
	
		# Downstream Reservoir: Minimum and maximum water volumes
		@constraint(m, [ts in p.time_steps], m[:dvDownstreamReservoirWaterVolume][ts] >= p.s.downstream_reservoir.minimum_volume_fraction_downstream_reservoir * m[:dvDownstreamReservoirCapacity])
		@constraint(m, [ts in p.time_steps], m[:dvDownstreamReservoirWaterVolume][ts] <= p.s.downstream_reservoir.maximum_volume_fraction_downstream_reservoir * m[:dvDownstreamReservoirCapacity])

		# Downstream Reservoir: define the initial water volume
		@constraint(m, m[:dvDownstreamReservoirWaterVolume][1] == p.s.downstream_reservoir.initial_reservoir_volume_fraction_downstream_reservoir * m[:dvDownstreamReservoirCapacity]) 

		# Downstream Reservoir outflow: minimum and maximum flow rates
		@constraint(m, [ts in p.time_steps], 
						m[:dvDownstreamReservoirWaterOutflow][ts] >= p.s.downstream_reservoir.minimum_outflow_from_downstream_reservoir_cubic_meter_per_second 
			   		)
					
		@constraint(m, [ts in p.time_steps], 
					   m[:dvDownstreamReservoirWaterOutflow][ts] <= p.s.downstream_reservoir.maximum_outflow_from_downstream_reservoir_cubic_meter_per_second
					)
		
		# The pumps cannot act as power generators
		for pump in p.techs.water_power_pumps
			@constraint(m, [ts in p.time_steps], m[:dvRatedProduction][pump,ts] == 0)
		end

		# Ensure that the turbines aren't on when the pumping is happening; binTurbineOrPump is 1 when the turbines are on; binTurbineOrPump is 0 when the pumps are operating
		@constraint(m, [ts in p.time_steps], sum(m[:binTurbineActive][t,ts] for t in p.techs.water_power_turbines) <= p.s.water_power.number_of_turbines * m[:binTurbineOrPump][ts] )
		
		@constraint(m, [ts in p.time_steps], sum(m[:binPumpingWaterActive][t,ts] for t in p.techs.water_power_pumps) <= p.s.water_power.number_of_pumps * (1 - m[:binTurbineOrPump][ts]))
		
		# Each pump must meet the minimum water flow requirement, if it is on
		@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], 
						m[:dvPumpedWaterFlow][t, ts] >= m[:binPumpingWaterActive][t,ts]*p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine
							)
		
		# Define the power rating for each pump
		@variable(m, pump_power_rating[t in p.techs.water_power_pumps] >= 0)
		
		# Set the dvSize for the pumps
		@constraint(m, [t in p.techs.water_power_pumps],
			m[:dvSize][t] == m[:pump_power_rating][t]
		)

		# Pump size constraints
		if p.s.water_power.are_pumps_reversible && ((p.s.water_power.existing_kw_per_pump == nothing) || (p.s.water_power.existing_kw_per_pump != 0))
			@constraint(m, [t in p.techs.water_power_pumps], m[:pump_power_rating][t] == p.s.water_power.pump_kw_to_turbine_kw_ratio_for_reversible_pumps *  m[:turbine_power_rating][t])
		elseif (p.s.water_power.existing_kw_per_pump != nothing) && (p.s.water_power.existing_kw_per_pump != 0)
			@constraint(m, [t in p.techs.water_power_pumps], m[:pump_power_rating][t] == p.s.water_power.existing_kw_per_pump)
		else
			@constraint(m, [t in p.techs.water_power_pumps], m[:pump_power_rating][t] >= p.s.water_power.min_kw_pump)
			@constraint(m, [t in p.techs.water_power_pumps], m[:pump_power_rating][t] <= p.s.water_power.max_kw_pump)
		end

		# Define the PumpPowerInput variable
		@variable(m, PumpPowerInputMaximum[t in p.techs.water_power_pumps, ts in p.time_steps] >= 0)

		# The electric power input into each pump must be below the pump's electric power rating
		@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], m[:dvPumpPowerInput][t, ts] <= m[:PumpPowerInputMaximum][t, ts])
				
		# Method for linearizing the product of a binary variable and a continuous variable (PumpPowerInputMaximum * binPumpingWaterActive)
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_pumps], m[:PumpPowerInputMaximum][t,ts] <= m[:binPumpingWaterActive][t,ts] * 1000000)
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_pumps], m[:PumpPowerInputMaximum][t,ts] <= m[:pump_power_rating][t])
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_pumps], m[:PumpPowerInputMaximum][t,ts] >= m[:pump_power_rating][t] - (1000000*(1-m[:binPumpingWaterActive][t,ts])))
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_pumps], m[:PumpPowerInputMaximum][t,ts] >= 0)

		if p.s.water_power.computation_type == "average_power_conversion"
			# Conversion between pumped water flow rate and power input into the pump
			@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], 
						m[:dvPumpedWaterFlow][t, ts] == m[:dvPumpPowerInput][t, ts] * p.s.water_power.water_pump_average_cubic_meters_per_second_per_kw )

		else
			throw(@error("A downstream reservoir is only compatible with average_power_conversion at the moment"))
		end
	else	
		@info("Preventing use of the water pump variables because there is no downstream reservoir")
		for t in p.techs.water_power_pumps
			for ts in p.time_steps
				fix(m[:dvPumpedWaterFlow][t, ts], 0.0, force=true)
				fix(m[:dvPumpPowerInput][t, ts], 0.0, force=true)
			end
		end				
	end

	# Create an array of binary variable names for turbine or turbine and pumps
	dvs = []
	if !isempty(p.techs.water_power_pumps)
		dvs = ["binTurbineActive","binPumpingWaterActive"]
	else
		dvs = ["binTurbineActive"]
	end

	solvers_incompatible_with_indicator_constraints = ["HiGHS", "Cbc"]

	# Define the minimum operating time (in time steps) for the water_power turbine
	if p.s.water_power.minimum_operating_time_steps_individual_turbine > 1
		@warn "Setting minimum_operating_time_steps_individual_turbine to greater than 1 requires an optimization solver that can handle indicator constraints."
		
		if p.s.settings.solver_name in solvers_incompatible_with_indicator_constraints
			throw(@error("A solver that can handle indicator constraints must be used if minimum_turbine_off_time_steps is set to greater than 1"))
		end

		print("\n Adding minimum operating time constraint \n")
		@variable(m, indicator_min_operating_time[t in p.techs.water_power, ts in p.time_steps, dv in dvs], Bin)
		for dv in dvs
			if dv == "binTurbineActive"
				techs = p.techs.water_power_turbines
				min_operating_timesteps = p.s.water_power.minimum_operating_time_steps_individual_turbine
			elseif dv == "binPumpingWaterActive"
				techs = p.techs.water_power_pumps
				min_operating_timesteps = 1 # TODO: update this to be an input into the model
			else
				throw(@error("Error in applying the local maximum operating time constraint"))
			end
			for t in techs, ts in 1:Int(length(p.time_steps)- min_operating_timesteps - 1 )
				@constraint(m, m[:indicator_min_operating_time][t, ts, dv] =>  { sum(m[Symbol(dv)][t,ts+i] for i in 1:p.s.water_power.minimum_operating_time_steps_individual_turbine) >= p.s.water_power.minimum_operating_time_steps_individual_turbine} ) 
				@constraint(m, !m[:indicator_min_operating_time][t, ts, dv] => { m[Symbol(dv)][t,ts+1] - m[Symbol(dv)][t,ts] <= 0  } )
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
		@variable(m, indicator_turn_down[t in p.techs.water_power_turbines, ts in p.time_steps, dv in dvs], Bin)	
		for dv in dvs
			if dv == "binTurbineActive"
				variable = Symbol("dvWaterOutFlow")
				techs = p.techs.water_power_turbines
			elseif dv == "binPumpingWaterActive"
				variable = Symbol("dvPumpedWaterFlow")
				techs = p.techs.water_power_pumps
			else
				throw(@error("Error in applying the local maximum operating time constraint"))
			end
			for t in techs, ts in (2 + p.s.water_power.minimum_operating_time_steps_at_local_maximum_turbine_output):Int(length(p.time_steps))
				for i in 1:p.s.water_power.minimum_operating_time_steps_at_local_maximum_turbine_output
					@constraint(m, m[:indicator_turn_down][t, ts, dv] => {m[variable][t, ts-i] == m[variable][t,ts-i-1]})
				end
				@constraint(m, !m[:indicator_turn_down][t, ts, dv] => { m[variable][t,ts] >= m[variable][t,ts-1]  })
			end
		end
	end

	if p.s.water_power.minimum_turbine_off_time_steps > 1
		@warn "Setting minimum_turbine_off_time_steps to greater than 1 requires an optimization solver that can handle indicator constraints."
		
		if p.s.settings.solver_name in solvers_incompatible_with_indicator_constraints
			throw(@error("A solver that can handle indicator constraints must be used if minimum_turbine_off_time_steps is set to greater than 1"))
		end
	
		print("\n Adding minimum off duration for the turbines \n")
		@variable(m, indicator_turbine_turn_off[t in p.techs.water_power_turbines, ts in p.time_steps], Bin)
		for t in p.techs.water_power_turbines, ts in 1:Int(length(p.time_steps)- p.s.water_power.minimum_turbine_off_time_steps - 1 )
			@constraint(m, m[:indicator_turbine_turn_off][t, ts] =>  { sum(m[:binTurbineActive][t,ts+i] for i in 1:p.s.water_power.minimum_turbine_off_time_steps) <= 0 } ) 
			@constraint(m, !m[:indicator_turbine_turn_off][t, ts] => { m[:binTurbineActive][t,ts+1] - m[:binTurbineActive][t,ts] >= 0  } )
		end
	end
	
	# TODO: remove this constraint, which prevents a spike in the spillway use during the first time step
	@constraint(m, [ts in p.time_steps], m[:dvSpillwayWaterFlow][1] == 0)

end

