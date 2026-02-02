using LiveServer

"""
Run this script to locally host the REopt.jl documentation.
NOTE you have to dev REopt in the `docs` environment to get local changes. 

e.g. 
```julia
[~/.julia/dev/REopt/docs]
(docs) pkg> activate .
(docs) pkg> dev REopt
julia> include("devdeploy.jl")
[ Info: Precompiling REopt [d36ad4e8-d74a-4f7a-ace1-eaea049febf6]
...
✓ LiveServer listening on http://localhost:8000/ ...
  (use CTRL+C to shut down)
```
"""
function devbuildserve()
    rm("build", force=true, recursive=true)
    include("make.jl")
    cd("build")
    serve()
end

devbuildserve()