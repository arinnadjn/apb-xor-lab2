# Запуск в ModelSim: do run.do  (в окне Transcript, в папке проекта)
vlib work
vlog -sv +incdir+. apb_xor_acc.sv apb_master.sv top.sv
vsim work.top
add wave -r /top/*
run -all
