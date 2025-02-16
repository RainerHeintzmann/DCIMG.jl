using PyCall
using View5D

ENV["PYTHON"] = ""
# python -m venv C:\Users\Heinzmann\VirtualEnvs\JuliaEnv\DCIMG
# using Conda
# Conda.pip_interop(true)
# Conda.pip("install", "dcimg")
# ENV["PYTHON"] = raw"C:\Users\Heinzmann\VirtualEnvs\JuliaEnv\DCIMG\Scripts\python.exe"

py"""
import numpy as np
import dcimg
# import PyCall as pc

def get_dcimg(filename):
    img = np.array(dcimg.DCIMGFile(filename)[:])
    print(img.ctypes.data)
    return img

def get_dcimg_permuted(filename):
    img = dcimg.DCIMGFile(filename)[:]
    print(img.ctypes.data)
    newdims = range(img.ndim-1,-1,-1)
    #print(newdims)
    #print(img.shape)
    #print(type(img))
    img_permuted = np.transpose(img, newdims)
    #print(img_permuted.ctypes.data)
    return img_permuted
"""

function load_dcimg(filename)
    # dcimg = pyimport("dcimg")
    # np = pyimport("numpy")
    img = pycall(py"get_dcimg_permuted", PyArray, filename);
    println(pointer(img))
    # sz = ntuple(d->size(img,length(size(img))-d+1), length(size(img)))
    return img # unsafe_wrap(Array, pointer(img), sz; own=true); # 
end

function main()
    filename = raw"C:\NoBackup\Data\SIM\Retina\785nm_SIM\20250203_2016023L_83F_unkown_position_unremarkable\20250203_IR_RPE000M0.dcimg"
    img = pycall(py"get_dcimg", PyArray, filename);
    # sz = ntuple(d->size(img,length(size(img))-d+1), length(size(img)))
    # julia_array = unsafe_wrap(Array, pointer(img), sz; own=true);

    # crashes:
    img = load_dcimg(filename);
    @vv img
    # img = pycall(py"get_dcimg", Array, filename);
    q = reinterpret(reshape, eltype(img), img)
    @vv img
    println(size(img))
end

