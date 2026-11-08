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

    // --- 1. значения после сброса ---
    $display("[MASTER] test 1: reset values");
    check_all();

    // --- 2. базовое накопление: RESULT = 0 ^ A5A5A5A5 ---
    $display("[MASTER] test 2: basic accumulate");
    write_addend(32'hA5A5_A5A5);
    write_ctrl(32'h3);                // EN = 1, ADD = 1
    check_all();

    // --- 3. повторное сложение того же числа возвращает прежний результат ---
    $display("[MASTER] test 3: accumulate twice");
    write_ctrl(32'h3);
    check_all();                      // RESULT = 0
    write_ctrl(32'h3);
    check_all();                      // RESULT = A5A5A5A5

    // --- 4. накопление разных значений ---
    $display("[MASTER] test 4: different addends");
    write_addend(32'h5A5A_5A5A);
    write_ctrl(32'h3);
    check_all();                      // RESULT = FFFFFFFF
    write_addend(32'hFFFF_FFFF);
    write_ctrl(32'h3);
    check_all();                      // RESULT = 0
    write_addend(32'h0000_0000);
    write_ctrl(32'h3);
    check_all();

    // --- 5. ADD при EN = 0 не изменяет результат ---
    $display("[MASTER] test 5: ADD with EN=0");
    write_addend(32'h1234_5678);
    write_ctrl(32'h3);                // RESULT = 12345678
    write_ctrl(32'h2);                // ADD = 1, EN = 0: игнорируется
    check_all();
    write_ctrl(32'h0);                // EN = 0
    check_all();

    // --- 6. CLR сбрасывает результат; CLR приоритетнее ADD ---
    $display("[MASTER] test 6: CLR");
    write_ctrl(32'h1);                // EN = 1 без ADD
    write_ctrl(32'h4);                // CLR при EN = 0
    check_all();
    write_ctrl(32'h3);                // RESULT = 12345678
    write_ctrl(32'h7);                // CLR + ADD + EN: побеждает CLR
    check_all();                      // RESULT = 0

    // --- 7. зарезервированные биты CTRL читаются как 0 ---
    $display("[MASTER] test 7: reserved bits");
    write_ctrl(32'hFFFF_FFF9);        // EN = 1, ADD = 0, CLR = 0, остальные биты = 1
    check_all();

    // --- 8. ошибки: запись в RESULT, неверные адреса ---
    $display("[MASTER] test 8: errors");
    write_ctrl(32'h1);
    write_addend(32'hDEAD_BEEF);
    write_ctrl(32'h3);
    apb_write(BASE_ADDR + OFF_RESULT, 32'hFFFF_FFFF);   // RESULT только для чтения
    check_slverr(1'b1);
    check_all();                                        // результат не изменился
    apb_write(BASE_ADDR + 32'h0C, 32'h1);               // несуществующий адрес
    check_slverr(1'b1);
    apb_write(BASE_ADDR + 32'h80, 32'h1);
    check_slverr(1'b1);
    apb_read(BASE_ADDR + 32'h0C, dummy);                // чтение несуществующего адреса
    check_slverr(1'b1);
    apb_read(BASE_ADDR + 32'hFC, dummy);
    check_slverr(1'b1);
    apb_write(BASE_ADDR + OFF_ADDEND, 32'h1);           // обращение без ошибки
    exp_addend = 32'h1;
    check_slverr(1'b0);                                 // pslverr сброшен
    check_all();

    // --- 9. алиас адреса: старшие биты адреса не декодируются ---
    $display("[MASTER] test 9: address alias");
    apb_write(32'hFFFF_FF00 + OFF_ADDEND, 32'hC3C3_C3C3);
    exp_addend = 32'hC3C3_C3C3;
    apb_read_check(32'h0000_0000 + OFF_ADDEND, 32'hC3C3_C3C3);
    apb_write(32'h8F0F_0F00 + OFF_CTRL, 32'h5);         // CLR + EN
    exp_en = 1'b1; exp_result = '0;
    apb_read_check(32'h7070_7004, 32'h1);
    apb_read_check(32'h0F0F_0F08, exp_result);

    // --- 10. псевдослучайная последовательность ---
    $display("[MASTER] test 10: pseudo-random");
    for (i = 0; i < 40; i = i + 1) begin
      lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
      write_addend(lfsr ^ {lfsr[15:0], lfsr[31:16]});
      lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
      write_ctrl({29'b0, lfsr[2:0]});
      check_all();
    end

    // --- 11. обрыв обмена: устройство не должно менять регистры ---
    $display("[MASTER] test 11: aborted transfers");
    write_addend(32'h1111_2222);
    write_ctrl(32'h1);
    apb_abort(BASE_ADDR + OFF_ADDEND, 1'b1, 2'd0);      // запись: psel снят сразу
    apb_abort(BASE_ADDR + OFF_RESULT, 1'b0, 2'd0);      // чтение: psel снят сразу
    apb_abort(BASE_ADDR + OFF_ADDEND, 1'b1, 2'd1);      // запись: psel удержан без penable
    apb_abort(BASE_ADDR + OFF_RESULT, 1'b0, 2'd1);      // чтение: psel удержан без penable
    apb_abort(BASE_ADDR + OFF_ADDEND, 1'b1, 2'd2);      // запись: penable при смене направления
    apb_abort(BASE_ADDR + OFF_RESULT, 1'b0, 2'd2);      // чтение: penable при смене направления
    apb_abort(BASE_ADDR + OFF_ADDEND, 1'b1, 2'd3);      // запись: penable при снятом psel
    apb_abort(BASE_ADDR + OFF_RESULT, 1'b0, 2'd3);      // чтение: penable при снятом psel
    check_all();                                        // регистры не изменились
    write_ctrl(32'h3);                                  // и обмен после обрыва работает
    check_all();

    if (errors == 0) $display("[MASTER] TEST PASSED");
    else             $display("[MASTER] TEST FAILED, errors = %0d", errors);

    repeat (10) @(posedge pclk);
    done = 1'b1;
  end

endmodule
