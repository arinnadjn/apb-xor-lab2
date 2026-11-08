`timescale 1ns/1ps

// Модель APB-мастера (bus functional model) из Л/Р 1.
// Задачи apb_write / apb_read / apb_read_check не изменены;
// заменена только тестовая последовательность (блок initial).
module apb_master
#(
  parameter [31:0] BASE_ADDR = 32'h7000_0000  // базовый адрес устройства на шине
)
(
  input  logic        pclk,     // синхросигнал
  input  logic        presetn,  // сброс (инверсный)
  output logic        psel,     // выбор устройства
  output logic        penable,  // фаза ACCESS
  output logic        pwrite,   // 1 - запись, 0 - чтение
  output logic [31:0] paddr,    // адрес
  output logic [31:0] pwdata,   // данные для записи
  input  logic        pready,   // готовность slave
  input  logic        pslverr,  // ошибка slave
  input  logic [31:0] prdata,   // прочитанные данные
  output logic        done      // 1 - тест закончен
);

  logic last_slverr;            // значение pslverr в последней транзакции

  // ---------------- запись ----------------
  task apb_write(input [31:0] addr, input [31:0] data);
    begin
      wait ((penable == 0) && (pready == 0));
      @(posedge pclk);
      psel  <= 1'b1;            // фаза SETUP
      paddr <= addr;
      pwdata <= data;
      pwrite <= 1'b1;
      @(posedge pclk);
      penable <= 1'b1;          // фаза ACCESS
      @(posedge pclk);
      wait (pready == 1'b1);
      last_slverr = pslverr;
      @(posedge pclk);
      psel    <= 1'b0;
      penable <= 1'b0;
      pwrite  <= 1'b0;
      @(posedge pclk);
    end
  endtask

  // ---------------- чтение ----------------
  task apb_read(input [31:0] addr, output logic [31:0] data);
    begin
      wait ((penable == 0) && (pready == 0));
      @(posedge pclk);
      psel   <= 1'b1;           // фаза SETUP
      pwrite <= 1'b0;
      paddr  <= addr;
      @(posedge pclk);
      penable <= 1'b1;          // фаза ACCESS
      @(posedge pclk);
      wait (pready == 1'b1);
      last_slverr = pslverr;
      @(posedge pclk);
      data <= prdata;
      psel    <= 1'b0;
      penable <= 1'b0;
      @(posedge pclk);
    end
  endtask

  // ---------------- проверки ----------------
  integer errors = 0;           // счетчик ошибок

  task apb_read_check(input [31:0] addr, input [31:0] expected);
    logic [31:0] got;
    begin
      apb_read(addr, got);
      if (got === expected)
        $display("[MASTER] PASS: addr=0x%h data=0x%h", addr, got);
      else begin
        errors = errors + 1;
        $display("[MASTER] FAIL: addr=0x%h expected=0x%h got=0x%h", addr, expected, got);
      end
    end
  endtask

  // проверка признака pslverr последней транзакции
  task check_slverr(input expected);
    begin
      if (last_slverr === expected)
        $display("[MASTER] PASS: pslverr = %b", last_slverr);
      else begin
        errors = errors + 1;
        $display("[MASTER] FAIL: pslverr expected=%b got=%b", expected, last_slverr);
      end
    end
  endtask

  // ---------------- смещения регистров устройства ----------------
  localparam [31:0] OFF_ADDEND = 32'h0;
  localparam [31:0] OFF_CTRL   = 32'h4;
  localparam [31:0] OFF_RESULT = 32'h8;

  // ---------------- эталонная модель устройства ----------------
  logic [31:0] exp_addend = '0;
  logic        exp_en     = 1'b0;
  logic [31:0] exp_result = '0;

  // запись ADDEND с обновлением модели
  task write_addend(input [31:0] v);
    begin
      apb_write(BASE_ADDR + OFF_ADDEND, v);
      exp_addend = v;
    end
  endtask

  // запись CTRL с обновлением модели
  task write_ctrl(input [31:0] v);
    begin
      apb_write(BASE_ADDR + OFF_CTRL, v);
      exp_en = v[0];
      if (v[2])                exp_result = '0;
      else if (v[1] && v[0])   exp_result = exp_result ^ exp_addend;
    end
  endtask

  // чтение и проверка всех трех регистров по модели
  task check_all;
    begin
      apb_read_check(BASE_ADDR + OFF_ADDEND, exp_addend);
      apb_read_check(BASE_ADDR + OFF_CTRL,   {31'b0, exp_en});
      apb_read_check(BASE_ADDR + OFF_RESULT, exp_result);
    end
  endtask

  // обрыв обмена (нарушение протокола) после фазы SETUP. Устройство должно вернуться
  // в ожидание, не выставив pready и не изменив регистры. Виды нарушения (kind):
  //   0 - psel снимается сразу;
  //   1 - psel удерживается еще один такт при penable = 0;
  //   2 - penable = 1, но направление pwrite меняется на противоположное;
  //   3 - penable = 1, но psel снимается.
  task apb_abort(input [31:0] addr, input wr, input [1:0] kind);
    begin
      wait ((penable == 0) && (pready == 0));
      @(posedge pclk);
      psel   <= 1'b1;
      pwrite <= wr;
      paddr  <= addr;
      pwdata <= 32'h0BAD_0BAD;
      @(posedge pclk);                // устройство видит SETUP
      case (kind)
        2'd0: begin
          psel <= 1'b0; pwrite <= 1'b0;
        end
        2'd1: begin
          @(posedge pclk);            // psel остается 1, penable = 0
          psel <= 1'b0; pwrite <= 1'b0;
        end
        2'd2: begin
          penable <= 1'b1; pwrite <= ~wr;
          @(posedge pclk);
          psel <= 1'b0; penable <= 1'b0; pwrite <= 1'b0;
        end
        2'd3: begin
          psel <= 1'b0; penable <= 1'b1;
          @(posedge pclk);
          penable <= 1'b0; pwrite <= 1'b0;
        end
      endcase
      @(posedge pclk);
      @(posedge pclk);
    end
  endtask

  // ---------------- тестовая последовательность ----------------
  logic [31:0] lfsr;            // псевдослучайные числа (одинаковы во всех симуляторах)
  logic [31:0] dummy;
  integer i;

  initial begin
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    paddr   = '0;
    pwdata  = '0;
    done    = 1'b0;
    last_slverr = 1'b0;
    lfsr    = 32'hACE1_2468;

    wait (presetn === 1'b1);          // ждем снятия сброса
    repeat (5) @(posedge pclk);

    // --- базовый тест: RESULT = 0 ^ A5A5A5A5 ---
    $display("[MASTER] basic test: accumulate");
    write_addend(32'hA5A5_A5A5);
    write_ctrl(32'h3);                // EN = 1, ADD = 1
    apb_read_check(BASE_ADDR + OFF_RESULT, 32'hA5A5_A5A5);

    if (errors == 0) $display("[MASTER] TEST PASSED");
    else             $display("[MASTER] TEST FAILED, errors = %0d", errors);

    repeat (10) @(posedge pclk);
    done = 1'b1;
  end

endmodule
