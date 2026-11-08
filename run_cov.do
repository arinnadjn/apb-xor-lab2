# Запуск со сбором кодового покрытия: do run_cov.do
# Покрытие собирается только для проверяемого устройства (apb_xor_acc.sv).
# b - ветви, c - условия, e - выражения, s - операторы, f - автомат, t - переключения
vlib work
vlog -sv -cover bcesft +incdir+. apb_xor_acc.sv
vlog -sv +incdir+. apb_master.sv top.sv
vsim -coverage work.top
add wave -r /top/*
run -all
coverage report -details -file cov_report.txt
coverage report -html -htmldir cov_html
coverage save cov.ucdb
