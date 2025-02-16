using DCIMG
using View5D

function main()
    file_path = raw"C:\NoBackup\Data\SIM\IRSIM\20250203_IR_RPE\785\20250203_IR_RPE000M0.dcimg"
    # file_path = raw"C:\NoBackup\Data\SIM\Retina\785nm_SIM\20250203_2016023L_83F_unkown_position_unremarkable\20250203_IR_RPE000M0.dcimg"
    dcimg = DCIMGFile(file_path);
    @vv dcimg.data
    timestamps(dcimg)
    s_since_start(dcimg)
end
