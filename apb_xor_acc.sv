`timescale 1ns/1ps

// APB-устройство "сложение по модулю 2 с накоплением" (вариант 10).
// Карта регистров (адрес = paddr[7:0]):
//   0x00 ADDEND  (RW) - добавляемое значение, 32 бита
//   0x04 CTRL    (RW) - контрольный регистр:
//                       бит 0 EN  - разрешение накопления (хранится);
//                       бит 1 ADD - импульс: RESULT = RESULT ^ ADDEND (если EN = 1 в этой записи);
//                       бит 2 CLR - импульс: RESULT = 0 (приоритетнее ADD);
//                       биты ADD и CLR самосбрасываются и читаются как 0
//   0x08 RESULT  (RO) - текущий результат; запись -> pslverr = 1
// Обращение по любому другому адресу -> pslverr = 1.
module apb_xor_acc
(
  input  logic        pclk,     // синхросигнал
  input  logic        presetn,  // сброс (инверсный)
  input  logic [31:0] paddr,    // адрес обращения
  input  logic [31:0] pwdata,   // данные для записи
  input  logic        psel,     // признак выбора устройства
  input  logic        penable,  // признак активной транзакции
  input  logic        pwrite,   // признак операции записи
  output logic        pready,   // готовность от устройства
  output logic        pslverr,  // признак ошибки при обращении
  output logic [31:0] prdata    // прочитанные данные
);

  // смещения регистров
  localparam [7:0] ADDR_ADDEND = 8'h00;
  localparam [7:0] ADDR_CTRL   = 8'h04;
  localparam [7:0] ADDR_RESULT = 8'h08;

  logic [31:0] reg_addend;   // добавляемое значение
  logic        reg_en;       // бит EN контрольного регистра
  logic [31:0] reg_result;   // текущий результат

  // Конечный автомат APB
  enum logic [1:0] {
    APB_SETUP,      // ожидание фазы SETUP
    APB_W_ENABLE,   // фаза ACCESS для записи
    APB_R_ENABLE    // фаза ACCESS для чтения
  } apb_st;

  always @(posedge pclk)
    if (!presetn) begin
      prdata     <= '0;
      pslverr    <= 1'b0;
      pready     <= 1'b0;
      reg_addend <= '0;
      reg_en     <= 1'b0;
      reg_result <= '0;
      apb_st     <= APB_SETUP;
    end
    else begin
      case (apb_st)

        APB_SETUP: begin : apb_setup_st
          prdata  <= '0;
          pready  <= 1'b0;
          pslverr <= 1'b0;
          if (psel && !penable) begin
            if (pwrite) apb_st <= APB_W_ENABLE;
            else        apb_st <= APB_R_ENABLE;
          end
        end : apb_setup_st

        APB_W_ENABLE: begin : apb_w_en_st
          if (psel && penable && pwrite) begin
            pready <= 1'b1;
            case (paddr[7:0])
              ADDR_ADDEND: begin
                reg_addend <= pwdata;
                $display("[%0t] DUT: WRITE ADDEND = 0x%h", $time, pwdata);
              end
              ADDR_CTRL: begin
                reg_en <= pwdata[0];
                if (pwdata[2]) begin                       // CLR: сброс результата
                  reg_result <= '0;
                  $display("[%0t] DUT: CTRL=0x%h  CLEAR, RESULT = 0", $time, pwdata);
                end
                else if (pwdata[1] && pwdata[0]) begin     // ADD при EN = 1
                  reg_result <= reg_result ^ reg_addend;
                  $display("[%0t] DUT: CTRL=0x%h  ADD, RESULT = 0x%h ^ 0x%h = 0x%h",
                           $time, pwdata, reg_result, reg_addend, reg_result ^ reg_addend);
                end
                else begin
                  $display("[%0t] DUT: CTRL=0x%h  (EN=%b)", $time, pwdata, pwdata[0]);
                end
              end
              ADDR_RESULT: begin                           // RESULT только для чтения
                pslverr <= 1'b1;
                $display("[%0t] DUT: WRITE ERROR, RESULT is read-only", $time);
              end
              default: begin
                pslverr <= 1'b1;
                $display("[%0t] DUT: WRITE ERROR, bad addr=0x%h", $time, paddr);
              end
            endcase
          end
          apb_st <= APB_SETUP;
        end : apb_w_en_st

        APB_R_ENABLE: begin : apb_r_en_st
          if (psel && penable && !pwrite) begin
            pready <= 1'b1;
            case (paddr[7:0])
              ADDR_ADDEND: begin
                prdata <= reg_addend;
                $display("[%0t] DUT: READ  ADDEND = 0x%h", $time, reg_addend);
              end
              ADDR_CTRL: begin
                prdata <= {31'b0, reg_en};                 // ADD и CLR читаются как 0
                $display("[%0t] DUT: READ  CTRL   = 0x%h", $time, {31'b0, reg_en});
              end
              ADDR_RESULT: begin
                prdata <= reg_result;
                $display("[%0t] DUT: READ  RESULT = 0x%h", $time, reg_result);
              end
              default: begin
                pslverr <= 1'b1;
                $display("[%0t] DUT: READ ERROR, bad addr=0x%h", $time, paddr);
              end
            endcase
          end
          apb_st <= APB_SETUP;
        end : apb_r_en_st

        default: begin
          pslverr <= 1'b1;
          apb_st  <= APB_SETUP;
        end
      endcase
    end

endmodule
