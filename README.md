# DCIMG.jl
Loads data, written in the Hamamatsu DCIMG format into an array and provides timestamp data. 

This code is hastily written based on https://github.com/lens-biophotonics/dcimg
a Python package that loads DCIMG files.
However, only few features are actually currently implemented.
Most probably only the new format can be read properly.
If you want full support you can use the Python package together with `PyJulia.jl` or `PythonJulia.jl`. An example of this, you can find in the examples directory.
