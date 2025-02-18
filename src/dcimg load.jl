
const FMT_OLD = 1
const FMT_NEW = 2

mutable struct DCIMGFile
    file_path::String
    mm::Array
    offset::Int
    data::Array{UInt16, 3}
    nfrms::Int
    byte_depth::Int
    xsize::Int
    ysize::Int
    bytes_per_row::Int
    bytes_per_img::Int
    fmt_version::Int
    x0::Int
    y0::Int
    binning::Int
    _target_line::Int  #: target line for 4px correction
    header_size::Int
    session_footer_offset::Int
    _4px::Array{UInt16, 2}
    _fs_data::Array{UInt32, 1}
    _ts_data::Array{UInt32, 2}
    deep_copy_enabled::Bool
    first_4px_correction_enabled::Bool
    target_line::Int
    _file_header::Dict{String, Any}
    _sess_header::Dict{String, Any}
    _sess_footer::Dict{String, Any}
    _sess_footer2::Dict{String, Any}
end

FILE_HDR_DTYPE = [
    ("file_format", "S8"),
    ("format_version", "<u4"),  # 0x08
    ("skip", "5<u4"),           # 0x0c
    ("nsess", "<u4"),           # 0x20 ?
    ("nfrms", "<u4"),           # 0x24
    ("header_size", "<u4"),     # 0x28 ?
    ("skip2", "<u4"),           # 0x2c
    ("file_size", "<u8"),       # 0x30
    ("skip3", "2<u4"),          # 0x38
    ("file_size2", "<u8"),      # 0x40, repeated
]

SESS_HDR_DTYPE = [
    ("session_size", "<u8"),  # including footer
    ("skip1", "6<u4"),
    ("nfrms", "<u4"),
    ("byte_depth", "<u4"),
    ("skip2", "<u4"),
    ("xsize", "<u4"),
    ("bytes_per_row", "<u4"),
    ("ysize", "<u4"),
    ("bytes_per_img", "<u4"),
    ("skip3", "2<u4"),
    ("offset_to_data", "<u4"),
    ("session_data_size", "<u8"),  # header_size + x*y*byte_depth*nfrms
]

SESSION_FOOTER_DTYPE = [
    ("format_version", "<u4"),
    ("skip0", "<u4"),
    ("offset_to_2nd_struct", "<u8"),
    ("skip1", "2<u4"),
    ("offset_to_offset_to_end_of_data", "<u8"),
    ("skip2", "2<u4"),
    ("footer_size", "<u4"),
    ("skip3", "<u4"),

    # an almost empty part after the footer
    # contains "offset_to_end_of_data", 0x00000000 0x00000000
    # repeated 2 * nfrms times
    ("2nd_footer_size", "<u4"),  # = 2 * nfrms * 16

    ("skip4", "19<u4"),
    ("offset_to_end_of_data", "<u8"),  # sum of the two offsets above
    ("skip5", "<u8"),  # sum of the two offsets above
    ("offset_to_end_of_data_again", "<u8"),  # repeated
    ("skip6", "<u8"),  # repeated
]

SESSION_FOOTER2_DTYPE = [
    ("offset_to_offset_to_timestamps", "<u8"),
    ("skip0", "2<u4"),
    ("offset_to_offset_to_frame_counts", "<u8"),
    ("skip1", "2<u4"),
    ("offset_to_offset_to_4px", "<u8"),
    ("skip2", "2<u4"),
    ("offset_to_frame_counts", "<u8"),
    ("skip3", "2<u4"),
    ("offset_to_timestamps", "<u8"),
    ("skip4", "4<u4"),
    ("offset_to_4px", "<u8"),
    ("skip5", "<u4"),
    ("4px_offset_in_frame", "<u4"),

    # this is zero if there is no 4px correction info in the footer
    # (maybe because of cropping, so the first line is not included) and
    # is 8 if there is 4px correction info stored in the footer. Might be
    # the size in bytes of the 4px correction for each frame (8 = 4 * 2)
    ("4px_size", "<u8"),
]

# newer versions of the dcimg format have a different header
NEW_SESSION_HEADER_DTYPE = [
    ("session_size", "<u8"),
    ("skip1", "13<u4"),
    ("nfrms", "<u4"),
    ("byte_depth", "<u4"),
    ("skip2", "<u4"),
    ("xsize", "<u4"),
    ("ysize", "<u4"),
    ("bytes_per_row", "<u4"),
    ("bytes_per_img", "<u4"),
    ("skip3", "2<u4"),
    ("offset_to_data", "<u8"),
    ("skip4", "5<u4"),
    ("frame_footer_size", "<u4"),
]

NEW_FRAME_FOOTER_CAMLINK_DTYPE = [
    ("progressive_number", "<u4"),
    ("timestamp", "<u4"),
    ("timestamp_frac", "<u4"),
    ("4px", "<u8"),
    ("zeros", "3<u4"),
]

NEW_FRAME_FOOTER_USB_DTYPE = [
    ("progressive_number", "<u4"),
    ("timestamp", "<u4"),
    ("timestamp_frac", "<u4"),
    ("zeros", "<u4"),
]

NEW_CROP_INFO = [
    ("x0", "<u2"),
    ("xsize", "<u2"),
    ("y0", "<u2"),
    ("ysize", "<u2"),
]


"""
    read_field(mm::Vector{UInt8}, dtype_str::String)

reads a single field from a memory-mapped array using the data typ string `dtype_str`.
"""
function read_field(dcimg, dstdict, field_name, field_type_str::String)
    DTYPE_MAP = Dict(
        "S8" => NTuple{8, UInt8},
        "<u4" => UInt32,
        "<i4" => Int32,
        "<f8" => Float64,
        "5<u4" => NTuple{5, UInt32},
        "<u8" => UInt64,
        "2<u4" => NTuple{2, UInt32},
        "6<u4" => NTuple{6, UInt32},
        "<u2" => UInt16,
        "13<u4" => NTuple{13, UInt32},
        # Add more mappings as needed
    )
    # Parse the dtype string
    field_type = DTYPE_MAP[field_type_str]
    field_size = sizeof(field_type)
    field_data = reinterpret(field_type, dcimg.mm[dcimg.offset+1:dcimg.offset+field_size])
    dstdict[field_name] = field_data[1]
    dcimg.offset += field_size
end

function read_block(dcimg, dst_dict, FieldBlock)
    for (name, dtype) in FieldBlock
        read_field(dcimg, dst_dict, name, dtype)
    end
end
# Example usage
# dcimg = Dict("mm" => rand(UInt8, 100))  # Replace with actual memory-mapped array
# dtype_str = "x0:<u2,xsize:<u2,y0:<u2,ysize:<u2"
# result = read(dcimg["mm"], dtype_str)
# println(result)

function _parse_header(dcimg::DCIMGFile)
    dcimg.offset = 0
    # dcimg._file_header = Dict{String, Any}()
    read_block(dcimg, dcimg._file_header, FILE_HDR_DTYPE)
    if !startswith(String(collect(dcimg._file_header["file_format"])), "DCIMG")
        throw(ArgumentError("Invalid DCIMG file"))
    end
    dcimg.nfrms = Int(dcimg._file_header["nfrms"])
    header_size = Int(dcimg._file_header["header_size"])
    dcimg.offset = header_size

    if dcimg._file_header["format_version"] == 0x7
        # sess_dtype = SESS_HDR_DTYPE
        dcimg.fmt_version = FMT_OLD
        read_block(dcimg, dcimg._sess_header, SESS_HDR_DTYPE)
    elseif dcimg._file_header["format_version"] == 0x1000000 || dcimg._file_header["format_version"] == 0x2000000
        dcimg.fmt_version = FMT_NEW
        # sess_dtype = NEW_SESSION_HEADER_DTYPE
        read_block(dcimg, dcimg._sess_header, NEW_SESSION_HEADER_DTYPE)
        # @show length(dcimg._sess_header)
    else
        throw(ArgumentError("Invalid DCIMG format version: 0x$(string(dcimg._file_header["format_version"], base=16))"))
    end

    dcimg.xsize = Int(dcimg._sess_header["xsize"])
    dcimg.ysize = Int(dcimg._sess_header["ysize"])
    dcimg.bytes_per_img = Int(dcimg._sess_header["bytes_per_img"]) 

    # if dcimg.fmt_version == FMT_NEW
    #     i = header_size + 712
    #     crop_info = Dict{String, Any}()
    #     read_block(dcimg, crop_info, NEW_CROP_INFO)

    #     @show crop_info
    #     dcimg.x0 = crop_info["x0"]
    #     dcimg.y0 = crop_info["y0"]
    #     binning_x = crop_info["xsize"] ÷ dcimg.xsize
    #     binning_y = crop_info["ysize"] ÷ dcimg.ysize

    #     if binning_x != binning_y
    #         throw(ArgumentError("different binning in X and Y"))
    #     end

    #     if binning_x > 0
    #         dcimg.binning = binning_x
    #     end
    # end

    # if dcimg.byte_depth != 1 && dcimg.byte_depth != 2
    #     throw(ArgumentError("Invalid byte-depth: $(dcimg.byte_depth)"))
    # end

    # if dcimg.bytes_per_img != dcimg.bytes_per_row * dcimg.ysize
    #     throw(ArgumentError("invalid value for bytes_per_img"))
    # end
end


function _parse_footer(dcimg::DCIMGFile)
    if dcimg.fmt_version != FMT_OLD
        return
    end

    dcimg._sess_footer = Dict{String, Any}()
    for (name, dtype) in SESSION_FOOTER_DTYPE
        dcimg._sess_footer[name] = read_field(dcimg.mm, dtype)
    end

    dcimg.offset = dcimg.session_footer_offset + dcimg._sess_footer["offset_to_2nd_struct"]

    dcimg._sess_footer2 = Dict{String, Any}()
    for (name, dtype) in SESSION_FOOTER2_DTYPE
        dcimg._sess_footer2[name] = read_field(dcimg.mm, dtype)
    end

end

"""
    load_dcimg(filename)

loads a DCIMG file and returns a `DCIMGFile` object. The raw data can be accessed via the `data` field of the returned object.

Parameters:
- `filename::String`: The path to the DCIMG file to load.

Returns:
- A `DCIMGFile` object representing the loaded DCIMG file.

Example:
```julia
dcimg = load_dcimg("path/to/file.dcimg")
```
"""
function load_dcimg(filename)
    return DCIMGFile(filename)
end

"""
Whether the footer contains 4px correction

Returns
-------
bool
"""
function _has_4px_data(dcimg)
    if (dcimg.fmt_version == FMT_NEW)
        if (Int(dcimg._sess_header["frame_footer_size"]) >= 512)
            return True
        end
        return sizeof(NEW_FRAME_FOOTER_CAMLINK_DTYPE) == dcimg._sess_header["frame_footer_size"]
    end
    # maybe this is sufficient
    # return int(self._sess_footer2['4px_size']) > 0

    footer_size = Int(dcimg._sess_footer["footer_size"])
    offset_to_4px = Int(dcimg._sess_footer2["offset_to_4px"])

    return footer_size == offset_to_4px + 8 * dcimg.nfrms
end

function DCIMGFile(file_path::String)
    mm = mmap(file_path)

    header_size = 0x28  # Example value, adjust as needed
    nfrms = 1  # Example value, adjust as needed
    byte_depth = 2  # Example value, adjust as needed
    xsize = 1  # Example value, adjust as needed
    ysize = 1  # Example value, adjust as needed
    offset = 0
    bytes_per_row = xsize * byte_depth
    bytes_per_img = ysize * bytes_per_row
    fmt_version = 1  # Example value, adjust as needed
    x0=0
    y0=0
    binning=1
    _target_line = -1  #: target line for 4px correction

    session_footer_offset = header_size + nfrms * bytes_per_img
    _4px = zeros(UInt16, nfrms, 4)
    _fs_data = zeros(UInt32, nfrms)
    _ts_data = zeros(UInt32, nfrms, 2)
    deep_copy_enabled = true
    first_4px_correction_enabled = true
    target_line = -1
    _file_header=Dict{String, Any}()
    _sess_header=Dict{String, Any}()
    _sess_footer=Dict{String, Any}()
    _sess_footer2=Dict{String, Any}()
    data = zeros(UInt16, 1, 1, 1)

    dcimg = DCIMGFile(file_path, mm, offset, data, nfrms, byte_depth, xsize, ysize, bytes_per_row, bytes_per_img, fmt_version, 
            x0, y0, binning, _target_line, header_size,
            session_footer_offset, _4px, _fs_data, _ts_data, deep_copy_enabled, first_4px_correction_enabled, target_line,
            _file_header, _sess_header, _sess_footer, _sess_footer2)

    _parse_header(dcimg)
    _parse_footer(dcimg)
    data_offset = (Int(dcimg._file_header["header_size"]) + Int(dcimg._sess_header["offset_to_data"]))
    data_strides = nothing

    if (dcimg.fmt_version == FMT_OLD)
        if _has_4px_data(dcimg)
            offset = self._session_footer_offset + int(self._sess_footer2["offset_to_4px"])
            dcimg._4px = zeros(dcimg.nfrms, 4)
                # dcimg.dtype, dcimg.mm, offset)
        end
        data_strides = (dcimg.bytes_per_img, dcimg.bytes_per_row, dcimg.byte_depth)
    elseif (dcimg.fmt_version == FMT_NEW)
        frame_footer_size = Int(dcimg._sess_header["frame_footer_size"][1])
        if _has_4px_data(dcimg)
            strides = (dcimg.bytes_per_img + frame_footer_size, bd)
            dcimg._4px = zeros(dcimg.nfrms, 8 // dcimg.byte_depth)
            # np.ndarray((dcimg.nfrms, 8 // dcimg.byte_depth), dcimg.dtype, dcimg.mm, data_offset + dcimg.bytes_per_img + 12, strides)
        end
        padding = dcimg.bytes_per_img - dcimg.xsize * dcimg.ysize * dcimg.byte_depth
        padding ÷= dcimg.ysize
        data_strides = (dcimg.bytes_per_img + frame_footer_size, dcimg.xsize * dcimg.byte_depth + padding, dcimg.byte_depth)
    end

    footer_size = Int(dcimg._sess_header["frame_footer_size"])
    # self.mma = np.ndarray(self.shape, self.dtype, self.mm, data_offset, data_strides)

    datsz = (dcimg.xsize+padding÷2, dcimg.ysize, dcimg.nfrms)

    dcimg.data = Array{UInt16}(undef, datsz)
    #@show datsz = (dcimg.ysize, dcimg.xsize, dcimg.nfrms)
    #@show datsz = (dcimg.nfrms, dcimg.ysize, dcimg.xsize)
    # @show prod(datsz)*2
    # @show size(mm[data_offset+1:end])
    dcimg.mm = mm
    # @show typeof(mm)
    # byte_array = mm[end-prod(datsz)*2+1:end]
    frame_start = data_offset+1
    frame_size =  dcimg.bytes_per_img # 2*datsz[1]*datsz[2]
    skip_bytes = 32  # 4 bytes framestamp, 4 bytes timestamp, 4 bytes timestamp fraction, 4 bytes 4px correction, 16 bytes unknown
    dcimg._fs_data = zeros(UInt32, dcimg.nfrms)
    dcimg._ts_data = zeros(UInt32, dcimg.nfrms, 2)
    n=1
    for s in eachslice(dcimg.data, dims=3)
        # s .= reshape(reinterpret(UInt16, mm[frame_start:frame_start+frame_size-1]), datsz[1:2])
        s[:] .= reinterpret(UInt16, mm[frame_start:frame_start+frame_size-1])
        fs = reinterpret(UInt32, mm[frame_start+frame_size:frame_start+frame_size+3])[1]
        dcimg._fs_data[n] = fs
        ts1 = reinterpret(UInt32, mm[frame_start+frame_size+4:frame_start+frame_size+7])[1]
        ts2 = reinterpret(UInt32, mm[frame_start+frame_size+8:frame_start+frame_size+11])[1]
        dcimg._ts_data[n, 1] = ts1
        dcimg._ts_data[n, 2] = ts2
        frame_start += data_strides[1] # frame_size .+ skip_bytes
        n += 1
    end

    # dcimg.data = reinterpret(reshape, Array{UInt16}, mm[end-prod(datsz)*2+1:end]) # , datsz)
    # dcimg.data = reshape(mm[end-prod(datsz)+1:end], datsz)
    # close(dcimg.mm)

    return dcimg
end

# function close(dcimg::DCIMGFile)
#     Mmap.munmap(dcimg.mm)
# end

# function shape(dcimg::DCIMGFile)
#     return (dcimg.nfrms, dcimg.ysize, dcimg.xsize)
# end

# function frame(dcimg::DCIMGFile, index::Int)
#     return dcimg.data[:, :, index]
# end

# function whole(dcimg::DCIMGFile)
#     return dcimg.data
# end

"""
    s_since_start(dcimg::DCIMGFile)

returns the frame-times in seconds since the first measured frame for each frame. The time resolutio is down to microseconds.
"""
function s_since_start(dcimg::DCIMGFile)
    whole_s = Float64(dcimg._ts_data[1,1])
    frac_s = Float64(dcimg._ts_data[1,2])
    return [(dcimg._ts_data[i,1]-whole_s)+(dcimg._ts_data[i,2]-frac_s)./1e6 for i in 1:dcimg.nfrms]
end

"""
    timestamps(dcimg::DCIMGFile)

returns the timestamps for each frame as a vector of DateTime objects. The time resolution is down to milliseconds.

See s_since_start() for microseconds time resolution.
"""
function timestamps(dcimg::DCIMGFile)
    return [ts(dcimg, i) for i in 1:dcimg.nfrms]
end

function ts(dcimg::DCIMGFile, frame::Int)
    whole = dcimg._ts_data[frame, 1]
    fraction = dcimg._ts_data[frame, 2]
    milliseconds = whole*10^3 + fraction÷1000
    datetime = DateTime(1970, 1, 1) + Millisecond(milliseconds)
    return datetime
end
