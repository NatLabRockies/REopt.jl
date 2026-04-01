# Documenting the Code
Besides the primary methods for using REopt.jl (which are documented in docs/reopt/methods.md) users need to know what inputs and outputs are available. The REopt.jl package and the REopt API v3 and later are designed to have the same input and output names so that a user can in theory use the same JSON or dictionary inputs to either REopt.jl or the API and get the same results (assuming that the same version of REopt.jl is used in both cases). 

In many cases the REopt.jl package will lead the development of the API, that is a new capability in REopt is first developed in the Julia package, and then if necessary that capability is added to the API (and the webtool after that if necessary). This means that REopt.jl and the API will not always have the same inputs (and outputs). 

## Inputs
For each of the structs that are attached to the `Scenario` struct we document the input fields, their types, and default values if any.
In some cases documenting inputs can be as simple as copying and pasting the function signature that builds the input struct into the doc string of the function.
However, there are some cases in which a function contains input fields that are not meant to be provided/accessed by a user.
For example, the `Site.latitude` input is used in many other input constructors, such as in `PV` to look up the PVWatts production factor, but the user does not need to provide a `PV.latitude` input.
In these cases one should not include all of the function signature fields in the doc string.

Any new input function and/or struct must be added to the docs/reopt/inputs.md file for it to show up in the online documentation (see that file for examples).

For describing how to use more complicated inputs use a `note` admonition like:

!!! note
    This is an input note.


## Outputs
All of the results functions should have a list of output fields with descriptions in a bulleted list in the function doc string. 
When adding a new results function it should be added to the docs/reopt/outputs.md file so that it shows up in the online documentation.
There is no need to include the function signature in the doc string.


## Testing Documentation
Test documentation changes locally to confirm they are working as intended. See docs/README.md for instructions. If Documenter cannot find your doc strings, ensure that there is no extra line between the doc string and the function. 