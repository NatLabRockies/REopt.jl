# DC-Coupled PV and Battery: Modeling Approach and Review Questions

## Summary of approach

- intended approach, mostly but not 100% complete
- extend REopt optimization to represent DC coupled PV and battery with shared inverter
- both AC and DC coupled PV and other AC coupled DERs can be modeled at the same time so they can be traded off (use DC and AC coupled technology sets to align with existing REopt paradigms)
- PV nameplate capacity was already defined as DC so no change to that
- when PV is DC coupled, some power variables are defined as DC (PV capacity, production, curtailment, and battery charging)
- some variables are always defined as AC (grid purchases, grid exports, grid-to-battery charging, battery to load, and inverter capacity)
- effiencies in the battery inputs: internal losses apply only to energy stored; inverter/rectifier losses apply to power crossing the AC/DC boundary
- in addition to optimizing DC PV capacity, battery energy capacity, and battery power capacity as REopt normally does, there is a new shared inverter AC capacity decision variable (questions on this below)


## Topics for discussion

### Inverter losses
- when AC-coupled, PV production factor is the PVWatts AC output, which includes array losses and non linear inverter losses accounting for DC-AC ratio
- when DC-coupled, PV production factor is the PVWatts DC output, which includes array losses but not inverter losses
- shared inverter losses are then modeled in REopt using the storage inverter efficiency input (existing battery model includes inverter, rectifier, and internal efficiencies)
- limits on % of rated inverter capacity so constant inv effic is an ok assumption
- issue: this does not account for inverter efficiency being dependent on usage

### Shared inverter sizing
- currently sizing shared inverter based on max net flow through it, which doesn't necessarily support all possible future dispatch
- should shared inverter be sized based on combined PV and battery capacities?
- are there other operating considerations that are important to consider sich as headroom, DC-AC ratio, non-optimized future dispatch, etc?
- should there be separate sizes for inverter and rectifier?

### Costs
- can existing cost inputs be reassigned cleanly, or are separate PV array, battery power, battery energy, and shared inverter cost inputs needed to avoid double counting or omitted costs?
- current approach is to reuse the battery's per-kW cost input for the shared inverter and retain per-kWh battery cost
- does battery power hardware need its own cost? should shared inverter cost be a new additional input?
- defensible sources for cost defaults? shared inverter cost if not just using the existing battery per-kW cost? how does adding shared inverter cost affect battery power/energy cost?
- issue: PV cost defaults still include a separate inverter cost

### AC and DC charging
- initial implementation defaults to not allowing grid charging of the DC coupled battery -- should this be forbidden entirely?
- charging from AC-connected resources is never allowed if a DC coupled resource is modeled -- should this be an option (more work to add)?
- to do: decide how REopt will determine if there can be grid export from shared inverter (based on PV or battery inputs)