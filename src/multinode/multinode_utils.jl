# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.


function run_PowerModelsDistribution_using_just_dss_file(dss_file_path::String, PMD_model_subtype::String, optimizer; options=[])
	#=
	Information about this function
	The PMD_model_subtype defines which model to run
		"NFAUPowerModel_pf" will run the simplest type of model that looks only at feasibility of real power balance: run this model first when checking the model
		"NFAUPowerModel_opf" 

	The "options" input can be used to activate various debugging treatments
		Adding "set_all_transformers_to_infinite_kVA" into the inputs vector sets all of the transformers to be able to handle infinite power

	=#

	eng_model = PowerModelsDistribution.parse_file(dss_file_path)
	
	# start of a section of code that was developed using assistance from AI
	# Ensure that the slack bus can provide infinite power if the power maximum and minimum is not already defined

	for (k, v) in eng_model["voltage_source"]
		n = length(v["connections"])
		if !haskey(v, "pg_lb") v["pg_lb"] = fill(-Inf, n) end
		if !haskey(v, "pg_ub") v["pg_ub"] = fill( Inf, n) end
		if !haskey(v, "qg_lb") v["qg_lb"] = fill(-Inf, n) end
		if !haskey(v, "qg_ub") v["qg_ub"] = fill( Inf, n) end
	end

	eng_model["settings"]["sbase_default"] = 0.001  # set sbase to 1 kVA

	if "set_all_transformers_to_infinite_kVA_and_detect_if_any_transformers_exceed_the_original_power_limit" in options
		# save the original

		original_sm_ub = Dict(k => xfmr["sm_ub"] for (k, xfmr) in eng_model["transformer"]  if haskey(xfmr, "sm_ub"))

		for (k, xfmr) in eng_model["transformer"]
			xfmr["sm_ub"] = Inf
		end
	end

	# end of section that was developed using AI

	if PMD_model_subtype == "LPUBFDiagPowerModel"
        #pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.LPUBFDiagPowerModel, PowerModelsDistribution.build_mn_mc_opf) # Note: instantiate_mc_model automatically converts the "engineering" model into a "mathematical" model
    elseif PMD_model_subtype == "NFAUPowerModel_pf"
        #pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.NFAUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
		results = PowerModelsDistribution.solve_mc_pf(eng_model, PowerModelsDistribution.NFAUPowerModel, optimizer)
    elseif PMD_model_subtype == "NFAUPowerModel_opf"
        #pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.NFAUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
		results = PowerModelsDistribution.solve_mc_opf(eng_model, PowerModelsDistribution.NFAUPowerModel, optimizer)

	elseif PMD_model_subtype == "ACPUPowerModel"
        #pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.ACPUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif PMD_model_subtype == "ACRUPowerModel"
        #pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.ACRUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif PMD_model_subtype == "IVRUPowerModel"
        #pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.IVRUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif PMD_model_subtype == "SOCNLPUBFPowerModel"                                      
        #pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.SOCNLPUBFPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif PMD_model_subtype == "SOCConicUBFPowerModel"
        #pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.SOCConicUBFPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    else
        throw(@error("The PMD subtype is not valid"))
    end


	# start of a section of code that was developed using assistance from AI
	if "set_all_transformers_to_infinite_kVA_and_detect_if_any_transformers_exceed_the_original_power_limit" in options
		println("Overloaded transformers (flow > original kVA rating):")
		found_any = false
		sol_xfmrs = get(results["solution"], "transformer", Dict())
		for (k, rating) in original_sm_ub
			sol_key = lowercase(k)  # solution keys are lowercase
			if haskey(sol_xfmrs, sol_key)
				p = get(sol_xfmrs[sol_key], "p", nothing)
				if p !== nothing
					# p is [[winding1_phase_powers...], [winding2_phase_powers...]]
					# Use winding 1 (primary) active power across all phases
					flow_kw = maximum(abs.(p[1]))
					if flow_kw > rating
						pct = round(100 * flow_kw / rating, digits=1)
						println("  Transformer $k: rating = $(round(rating, digits=1)) kVA, " *
								"flow = $(round(flow_kw, digits=1)) kW ($pct% of rating)")
						found_any = true
					end
				end
			end
		end
		found_any || println("  None — all transformers within rating.")
		# end of section that was developed using AI
	end

	return results
end


function combine_dss_files_into_aggregated_dss_file(folder, new_file_name, existing_dss_files_list)
	# This function takes multiple separate dss files and combines them into one dss file
	# note: this function was created with the assistance of ChatGPT

	# The order of the files in the existing_dss_files_list matters
	
	aggregated_file_path = folder * "/" * new_file_name # note: the new_file_name should have .dss appended to the end of the string

	open(aggregated_file_path, "w") do x
		for file in existing_dss_files_list
			filepath = folder*"/"* file
			println(x) # this creates a new line
			println(x, "! Data from filename: ", file)
			println(x)

			for line in eachline(filepath)
				println(x, line)
			end
		end
	end

	return aggregated_file_path

end


function prepare_dss_file_for_multinode(Multinode_Inputs_struct, folder, input_dss_filepath) 

	# Convert the syntax "new object=" into simpler syntax
	output_dss_filepath_object_syntax_processed = modify_object_syntax(input_dss_filepath, folder*"/"*"temp_object_syntax_modified.dss")

	# Process the reactors
	output_dss_filepath_reactors_processed = process_reactors(output_dss_filepath_object_syntax_processed, folder*"/"*"temp_reactors_processed.dss")

	output_dss_filepath_redirects_removed = remove_redirect_lines(output_dss_filepath_reactors_processed, folder*"/"*"temp_redirects_removed.dss")

	output_dss_filepath_multiphase_split_into_multiple_lines = split_multiphase_loads_into_separate_lines(output_dss_filepath_redirects_removed, folder*"/"*"temp_multiphase_split_into_multiple_lines.dss")  

	output_dss_filepath_loads_renamed_to_names_of_busses, load_map = rename_load_names_to_names_of_busses_with_phase_label(output_dss_filepath_multiphase_split_into_multiple_lines, folder*"/"*"temp_loads_renamed_to_busses_with_phase_label.dss")

	output_dss_filepath_kw_kvar_modified = set_kw_and_kvar_loads_to_1_if_there_is_an_associated_REopt_node(Multinode_Inputs_struct, output_dss_filepath_loads_renamed_to_names_of_busses, folder*"/"*"temp_kw_and_kvar_loads_with_value_of_1.dss")

	dss_file_export = output_dss_filepath_kw_kvar_modified

	return dss_file_export, load_map
end


function modify_object_syntax(input_filepath::String, output_filepath::String)
	# This function was generated with the assistance of ChatGPT

	open(output_filepath, "w") do output
		for line in eachline(input_filepath)
			println(output, change_object_syntax(line))
		end
	end
	
	return output_filepath
end


function change_object_syntax(line)
	# This funcition was generated with the assistance of ChatGPT

	new_object_syntax_pattern = r"(?i)^\s*new\s+object\s*=\s*(\S+)"

	m = match(new_object_syntax_pattern, line)
	if m !== nothing
		object_name = lowercase(m.captures[1])
		return replace(line, new_object_syntax_pattern => "new $object_name"; count=1)
	else
		return line
	end

	return 
end


function set_kw_and_kvar_loads_to_1_if_there_is_an_associated_REopt_node(Multinode_Inputs, input_dss_file, output_dss_file)
	# This funcition was generated with the assistance of ChatGPT
	
	REopt_nodes = lowercase.(REopt.GenerateREoptNodesList(Multinode_Inputs))

	REopt_nodes = []
	REopt_phases = Dict()
    for i in Multinode_Inputs.REopt_inputs_list
        if string(i["Site"]["node"]) != Multinode_Inputs.facilitymeter_node
            push!(REopt_nodes, i["Site"]["node"])
			REopt_phases[lowercase(i["Site"]["node"])] = i["Settings"]["phase_numbers"]
        end
    end

	# If the node is part of the REopt nodes, then set the kW and the kVAR to 1
	# If the node is not part of the REopt nodes list, then set the kW and kVAR to 0

	open(output_dss_file, "w") do output
		for line in eachline(input_dss_file)
			if occursin(r"(?i)new\s+load\.", line) && occursin(r"(?i)bus1=",line)
				bus, phases = get_bus_and_phases(line)
								
				phase = phases[1] # There will only be one phase listed in each row due to the function split_multiphase_loads_into_separate_lines

				if (bus !== nothing) && (lowercase(bus) in REopt_nodes) 
					if phase in REopt_phases[lowercase(bus)]
						line = replace_kw_and_kvar(line, 1.0, 1.0)
					else
						line = replace_kw_and_kvar(line, 0.0, 0.0)
					end
				else
					line = replace_kw_and_kvar(line, 0.0, 0.0)
				end
			end
			write(output, line*"\n")
		end
	end
	
	return output_dss_file
end


function get_bus_and_phases(line::String)
	# This funcition was generated with the assistance of ChatGPT
	m = match(r"(?i)Bus1=([^\s\.]+)((?:\.\d+)*)",line)
	if m === nothing 
		return  nothing, Int[]
	end
	bus = m.captures[1]

	# Extract all digits after dots
	phase_str = m.captures[2]
	phases = isempty(phase_str) ? Int[] : parse.(Int,split(phase_str[2:end], "."))

	return bus, phases
end


function replace_kw_and_kvar(line::String, kw::Float64, kvar::Float64)
	# This funcition was generated with the assistance of ChatGPT
	line = replace(line, r"(?i)kW=[^\s]+" => "kW=$(kw)")
	line = replace(line, r"(?i)kvar=[^\s]+" => "kvar=$(kvar)")
	return line
end


function process_reactors(input_dss_filepath, output_dss_filepath)
	# This function removes features that REopt multinode does not model
	# This funcition was generated with the assistance of ChatGPT

	# Convert the series reactors to lines (series reactors are show as reactor types with two busses listed in the .dss file)
		# add code to remove shunt reactors (reactor types that only have one bus listed)
	new_line_prefix = "RXLine_" # label the lines with RXLine_ after they are converted from reactors
	
	open(output_dss_filepath, "w") do output
		open(input_dss_filepath, "r") do input

			block = String[]

			function flush_block()
				isempty(block) && return

				if isempty(block)
					return
				end

				first_line = block[1]

				stripped_line = strip(first_line) # isa String ? first_line : ""

				if startswith(lowercase(stripped_line), "new reactor.")
					handle_reactor_block(block, output, new_line_prefix)
				else
					# write non-reactor block verbatim
					for y in block
						println(output, y)
					end
				end

				empty!(block)
			end

			for line in eachline(input)
				stripped = line # strip(line) # isa String ? strip(line) : ""
				if startswith(lowercase(stripped), "new")
					# Start a new block
					flush_block()
					push!(block, line)
				elseif startswith(stripped, "~")
					# Continuation line
					push!(block, line)
				else
					flush_block()
					println(output, line)
				end
			end

			flush_block() # final block
		end
	end

	return output_dss_filepath
end


function handle_reactor_block(block, x, prefix)
	# This funcition was generated with the assistance of ChatGPT
	full = join(block, " ")
	has_bus2 = occursin(r"(?i)bus2\s*=", full) # This detects if it is a series reactor (and not a shunt reactor, because shunt reactors won't have a bus 2)
	if has_bus2
		line_def = reactor_block_to_line(full, prefix)
		println(x, line_def)
	else
		println(x, "! Shunt reactor removed:")
		for y in block
			println(x, "! ", y)
		end
	end
end


function reactor_block_to_line(full::String, prefix::String)
	# This function was generated with the assistance of ChatGPT
	
	name = extract_reactor_name(full)
	bus1 = extract_prop(full, "bus1", "UNKNOWN")
	bus2 = extract_prop(full, "bus2", "UNKNOWN")
	phases = extract_prop(full, "phases", "3") 
	r = extract_prop(full, "r", "0.0")
	x = extract_prop(full, "x", "0.0")

	line_name = prefix*name

	lines = ["New Line.$line_name Bus1=$bus1 Bus2=$bus2 Phases=$phases",
			 "~ R1=$r X1=$x Length=1 Units=Ft"]  # line objects in OpenDSS take the resistance and reactance as R1 and X1 variables, respectively. Resistance and reactance can also be entered using other variables in the OpenDSS format.
	return join(lines, "\n")
end


function extract_prop(text::String, key::String, default::String)
	# This function was generated with the assistance of ChatGPT
	m = match(Regex("(?i)$key\\s*=\\s*([^\\s]+)"), text)
	return m == nothing ? default : m.captures[1]
end

function extract_reactor_name(full::String)
	# This function was generated with the assistance of ChatGPT
	m = match(r"(?i)new\s+reactor\.([^\s]+)",full)
	return m == nothing ? "UNKNOWN" : m.captures[1]
end


function remove_redirect_lines(input_filepath::String, output_filepath::String)
	# This function was generated with the assistance of ChatGPT
	open(output_filepath, "w") do output
		open(input_filepath, "r") do input
			for line in eachline(input)
				stripped = strip(line)
				# Skip lines starting with "redirect" (case-insensitive)
				if startswith(lowercase(stripped), "redirect")
					continue
				else
					println(output, line)
				end
			end
		end
	end

	return output_filepath
end


function split_multiphase_loads_into_separate_lines(input_filepath::String, output_filepath::String)
	# This function was generated with assistance from ChatGPT

	# This function handles how voltages will need to be adjusted, depending on if they are delta or wye connected
	
	sqrt3 = sqrt(3.0)

	open(output_filepath, "w") do output
		open(input_filepath, "r") do input
			for line in eachline(input)
				stripped = strip(line)
				
				# Only process New Load lines
				if startswith(lowercase(stripped), "new load.")
					m_name = match(r"(?i)new\s+load\.([^\s]+)",line)
					m_bus = match(r"(?i)bus1\s*=\s*([^\s]+)", line)
					m_phases = match(r"(?i)phases\s*=\s*(\d+)",line)
					m_conn = match(r"(?i)conn\s*=\s*(\w+)",line)
					m_kv = match(r"(?i)kv\s*=\s*([\d\.]+)",line)
					m_kw = match(r"(?i)kw\s*=\s*([\d\.]+)",line)
					m_kvar = match(r"(?i)kvar\s*=\s*([\d\.]+)",line)

					if m_name !== nothing &&
						m_bus !== nothing &&
						m_phases !== nothing &&
						parse(Int,m_phases.captures[1]) > 1 &&
						m_conn !== nothing &&
						m_kv !== nothing &&
						m_kw !== nothing

						orig_name = m_name.captures[1]
						bus_full = m_bus.captures[1]
						nph = parse(Int, m_phases.captures[1])
						conn = lowercase(m_conn.captures[1])
						kv_orig = parse(Float64, m_kv.captures[1])
						kw_orig = parse(Float64, m_kw.captures[1])

						parts = split(bus_full, ".")
						bus_id = parts[1]
						phases = parts[2:end]

						# Voltage scaling
						kv_new = conn == "delta" ? kv_orig / sqrt3 : kv_orig

						# Power scaling
						kw_new = kw_orig / nph

						for ph in phases
							new_name = "$(orig_name)_phase$(ph)"
							newline = line
							#newline = replace(newline, r"(?i)(new\s+load\.)[^\s]+" => "\\1$new_name")
							
							newline = replace_dss_load_name(newline, new_name)

							newline = replace(newline, r"(?i)phases\s*=\s*\d+" => "phases=1")
							newline = replace(newline, r"(?i)bus1\s*=\s*[^\s]+" => "Bus1=$(bus_id).$(ph)")
							newline = replace(newline, r"(?i)kv\s*=\s*[\d\.]+" => "kV=$(round(kv_new, digits=6))")
							newline = replace(newline, r"(?i)kw\s*=\s*[\d\.]+" => "kW=$(round(kw_new, digits=6))")

							println(output, newline)
						end

						continue # used to skip the original multiphase line
					end
				end

				# By default, re-write the unchanged line
				println(output, line)
			end
		end
	end

	return output_filepath
end


function rename_load_names_to_names_of_busses_with_phase_label(input_filepath::String, output_filepath::String)
	# This function was generated with assistance from ChatGPT

	# NOTE: this function will not handle multiphase busses (e.g. Bus1=9.1.2.3). This assumes that all loads have been assigned to a single phase bus (which is what currently is required for multinode)

	load_to_bus_mapping = Dict{String, Tuple{String,String}}()

	open(output_filepath, "w") do output
		open(input_filepath, "r") do input
			for line in eachline(input)
				stripped = strip(line)

				if startswith(lowercase(stripped), "new load.")
					#Extract the original load name
					m_name = match(r"(?i)new\s+load\.([^\s]+)", line)

					# Extract Bus1 information
					m_bus = match(r"(?i)bus1\s*=\s*([^\s]+)",line)

					if (m_name !== nothing) && (m_bus !== nothing)
						orig_name = m_name.captures[1]
						bus_full = m_bus.captures[1]

						parts = split(bus_full,".")
						bus_id = parts[1]
						phase_id = length(parts) > 1 ? parts[2] : "1"  # assume the phase ID is 1 by default

						new_name = "Load$(bus_id)_phase$(phase_id)"

						# Store the mapping
						load_to_bus_mapping[orig_name] = (new_name, bus_full)

						# Replace the load name in the dss file line
						#line = replace(line, r"(?i)(new\s+load\.)[^\s]+"=>"\\1$new_name")
						line = replace_dss_load_name(line, new_name)
					end
				end

				println(output, line)
			end
		end
	end

	return output_filepath, load_to_bus_mapping
end


function replace_dss_load_name(line::String, new_name::String)
	# This function was generated with the assistance of ChatGPT

	m = match(r"(?i)^(new\s+load\.)[^\s]+(.*)$", line)
	if m == nothing
		return line
	end
	prefix = m.captures[1] # This is for "New Load."
	rest = m.captures[2] # everything after the name

	return prefix*new_name*rest

end


"""
Note: this function was generated using AI

    detect_network_loops(data_eng; kwargs...) -> (has_loops::Bool, loop_edges::Vector)

Detects loops (cycles) in a PowerModelsDistribution engineering-model network
using Union-Find (disjoint set union). Compatible with single-phase and
multi-phase radial or meshed distribution systems.

A "loop" is any edge whose two endpoint buses are already connected by another
path — i.e. removing it would not disconnect the graph.  In a purely radial
feeder no loops will be found.

# Keyword arguments
- `include_switches` (default `true`): include switch elements (both dedicated
  `"switch"` entries and lines whose name starts with `"sw_"`).
- `include_transformers` (default `true`): include transformers as edges
  between their winding buses.
- `only_enabled` (default `true`): skip any component whose `"status"` field
  is `PowerModelsDistribution.DISABLED`.
- `verbose` (default `true`): print a summary table to stdout.
- `phase_filter` (default `nothing`): if set to an integer (1=A, 2=B, 3=C), only edges
  that carry that phase are included. Edges with no phase information are always included.
  Use this to check loop connectivity on a single phase.

# Returns
- `has_loops::Bool` – `true` if at least one loop was found.
- `loop_edges::Vector{NamedTuple}` – one entry per loop-closing edge, each
  with fields `(type, name, f_bus, t_bus)`.
"""
function detect_network_loops(
    data_eng::Dict;
    include_switches::Bool            = true,
    include_transformers::Bool        = true,
    only_enabled::Bool                = true,
    verbose::Bool                     = true,
    phase_filter::Union{Nothing, Int} = nothing,
)
    # ------------------------------------------------------------------ #
    # 1.  Build edge list                                                  #
    # ------------------------------------------------------------------ #
    # Each entry: NamedTuple (type, name, f_bus, t_bus, phases)
    # phases is a Vector{Int} using PMD convention: 1=A, 2=B, 3=C, 0=neutral
    Edge = NamedTuple{(:type, :name, :f_bus, :t_bus, :phases),
                      Tuple{String,String,String,String,Vector{Int}}}
    edges = Edge[]

    # Helper: is a component disabled?
    function is_disabled(comp::Dict)
        only_enabled || return false
        status = get(comp, "status", nothing)
        status === nothing && return false
        return string(status) == "DISABLED"
    end

    # Helper: convert integer phase list to a readable string ("A", "AB", "ABC", etc.)
    _phase_label = Dict(1 => "A", 2 => "B", 3 => "C", 0 => "N")
    function phases_str(phases::Vector{Int})
        isempty(phases) && return "?"
        return join([get(_phase_label, p, string(p)) for p in sort(phases)])
    end

    # --- Lines (includes overhead lines, underground cables, and any        ---
    #     stub lines created by the REopt DSS pre-processor)                  #
    for (name, line) in get(data_eng, "line", Dict())
        is_disabled(line) && continue
        startswith(name, "loadconn_") && continue
        !include_switches && startswith(name, "sw_") && continue

        f_bus = get(line, "f_bus", nothing)
        t_bus = get(line, "t_bus", nothing)
        (f_bus === nothing || t_bus === nothing) && continue

        phases = Vector{Int}(get(line, "f_connections", Int[]))
        phase_filter !== nothing && !isempty(phases) && !(phase_filter in phases) && continue
        push!(edges, (type="line", name=name, f_bus=string(f_bus), t_bus=string(t_bus), phases=phases))
    end

    # --- Dedicated switch entries (PMD stores some switches separately)  ---
    if include_switches
        for (name, sw) in get(data_eng, "switch", Dict())
            is_disabled(sw) && continue
            f_bus = get(sw, "f_bus", nothing)
            t_bus = get(sw, "t_bus", nothing)
            (f_bus === nothing || t_bus === nothing) && continue
            phases = Vector{Int}(get(sw, "f_connections", Int[]))
            phase_filter !== nothing && !isempty(phases) && !(phase_filter in phases) && continue
            push!(edges, (type="switch", name=name, f_bus=string(f_bus), t_bus=string(t_bus), phases=phases))
        end
    end

    # --- Transformers (multi-winding: connect each adjacent pair of buses) ---
    if include_transformers
        for (name, xfmr) in get(data_eng, "transformer", Dict())
            is_disabled(xfmr) && continue
            buses = get(xfmr, "bus", String[])
            # connections is a vector of per-winding connection arrays
            conns = get(xfmr, "connections", Vector{Vector{Int}}())
            for i in 1:(length(buses) - 1)
                phases = !isempty(conns) && i <= length(conns) ? Vector{Int}(conns[i]) : Int[]
                phase_filter !== nothing && !isempty(phases) && !(phase_filter in phases) && continue
                push!(edges, (type="transformer", name=name,
                              f_bus=string(buses[i]), t_bus=string(buses[i+1]), phases=phases))
            end
        end
    end

    # ------------------------------------------------------------------ #
    # 2.  Union-Find with path compression and union-by-rank               #
    # ------------------------------------------------------------------ #
    all_buses = unique(vcat(
        [e.f_bus for e in edges],
        [e.t_bus for e in edges],
    ))

    parent = Dict{String,String}(b => b for b in all_buses)
    rnk    = Dict{String,Int}(b => 0    for b in all_buses)

    function find!(x::String)
        while parent[x] != x
            parent[x] = parent[parent[x]]   # path-halving compression
            x = parent[x]
        end
        return x
    end

    function union!(x::String, y::String)::Bool
        rx, ry = find!(x), find!(y)
        rx == ry && return false             # already connected → cycle
        if rnk[rx] < rnk[ry]
            rx, ry = ry, rx
        end
        parent[ry] = rx
        rnk[rx] == rnk[ry] && (rnk[rx] += 1)
        return true
    end

    # ------------------------------------------------------------------ #
    # 3.  Detect loop-closing edges                                         #
    # ------------------------------------------------------------------ #
    loop_edges = Edge[]
    for e in edges
        if !union!(e.f_bus, e.t_bus)
            push!(loop_edges, e)
        end
    end

    # ------------------------------------------------------------------ #
    # Helper (defined here so it is available for the report below)        #
    # ------------------------------------------------------------------ #
    _phase_label_report = Dict(1 => "A", 2 => "B", 3 => "C", 0 => "N")
    phases_str_report(phases::Vector{Int}) =
        isempty(phases) ? "?" : join([get(_phase_label_report, p, string(p)) for p in sort(phases)])

    has_loops = !isempty(loop_edges)

    # ------------------------------------------------------------------ #
    # 4.  Report                                                            #
    # ------------------------------------------------------------------ #
    if verbose
        println("\n" * "=" ^ 70)
        println("Network Loop Detection")
        phase_filter === nothing || println("  Phase filter: $(phase_filter) ($(get(Dict(1=>"A",2=>"B",3=>"C",0=>"N"), phase_filter, string(phase_filter))))")
        println("  Buses      : $(length(all_buses))")
        println("  Edges used : $(length(edges))  ",
                "(switches=$(include_switches), ",
                "transformers=$(include_transformers))")
        println("=" ^ 70)
        if has_loops
            println("LOOPS DETECTED — $(length(loop_edges)) loop-closing edge(s):")
            for e in loop_edges
                ph = phases_str_report(e.phases)
                println("  [$(e.type)]  \"$(e.name)\"   $(e.f_bus)  <-->  $(e.t_bus)   phases: $ph")
            end
        else
            println("No loops detected — network appears to be radial.")
        end
        println("=" ^ 70)
    end

    return has_loops, loop_edges
end


"""
Note: this function was generated using AI

    detect_islanded_buses(data_eng, source_bus; kwargs...) -> (has_islands::Bool, islanded_buses::Vector{String}, island_groups::Vector{Vector{String}})

Detects buses that are not electrically connected to `source_bus` (the
substation / voltage-source bus) in a PowerModelsDistribution engineering model.

Each disconnected group is reported separately so you can see which buses are
isolated together versus individually.

# Arguments
- `data_eng`   : parsed PMD engineering model (`data_eng = PowerModelsDistribution.parse_file(...)`)
- `source_bus` : name of the reference bus (e.g. `Multinode_Inputs.substation_node`)

# Keyword arguments
- `include_switches`    (default `true`): treat switch elements as edges.
- `include_transformers`(default `true`): treat transformer winding connections as edges.
- `only_enabled`        (default `true`): ignore components whose `"status"` field is DISABLED.
- `verbose`             (default `true`): print a summary to stdout.
- `phase_filter`        (default `nothing`): if set to an integer (1=A, 2=B, 3=C), only edges
  that carry that phase are used to build the connectivity graph. Edges with no phase
  information are always included. Use this to detect per-phase islands in systems where
  some buses are connected on one phase but not another.

# Returns
- `has_islands::Bool`                    – `true` if any islanded bus was found.
- `islanded_buses::Vector{String}`       – flat list of all buses not reachable from `source_bus`.
- `island_groups::Vector{Vector{String}}`– buses grouped by their connected component.
"""
function detect_islanded_buses(
    data_eng::Dict,
    source_bus::String;
    include_switches::Bool            = true,
    include_transformers::Bool        = true,
    only_enabled::Bool                = true,
    verbose::Bool                     = true,
    phase_filter::Union{Nothing, Int} = nothing,
)
    # ------------------------------------------------------------------ #
    # 1.  Collect all buses present in the model                           #
    # ------------------------------------------------------------------ #
    # When phase_filter is set, only include buses whose `terminals` field
    # contains the filtered phase. Otherwise buses that physically exist on
    # other phases only (e.g. a phase-2 battery) would appear as singleton
    # islands on the phase-1 graph.
    all_buses = String[]
    for (bname, bdata) in get(data_eng, "bus", Dict())
        if phase_filter !== nothing
            terms = Vector{Int}(get(bdata, "terminals", Int[]))
            !isempty(terms) && !(phase_filter in terms) && continue
        end
        push!(all_buses, string(bname))
    end

    # ------------------------------------------------------------------ #
    # 2.  Build edge list (same logic as detect_network_loops)             #
    # ------------------------------------------------------------------ #
    function is_disabled(comp::Dict)
        only_enabled || return false
        status = get(comp, "status", nothing)
        status === nothing && return false
        return string(status) == "DISABLED"
    end

    edges = Tuple{String,String}[]   # (f_bus, t_bus)

    for (name, line) in get(data_eng, "line", Dict())
        is_disabled(line) && continue
        !include_switches && startswith(name, "sw_") && continue
        f = get(line, "f_bus", nothing)
        t = get(line, "t_bus", nothing)
        (f === nothing || t === nothing) && continue
        phases = Vector{Int}(get(line, "f_connections", Int[]))
        phase_filter !== nothing && !isempty(phases) && !(phase_filter in phases) && continue
        push!(edges, (string(f), string(t)))
    end

    if include_switches
        for (_, sw) in get(data_eng, "switch", Dict())
            is_disabled(sw) && continue
            f = get(sw, "f_bus", nothing)
            t = get(sw, "t_bus", nothing)
            (f === nothing || t === nothing) && continue
            phases = Vector{Int}(get(sw, "f_connections", Int[]))
            phase_filter !== nothing && !isempty(phases) && !(phase_filter in phases) && continue
            push!(edges, (string(f), string(t)))
        end
    end

    if include_transformers
        for (_, xfmr) in get(data_eng, "transformer", Dict())
            is_disabled(xfmr) && continue
            buses = get(xfmr, "bus", String[])
            conns = get(xfmr, "connections", Vector{Vector{Int}}())
            for i in 1:(length(buses) - 1)
                phases = !isempty(conns) && i <= length(conns) ? Vector{Int}(conns[i]) : Int[]
                phase_filter !== nothing && !isempty(phases) && !(phase_filter in phases) && continue
                push!(edges, (string(buses[i]), string(buses[i+1])))
            end
        end
    end

    # ------------------------------------------------------------------ #
    # 3.  Union-Find over ALL buses (not just those touched by edges)      #
    # ------------------------------------------------------------------ #
    parent = Dict{String,String}(b => b for b in all_buses)
    rnk    = Dict{String,Int}(b => 0    for b in all_buses)

    # Also register any edge-endpoint buses not already in data_eng["bus"]
    for (f, t) in edges
        get!(parent, f, f); get!(rnk, f, 0)
        get!(parent, t, t); get!(rnk, t, 0)
    end

    function find!(x::String)
        while parent[x] != x
            parent[x] = parent[parent[x]]
            x = parent[x]
        end
        return x
    end

    function union!(x::String, y::String)
        rx, ry = find!(x), find!(y)
        rx == ry && return
        if rnk[rx] < rnk[ry]; rx, ry = ry, rx; end
        parent[ry] = rx
        rnk[rx] == rnk[ry] && (rnk[rx] += 1)
    end

    for (f, t) in edges
        union!(f, t)
    end

    # ------------------------------------------------------------------ #
    # 4.  Identify connected components                                     #
    # ------------------------------------------------------------------ #
    if !haskey(parent, source_bus)
        error("detect_islanded_buses: source_bus \"$source_bus\" not found in the model.")
    end

    source_root = find!(source_bus)

    # Group all buses by their root
    components = Dict{String, Vector{String}}()
    for b in keys(parent)
        root = find!(b)
        push!(get!(components, root, String[]), b)
    end

    islanded_buses  = String[]
    island_groups   = Vector{String}[]

    for (root, group) in components
        root == source_root && continue   # this is the main connected network
        sort!(group)
        append!(islanded_buses, group)
        push!(island_groups, group)
    end
    sort!(islanded_buses)
    sort!(island_groups, by = g -> g[1])

    has_islands = !isempty(islanded_buses)

    # ------------------------------------------------------------------ #
    # 5.  Report                                                            #
    # ------------------------------------------------------------------ #
    if verbose
        println("\n" * "=" ^ 70)
        println("Islanded Bus Detection")
        phase_filter === nothing || println("  Phase filter: $(phase_filter) ($(get(Dict(1=>"A",2=>"B",3=>"C",0=>"N"), phase_filter, string(phase_filter))))")
        println("  Source bus : \"$source_bus\"")
        println("  Total buses: $(length(keys(parent)))")
        main_group_size = haskey(components, source_root) ? length(components[source_root]) : 0
        println("  Connected buses (reachable from source): $(main_group_size)")
        println("  Island groups (excluding the group connected to the sourebus): $(length(island_groups))")
        println("=" ^ 70)
        if has_islands
            println("ISLANDED BUSES DETECTED — $(length(islanded_buses)) bus(es) in $(length(island_groups)) group(s):")
            for (i, group) in enumerate(island_groups)
                println("  Island $i ($(length(group)) bus(es)): ", join(group, ", "))
            end
        else
            println("No islanded buses — all buses are reachable from \"$source_bus\".")
        end
        println("=" ^ 70)
    end

    return has_islands, islanded_buses, island_groups
end
