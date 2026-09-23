//==========================================================================
// UVM 标准验证平台 —— 重构练习
//
// 基于你跑通的最小版，加上四块：
//   ① sequence     —— 激励从 driver 剥离出来
//   ② sequencer    —— 中转
//   ③ agent        —— 打包 driver + monitor（+ sequencer）
//   ④ test         —— 配置层，选 sequence
//
// 树形结构变成：
//   uvm_test_top (my_case0)
//        └── env
//             ├── i_agt (ACTIVE)   ── sqr, drv, mon
//             ├── o_agt (PASSIVE)  ── mon
//             └── scb
//
// EDA Playground 设置同上次（UVM 1.2 + VCS/Riviera）
// Run Options 填：+UVM_TESTNAME=my_case0
//==========================================================================


//==========================================================================
// 第 1 部分：DUT —— design.sv（不变）
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
      txd   <= rxd;
      tx_en <= rx_dv;
    end
  end
endmodule


//==========================================================================
// 以下放进 testbench.sv
//==========================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;


//==========================================================================
// 第 2 部分：interface（不变）
//==========================================================================
interface my_if(input clk, input rst_n);
  logic [7:0] data;
  logic       valid;
endinterface


//==========================================================================
// 第 3 部分：transaction（不变）
//==========================================================================
class my_transaction extends uvm_sequence_item;

  rand bit [7:0] pload[];

  constraint pload_size_cons {
    pload.size() inside {[4:8]};
  }

  `uvm_object_utils(my_transaction)

  function new(string name = "my_transaction");
    super.new(name);
  endfunction

  function void my_print(string tag);
    $write("[%0t] %s : size=%0d, data =", $time, tag, pload.size());
    foreach (pload[i]) $write(" %02h", pload[i]);
    $display("");
  endfunction

  function bit my_compare(my_transaction tr);
    if (pload.size() != tr.pload.size()) return 0;
    foreach (pload[i])
      if (pload[i] != tr.pload[i]) return 0;
    return 1;
  endfunction
endclass


//==========================================================================
// 第 4 部分：sequencer  ★新增
//==========================================================================
// 【填空1】sequencer 派生自哪个类？注意要带参数（transaction 类型）
class my_sequencer extends ________;

  `uvm_component_utils(my_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
// ↑ 注意：sequencer 一行逻辑都不用写，全在基类里


//==========================================================================
// 第 5 部分：sequence  ★新增
//==========================================================================
// 【填空2】sequence 派生自哪个类？注意要带参数
class my_sequence extends ________;

  my_transaction m_trans;

  // 【填空3】注册宏。sequence 是 component 还是 object？
  ________(my_sequence)

  // 【填空4】构造函数，注意参数个数
  function new(string name = "my_sequence");
    super.new(________);
  endfunction

  // 【填空5】body 要加 virtual 吗？（想想框架怎么调它）
  ________ task body();

    // 【填空6】顶层 sequence 要控制 objection
    //   提示：用 starting_phase，记得判断 != null
    if (________ != null)
      ________.raise_objection(this);

    // 【填空7】发 5 个随机包
    //   提示：用 `uvm_do 宏
    repeat (5) begin
      ________
    end

    #100;                              // drain time

    // 【填空8】放下 objection
    if (________ != null)
      ________.drop_objection(this);

  endtask
endclass


//==========================================================================
// 第 6 部分：driver  ★改造
//==========================================================================
// 【填空9】driver 派生时要带参数了（因为要用基类的 req）
class my_driver extends ________;

  virtual my_if vif;

  `uvm_component_utils(my_driver)

  function new(string name = "my_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif))
      `uvm_fatal("my_driver", "virtual interface must be set for vif!!!")
  endfunction

  extern virtual task main_phase(uvm_phase phase);
  extern task drive_one_pkt(my_transaction tr);
endclass


task my_driver::main_phase(uvm_phase phase);
  // 【填空10】driver 现在还要 raise_objection 吗？为什么？
  //   （想想：下面是无限循环）

  vif.data  <= 8'b0;
  vif.valid <= 1'b0;
  while (!vif.rst_n)
    @(posedge vif.clk);

  // 【填空11】改成无限循环，向 sequencer 索取 transaction
  //   三个固定动作：
  //     ① seq_item_port.get_next_item(req)   —— 要一个（阻塞）
  //     ② drive_one_pkt(req)                  —— 驱动
  //     ③ seq_item_port.item_done()           —— 回执
  //   注意：req 是基类自带的成员，不用声明
  while (1) begin



  end
endtask


task my_driver::drive_one_pkt(my_transaction tr);
  tr.my_print("Driver  send");
  foreach (tr.pload[i]) begin
    @(posedge vif.clk);
    vif.valid <= 1'b1;
    vif.data  <= tr.pload[i];
  end
  @(posedge vif.clk);
  vif.valid <= 1'b0;
  @(posedge vif.clk);
endtask


//==========================================================================
// 第 7 部分：monitor（不变）
//==========================================================================
class my_monitor extends uvm_monitor;

  virtual my_if vif;
  uvm_analysis_port #(my_transaction) ap;

  `uvm_component_utils(my_monitor)

  function new(string name = "my_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif))
      `uvm_fatal("my_monitor", "virtual interface must be set for vif!!!")
    ap = new("ap", this);
  endfunction

  extern task main_phase(uvm_phase phase);
  extern task collect_one_pkt(my_transaction tr);
endclass


task my_monitor::main_phase(uvm_phase phase);
  my_transaction tr;
  while (1) begin
    tr = new("tr");
    collect_one_pkt(tr);
    ap.write(tr);
  end
endtask


task my_monitor::collect_one_pkt(my_transaction tr);
  byte unsigned data_q[$];

  while (1) begin
    @(posedge vif.clk);
    if (vif.valid) break;
  end

  while (vif.valid) begin
    data_q.push_back(vif.data);
    @(posedge vif.clk);
  end

  tr.pload = new[data_q.size()];
  foreach (tr.pload[i]) tr.pload[i] = data_q[i];
endtask


//==========================================================================
// 第 8 部分：agent  ★新增
//==========================================================================
// 【填空12】agent 派生自哪个类？
class my_agent extends ________;

  my_sequencer sqr;
  my_driver    drv;
  my_monitor   mon;

  // agent 内部的 ap，用来把 monitor 的 ap 转发出去
  uvm_analysis_port #(my_transaction) ap;

  `uvm_component_utils(my_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 【填空13】只有 ACTIVE 模式才创建 sequencer 和 driver
    //   提示：is_active 是 uvm_agent 自带的成员
    if (________ == UVM_ACTIVE) begin
      sqr = ________;
      drv = ________;
    end

    // 【填空14】monitor 两种模式都要创建（写在 if 外面）
    mon = ________;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // 【填空15】ACTIVE 时把 driver 和 sequencer 连起来
    //   提示：drv.seq_item_port 连 sqr.seq_item_export
    //         这两个名字都是基类自带的
    if (is_active == UVM_ACTIVE)
      ________;

    // 【填空16】把 monitor 的 ap 转发给 agent 自己的 ap
    //   提示：直接赋值即可（不是 connect）
    ________;
  endfunction
endclass


//==========================================================================
// 第 9 部分：scoreboard（不变）
//==========================================================================
class my_scoreboard extends uvm_scoreboard;

  my_transaction expect_queue[$];
  uvm_blocking_get_port #(my_transaction) exp_port;
  uvm_blocking_get_port #(my_transaction) act_port;

  `uvm_component_utils(my_scoreboard)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    exp_port = new("exp_port", this);
    act_port = new("act_port", this);
  endfunction

  extern virtual task main_phase(uvm_phase phase);
endclass


task my_scoreboard::main_phase(uvm_phase phase);
  my_transaction get_expect, get_actual, tmp_tran;
  bit result;

  fork
    while (1) begin
      exp_port.get(get_expect);
      expect_queue.push_back(get_expect);
    end

    while (1) begin
      act_port.get(get_actual);
      if (expect_queue.size() > 0) begin
        tmp_tran = expect_queue.pop_front();
        result = tmp_tran.my_compare(get_actual);
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
// 第 10 部分：env  ★改造
//==========================================================================
class my_env extends uvm_env;

  // 【填空17】把原来的 drv/i_mon/o_mon 换成两个 agent
  ________  i_agt;
  ________  o_agt;
  my_scoreboard scb;

  uvm_tlm_analysis_fifo #(my_transaction) i_agt_scb_fifo;
  uvm_tlm_analysis_fifo #(my_transaction) o_agt_scb_fifo;

  `uvm_component_utils(my_env)

  function new(string name = "my_env", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 【填空18】创建两个 agent 和 scoreboard
    i_agt = ________;
    o_agt = ________;
    scb   = ________;

    // 【填空19】设置两个 agent 的模式
    //   i_agt 要驱动信号 → ?
    //   o_agt 只观察     → ?
    i_agt.is_active = ________;
    o_agt.is_active = ________;

    i_agt_scb_fifo = new("i_agt_scb_fifo", this);
    o_agt_scb_fifo = new("o_agt_scb_fifo", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // 【填空20】连接（注意现在连的是 agent 的 ap，不是 monitor 的）
    //   i_agt.ap     → i_agt_scb_fifo.analysis_export
    //   scb.exp_port → i_agt_scb_fifo.blocking_get_export
    //   o_agt.ap     → o_agt_scb_fifo.analysis_export
    //   scb.act_port → o_agt_scb_fifo.blocking_get_export




  endfunction
endclass


//==========================================================================
// 第 11 部分：base_test  ★新增
//==========================================================================
// 【填空21】test 派生自哪个类？
class base_test extends ________;

  my_env env;

  `uvm_component_utils(base_test)

  function new(string name = "base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【填空22】创建 env
    env = ________;
  endfunction

  // report_phase：统计错误数，打印最终结论
  function void report_phase(uvm_phase phase);
    uvm_report_server server;
    int err_num;
    super.report_phase(phase);

    server  = get_report_server();
    err_num = server.get_severity_count(UVM_ERROR);

    if (err_num != 0)
      $display("TEST CASE FAILED");
    else
      $display("TEST CASE PASSED");
  endfunction
endclass


//==========================================================================
// 第 12 部分：具体测试用例  ★新增
//==========================================================================
// 【填空23】my_case0 派生自哪个类？（不是 uvm_test！）
class my_case0 extends ________;

  `uvm_component_utils(my_case0)

  function new(string name = "my_case0", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);            // ★ 先让 base_test 创建 env

    // 【填空24】指定这个用例用哪个 sequence
    //   uvm_config_db#(uvm_object_wrapper)::set(
    //       this,
    //       "路径.phase名",          ← 哪个 sequencer 的哪个 phase
    //       "固定字段名",            ← 想想是什么
    //       sequence类::type_id::get());
    //
    //   路径提示：从 base_test 看，sequencer 在 env.i_agt.sqr
    uvm_config_db#(uvm_object_wrapper)::set(
        ________,
        "________",
        "________",
        ________);
  endfunction
endclass


//==========================================================================
// 第 13 部分：top_tb  ★改造
//==========================================================================
module top_tb;

  reg clk;
  reg rst_n;

  my_if input_if (clk, rst_n);
  my_if output_if(clk, rst_n);

  dut my_dut(.clk   (clk),
             .rst_n (rst_n),
             .rxd   (input_if.data),
             .rx_dv (input_if.valid),
             .txd   (output_if.data),
             .tx_en (output_if.valid));

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    #50;
    rst_n = 1'b1;
  end

  initial begin
    // 【填空25】config_db 路径变深了，注意补全
    //   drv 在：uvm_test_top.env.i_agt.drv
    //   i_agt 的 mon 在：uvm_test_top.env.i_agt.mon
    //   o_agt 的 mon 在：uvm_test_top.env.o_agt.mon
    uvm_config_db#(virtual my_if)::set(null, "________", "vif", input_if);
    uvm_config_db#(virtual my_if)::set(null, "________", "vif", input_if);
    uvm_config_db#(virtual my_if)::set(null, "________", "vif", output_if);

    // 【填空26】run_test 现在应该怎么写？
    //   提示：用命令行 +UVM_TESTNAME 选用例
    run_test(________);
  end

endmodule
