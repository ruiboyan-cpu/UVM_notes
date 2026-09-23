//==========================================================================
// UVM 最小验证平台 —— 填空练习
//
// 在 EDA Playground 上跑：
//   - design.sv   放【第 1 部分】DUT
//   - testbench.sv 放【第 2~8 部分】
//   - 左侧 Testbench + Design 选 SystemVerilog/Verilog
//   - UVM/OVM 选 UVM 1.2（或 1.1d）
//   - 仿真器选 VCS 或 Riviera-PRO
//
// 每个 【填空N】 处按注释提示填写。
// 已经写好的部分不用改。
//==========================================================================


//==========================================================================
// 第 1 部分：DUT  —— 放进 design.sv
//==========================================================================
module dut(clk, rst_n, rxd, rx_dv, txd, tx_en);
  input        clk;
  input        rst_n;
  input  [7:0] rxd;
  input        rx_dv;
  output [7:0] txd;
  output       tx_en;

  reg [7:0] txd;
  reg       tx_en;

  always @(posedge clk) begin
    if (!rst_n) begin
      txd   <= 8'b0;
      tx_en <= 1'b0;
    end
    else begin
      txd   <= rxd;        // 收什么发什么，延迟一拍
      tx_en <= rx_dv;
    end
  end
endmodule


//==========================================================================
// 以下全部放进 testbench.sv
//==========================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;


//==========================================================================
// 第 2 部分：interface
//==========================================================================
interface my_if(input clk, input rst_n);

  // 【填空1】声明两个信号：
  //   data —— 8 位
  //   valid —— 1 位
  //   （提示：用 logic）


endinterface


//==========================================================================
// 第 3 部分：transaction
//==========================================================================
// 【填空2】my_transaction 应该派生自哪个类？
//   提示：它是【数据】不是【组件】，用作 driver 要发送的包
class my_transaction extends ________;

  rand bit [7:0] pload[];          // 负载，动态数组

  constraint pload_size_cons {
    pload.size() inside {[4:8]};   // 长度 4~8
  }

  // 【填空3】注册宏。注意：这是 object 还是 component？
  ________(my_transaction)

  // 【填空4】构造函数。注意 uvm_object 的构造函数有几个参数？
  function new(________);
    super.new(________);
  endfunction

  // 手写一个打印函数（后面学了 field automation 就不用手写了）
  function void my_print(string tag);
    $write("[%0t] %s : size=%0d, data =", $time, tag, pload.size());
    foreach (pload[i]) $write(" %02h", pload[i]);
    $display("");
  endfunction

  // 手写一个比较函数
  function bit my_compare(my_transaction tr);
    if (pload.size() != tr.pload.size()) return 0;
    foreach (pload[i])
      if (pload[i] != tr.pload[i]) return 0;
    return 1;
  endfunction
endclass


//==========================================================================
// 第 4 部分：driver
//==========================================================================
// 【填空5】driver 派生自哪个类？
class my_driver extends ________;

  // 【填空6】声明虚接口句柄，类型是 my_if，名字叫 vif


  // 【填空7】注册宏（这是 component）
  ________(my_driver)

  // 【填空8】构造函数。uvm_component 的构造函数有几个参数？
  function new(________);
    super.new(________);
  endfunction

  function void build_phase(uvm_phase phase);
    // 【填空9】先调用父类的 build_phase


    // 【填空10】从 config_db 取出虚接口
    //   提示：类型参数是 virtual my_if
    //         前两个参数固定写 (this, "")
    //         名字用 "vif"
    //         取不到要 uvm_fatal
    if (!uvm_config_db#(________)::get(________, ________, "vif", ________))
      `uvm_fatal("my_driver", "virtual interface must be set for vif!!!")
  endfunction

  extern virtual task main_phase(uvm_phase phase);
  extern task drive_one_pkt(my_transaction tr);
endclass


task my_driver::main_phase(uvm_phase phase);
  my_transaction tr;

  // 【填空11】举手，反对结束仿真


  // 初始化信号
  vif.data  <= 8'b0;
  vif.valid <= 1'b0;

  // 【填空12】等复位释放
  //   提示：rst_n 为低时一直等时钟上升沿
  while (________)
    @(posedge vif.clk);

  // 发 5 个包
  repeat (5) begin
    // 【填空13】造一个 transaction 对象（用 new，因为是 object）
    tr = ________;

    // 【填空14】随机化，失败就 fatal
    if (!________)
      `uvm_fatal("my_driver", "randomize failed")

    tr.my_print("Driver  send");
    drive_one_pkt(tr);
  end

  repeat (5) @(posedge vif.clk);       // drain time

  // 【填空15】放下手，可以结束了

endtask


// 把 transaction 翻译成信号
task my_driver::drive_one_pkt(my_transaction tr);
  // 每拍发一个字节
  foreach (tr.pload[i]) begin
    @(posedge vif.clk);
    vif.valid <= 1'b1;
    vif.data  <= tr.pload[i];
  end
  @(posedge vif.clk);
  vif.valid <= 1'b0;
  @(posedge vif.clk);                  // 包之间留一拍间隔
endtask


//==========================================================================
// 第 5 部分：monitor
//==========================================================================
// 【填空16】monitor 派生自哪个类？
class my_monitor extends ________;

  virtual my_if vif;

  // 【填空17】声明一个 analysis port，传递的类型是 my_transaction，名字叫 ap
  //   提示：uvm_analysis_port #(类型) 名字;


  `uvm_component_utils(my_monitor)

  function new(string name = "my_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif))
      `uvm_fatal("my_monitor", "virtual interface must be set for vif!!!")

    // 【填空18】创建 analysis port
    //   提示：端口用 new 创建，不是 type_id::create
    ap = ________;
  endfunction

  extern task main_phase(uvm_phase phase);
  extern task collect_one_pkt(my_transaction tr);
endclass


task my_monitor::main_phase(uvm_phase phase);
  my_transaction tr;

  // 【填空19】monitor 是无限循环，每次收一个包然后发出去
  //   注意：这里【不要】控制 objection，想想为什么
  while (1) begin
    tr = new("tr");
    collect_one_pkt(tr);

    // 【填空20】把收到的 transaction 通过 analysis port 广播出去
    //   提示：用 write 方法

  end
endtask


// 把信号还原成 transaction
task my_monitor::collect_one_pkt(my_transaction tr);
  byte unsigned data_q[$];

  // 等 valid 拉高
  while (1) begin
    @(posedge vif.clk);
    if (vif.valid) break;
  end

  // valid 期间一直收
  while (vif.valid) begin
    data_q.push_back(vif.data);
    @(posedge vif.clk);
  end

  // 放进 transaction
  tr.pload = new[data_q.size()];
  foreach (tr.pload[i]) tr.pload[i] = data_q[i];
endtask


//==========================================================================
// 第 6 部分：scoreboard
//==========================================================================
// 【填空21】scoreboard 派生自哪个类？
class my_scoreboard extends ________;

  my_transaction expect_queue[$];      // 期望值队列

  // 【填空22】声明两个 blocking_get_port，传递 my_transaction
  //   exp_port —— 收期望值（来自输入侧 monitor）
  //   act_port —— 收实际值（来自输出侧 monitor）
  //   提示：uvm_blocking_get_port #(类型) 名字;


  `uvm_component_utils(my_scoreboard)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【填空23】创建这两个 port


  endfunction

  extern virtual task main_phase(uvm_phase phase);
endclass


task my_scoreboard::main_phase(uvm_phase phase);
  my_transaction get_expect, get_actual, tmp_tran;
  bit result;

  // 【填空24】用 fork...join 让两个无限循环并行
  //   进程1：不停从 exp_port 取期望值，push_back 进队列
  //   进程2：不停从 act_port 取实际值，pop_front 取出最早的期望值比对
  fork
    while (1) begin
      // 进程1


    end

    while (1) begin
      // 进程2
      act_port.get(get_actual);
      if (expect_queue.size() > 0) begin
        // 【填空25】从队列头部取出一个期望值
        tmp_tran = ________;

        // 【填空26】用 my_compare 比较，结果存进 result
        result = ________;

        if (result)
          `uvm_info("my_scoreboard", "Compare SUCCESSFULLY", UVM_LOW)
        else begin
          `uvm_error("my_scoreboard", "Compare FAILED")
          tmp_tran.my_print ("expect");
          get_actual.my_print("actual");
        end
      end
      else begin
        `uvm_error("my_scoreboard", "Received from DUT, but Expect Queue is empty")
      end
    end
  join
endtask


//==========================================================================
// 第 7 部分：env
//==========================================================================
// 【填空27】env 派生自哪个类？
class my_env extends ________;

  my_monitor    i_mon;                 // 输入侧 monitor
  my_monitor    o_mon;                 // 输出侧 monitor
  my_driver     drv;
  my_scoreboard scb;

  // 两个 FIFO，连接 monitor 和 scoreboard
  uvm_tlm_analysis_fifo #(my_transaction) i_mon_scb_fifo;
  uvm_tlm_analysis_fifo #(my_transaction) o_mon_scb_fifo;

  `uvm_component_utils(my_env)

  function new(string name = "my_env", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 【填空28】用 type_id::create 创建四个组件
    //   注意 parent 参数传什么
    drv   = ________;
    i_mon = ________;
    o_mon = ________;
    scb   = ________;

    // FIFO 用 new 创建（它不是通过 factory 创建的）
    i_mon_scb_fifo = new("i_mon_scb_fifo", this);
    o_mon_scb_fifo = new("o_mon_scb_fifo", this);
  endfunction

  // 【填空29】connect_phase：连接端口
  //   连接方向：port.connect(export)
  //   i_mon.ap       → i_mon_scb_fifo.analysis_export
  //   scb.exp_port   → i_mon_scb_fifo.blocking_get_export
  //   o_mon.ap       → o_mon_scb_fifo.analysis_export
  //   scb.act_port   → o_mon_scb_fifo.blocking_get_export
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);




  endfunction
endclass


//==========================================================================
// 第 8 部分：top_tb
//==========================================================================
module top_tb;

  reg clk;
  reg rst_n;

  // 两个接口实例
  my_if input_if (clk, rst_n);
  my_if output_if(clk, rst_n);

  // 【填空30】例化 DUT，把接口的信号连上去
  //   rxd   ← input_if.data
  //   rx_dv ← input_if.valid
  //   txd   → output_if.data
  //   tx_en → output_if.valid
  dut my_dut(.clk   (clk),
             .rst_n (rst_n),
             .rxd   (________),
             .rx_dv (________),
             .txd   (________),
             .tx_en (________));

  // 时钟
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // 复位
  initial begin
    rst_n = 1'b0;
    #50;
    rst_n = 1'b1;
  end

  initial begin
    // 【填空31】用 config_db 把接口传给三个组件
    //   uvm_test_top.drv    ← input_if
    //   uvm_test_top.i_mon  ← input_if
    //   uvm_test_top.o_mon  ← output_if




    // 【填空32】启动，传入 my_env 的类名字符串
    run_test(________);
  end

endmodule
