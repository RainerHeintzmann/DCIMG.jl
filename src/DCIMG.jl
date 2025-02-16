module DCIMG
using Mmap
using Dates

export DCIMGFile, timestamps, s_since_start #, _parse_footer, _parse_header

include("dcimg load.jl")

end # module DCIMG
