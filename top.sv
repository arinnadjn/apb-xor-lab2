`timescale 1ns/1ps

// Модуль верхнего уровня: тактовый сигнал, сброс, соединение master <-> устройство.
module top;

  logic        pclk = 1'b0;
  logic        presetn = 1'b0;
  wire         psel, penable, pwrite;
  wire  [31:0] paddr, pwdata;
  wire         pready, pslverr;
  wire  [31:0] prdata;
  wire         done;

  // тактовый сигнал, период 20 нс
  always #10 pclk = ~pclk;

  // сброс: активен 5 тактов
  initial begin
    repeat (5) @(posedge pclk);
    presetn = 1'b1;
  end

  apb_master #(.BASE_ADDR(32'h7000_0000)) u_master (
    .pclk(pclk), .presetn(presetn),
    .psel(psel), .penable(penable), .pwrite(pwrite),
    .paddr(paddr), .pwdata(pwdata),
    .pready(pready), .pslverr(pslverr), .prdata(prdata),
    .done(done)
  );

  apb_xor_acc u_dut (
    .pclk(pclk), .presetn(presetn),
    .paddr(paddr), .pwdata(pwdata),
    .psel(psel), .penable(penable), .pwrite(pwrite),
    .pready(pready), .pslverr(pslverr), .prdata(prdata)
  );

  // завершение моделирования
  initial begin
    wait (done);
    $display("Simulation finished at %0t", $time);
    $stop;
  end

  // защита от зависания
  initial begin
    #1000000;
    $display("TIMEOUT");
    $stop;
  end

endmodule
