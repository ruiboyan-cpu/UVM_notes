# 02 搭建完整验证平台

> 对应《UVM实战》Ch2。从只有 driver 开始，一步步加组件。

## 0. 本章 DUT

```systemverilog
module dut(clk, rst_n, rxd, rx_dv, txd, tx_en);
  always @(posedge clk) begin
    if (!rst_n) begin txd <= 0; tx_en <= 0; end
    else        begin txd <= rxd; tx_en <= rx_dv; end   // 收什么发什么，延迟一拍
  end
endmodule
```

## 1. 第一条原则

> **验证平台中所有的组件都应该派生自 UVM 中的类。**

要实现某个功能，第一反应是"**从 UVM 的某个类派生，在新类里实现**"。

## 2. 最简单的 driver

```systemverilog
class my_driver extends uvm_driver;
  `uvm_component_utils(my_driver)                        // 注册到 factory

  function new(string name = "my_driver", uvm_component parent = null);
    super.new(name, parent);                             // 必须两个参数
  endfunction

  extern virtual task main_phase(uvm_phase phase);       // extern：类外实现
endclass

task my_driver::main_phase(uvm_phase phase);
  phase.raise_objection(this);
  ...驱动逻辑...
  phase.drop_objection(this);
endtask
```

### 四个要点

| 要素 | 说明 |
|---|---|
| **`new(name, parent)`** | 所有 uvm_component 的构造函数**必须**这两个参数 |
| **`main_phase`** | 基类预定义的 task，你重写它——"实现 driver ≈ 实现 main_phase" |
| **`virtual`** | 让框架用基类句柄调到**你的**实现（忘加 = 代码不执行且不报错） |
| **`extern`** | 类内声明、类外实现，保持类定义简洁 |

### `uvm_info` 宏

```systemverilog
`uvm_info("my_driver", "data is drived", UVM_LOW)
//          └─ID─┘      └──消息──┘       └冗余度┘
```

- **ID**：给信息分类，方便日志过滤（`grep`）
- **冗余度**：`UVM_NONE(0) < UVM_LOW(100) < UVM_MEDIUM(200) < UVM_HIGH(300) < UVM_FULL < UVM_DEBUG`
- **默认阈值 `UVM_MEDIUM`**——级别 ≤ 阈值才打印
- 宏**结尾不加分号**

同族：`` `uvm_warning `` / `` `uvm_error `` / `` `uvm_fatal ``（不受冗余度控制，总是打印）

## 3. factory 机制

### 三个关键动作

```systemverilog
// ① 注册
`uvm_component_utils(my_driver)       // component 版
`uvm_object_utils(my_transaction)     // object 版

// ② 创建
drv = my_driver::type_id::create("drv", this);

// ③ 启动
run_test("my_case0");                  // 或 run_test() + 命令行 +UVM_TESTNAME
```

### `new()` vs `type_id::create()`

| | 含义 |
|---|---|
| `new("drv", this)` | "造一个 my_driver"——**编译时焊死** |
| `type_id::create("drv", this)` | "**去工厂问一下现在该造哪个**"——运行时决定 |

**UVM 里创建组件一律用 `type_id::create`**，用 `new` 会绕过工厂、重载失效。

### `run_test` 做三件事

1. 从 factory 按字符串创建对象
2. 作为 **UVM 树的根**（实例名固定 `uvm_test_top`）
3. **启动 phase 机制**

⚠️ `run_test` 只创建**根节点一个**，其他组件靠各层 `build_phase` 里的 `type_id::create` 层层展开。

### 重载（override）

```systemverilog
class error_driver extends my_driver;    // ★ 必须是派生类
  `uvm_component_utils(error_driver)
endclass

// 在测试用例里一行，环境代码一个字不改
set_type_override_by_type(my_driver::get_type(), error_driver::get_type());
```

**是替换，不是添加**——之后所有 `my_driver::type_id::create` 都创建 `error_driver`。

**必须在 create 之前设置。**

## 4. objection 机制

```systemverilog
phase.raise_objection(this);     // 举手："我还有事没干完"
   ...
phase.drop_objection(this);      // 放下："我干完了"
```

**内部是计数器**：raise +1、drop -1、**归零则该 phase 结束**。

不写的话 UVM 认为无事可做，**在时刻 0 立刻结束仿真**，代码一行都跑不到。

### 在哪控制

| 位置 | 可行吗 |
|---|---|
| **sequence 里** | ✅ **最佳**（UVM 提倡） |
| test 的 main_phase | ✅（手动 start 时） |
| **driver / monitor** | ❌ 无限循环，drop 执行不到 |

### drain time

```systemverilog
repeat (5) `uvm_do(m_trans)
#100;                            // ★ 等 DUT 处理完最后的数据
phase.drop_objection(this);
```

不留的话，最后一个包的 DUT 输出会**收不到**。

## 5. virtual interface + config_db

### 为什么不用构造函数传参

factory 要求**所有组件构造函数签名统一**为 `(name, parent)`——塞不进 vif。

**config_db 把"配置传递"和"对象创建"解耦**，还支持跨层次直接投递。

### 用法

```systemverilog
// top_tb 里【set】—— 给东西的人
uvm_config_db#(virtual my_if)::set(null, "uvm_test_top.env.i_agt.drv", "vif", input_if);
//                                  └┬┘   └───────────┬────────────┘  └─┬─┘  └───┬──┘
//                            起点(null=uvm_top)    收件地址          名字     值

// 组件里【get】—— 要东西的人
function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif))
    `uvm_fatal("my_driver", "virtual interface must be set for vif!!!")
endfunction
```

| 规则 | 说明 |
|---|---|
| set 的**类型+路径+名字**必须和 get 完全一致 | 查表的主键 |
| get **必须检查返回值** | 取不到就 fatal，否则 vif 是 null、一用就崩 |
| `null` 自动替换成 `uvm_top` | module 里没有 `this`，用 null 写绝对路径 |
| component 里用 `this` | 写相对路径 |

**三个名字的关系**：

```systemverilog
interface my_if(...);            // 类型名
my_if input_if(clk, rst_n);      // 实例名（top_tb 里）
virtual my_if vif;               // 句柄（driver 里，指向那个实例）
```

## 6. transaction

```systemverilog
class my_transaction extends uvm_sequence_item;    // ★ 不是 uvm_transaction
  rand bit [47:0] dmac, smac;
  rand byte       pload[];
  constraint pload_cons { pload.size inside {[46:1500]}; }

  `uvm_object_utils(my_transaction)                 // ★ object 版
  function new(string name = "my_transaction");     // ★ 只有一个参数
    super.new(name);
  endfunction
endclass
```

### component vs object（最根本的分类）

| | `uvm_component` | `uvm_object` |
|---|---|---|
| 代表 | **组件**（driver、env） | **数据**（transaction、sequence） |
| 生命周期 | 整个仿真 | **用完即弃** |
| 在 UVM 树上 | ✅ | ❌ |
| 构造函数 | `new(name, parent)` | `new(name)` |
| 注册宏 | `` `uvm_component_utils `` | `` `uvm_object_utils `` |
| 有 phase | ✅ | ❌ |

**比喻**：component 是工厂里的机器（一直在），object 是流水线上的产品（造出来、用掉、扔掉）。

⚠️ **transaction 要从 `uvm_sequence_item` 派生**，不是 `uvm_transaction`——前者多了与 sequence 机制配合的成员。

## 7. env

```systemverilog
class my_env extends uvm_env;
  my_agent  i_agt, o_agt;
  my_scoreboard scb;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);                      // ★ 必须调
    i_agt = my_agent::type_id::create("i_agt", this);
    ...
  endfunction
endclass
```

### 两条规则

| 规则 | 原因 |
|---|---|
| **子组件必须在 `build_phase` 创建** | `new()` 里创建时 factory override 还没设置 |
| **必须调 `super.build_phase(phase)`** | 它负责 field automation 的自动配置 |

**env 是可复用的最小单位**——模块级环境能整体搬到芯片级。

## 8. monitor

```systemverilog
class my_monitor extends uvm_monitor;
  virtual my_if vif;
  uvm_analysis_port #(my_transaction) ap;      // ★ 广播端口

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif))
      `uvm_fatal("my_monitor", "vif not set")
    ap = new("ap", this);                      // ★ 端口用 new，不是 create
  endfunction

  task main_phase(uvm_phase phase);
    while (1) begin                            // ★ 无限循环
      tr = new("tr");
      collect_one_pkt(tr);
      ap.write(tr);                            // ★ 非阻塞广播
    end
  endtask
endclass
```

**三个要点**：
- **无限循环**（DUT 什么时候输出不由它决定）→ **不能控制 objection**
- **只读不驱动**（一驱动就和 driver 打架）
- **同一个类**配不同 vif 就能用在输入侧和输出侧

## 9. agent

```systemverilog
class my_agent extends uvm_agent;
  my_sequencer sqr;
  my_driver    drv;
  my_monitor   mon;
  uvm_analysis_port #(my_transaction) ap;      // agent 自己的 ap

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (is_active == UVM_ACTIVE) begin         // ★ is_active 是基类自带的
      sqr = my_sequencer::type_id::create("sqr", this);
      drv = my_driver::type_id::create("drv", this);
    end
    mon = my_monitor::type_id::create("mon", this);   // ★ 写在 if 【外面】
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (is_active == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
    ap = mon.ap;                               // ★ 转发（赋值，不是 connect）
  endfunction
endclass
```

**monitor 写在 if 外面**，使同一个 agent 类能用于 ACTIVE 和 PASSIVE 两种场合——这也是**模块级到芯片级重用**的基础。

## 10. TLM 通信与 reference model

### analysis port：一对多广播

```systemverilog
mon.ap.write(tr);              // 非阻塞，发出去就不管
mon.ap.connect(fifo1.analysis_export);     // 可 connect 多次 = 广播
mon.ap.connect(fifo2.analysis_export);
```

### FIFO 衔接

`analysis_port`（非阻塞广播）和 `get_port`（阻塞取）不能直连，中间加 FIFO：

```systemverilog
uvm_tlm_analysis_fifo #(my_transaction) agt_scb_fifo;
agt_scb_fifo = new("agt_scb_fifo", this);          // ★ FIFO 用 new

// connect_phase 里
i_agt.ap.connect(agt_scb_fifo.analysis_export);           // monitor → FIFO
scb.exp_port.connect(agt_scb_fifo.blocking_get_export);   // FIFO → scoreboard
```

**连接规则：永远 `port.connect(export)`——谁有 port 谁打头**，与数据流向无关。

### connect_phase

| phase | 做什么 | 执行顺序 |
|---|---|---|
| `build_phase` | **创建**组件 | **自顶向下**（父先建子才存在） |
| `connect_phase` | **连接**端口 | **自底向上**（内层先连外层才能用） |

## 11. scoreboard

```systemverilog
class my_scoreboard extends uvm_scoreboard;
  my_transaction expect_queue[$];                        // ★ 期望值队列
  uvm_blocking_get_port #(my_transaction) exp_port, act_port;

  task main_phase(uvm_phase phase);
    fork                                                 // ★ 两个进程并行
      while (1) begin                                    // 收期望值
        exp_port.get(get_expect);
        expect_queue.push_back(get_expect);
      end
      while (1) begin                                    // 收实际值并比对
        act_port.get(get_actual);
        if (expect_queue.size() > 0) begin
          tmp_tran = expect_queue.pop_front();           // FIFO 配对
          result = tmp_tran.compare(get_actual);
          ...
        end
        else `uvm_error("scb", "Expect Queue is empty")  // DUT 多发了
      end
    join
  endtask
endclass
```

**为什么要队列**：DUT 有延时，**期望值总是先到**，要缓存起来等实际值。

## 12. field automation

```systemverilog
class my_transaction extends uvm_sequence_item;
  rand bit [47:0] dmac;                            // ① 给编译器（创建变量）
  rand byte       pload[];

  `uvm_object_utils_begin(my_transaction)
    `uvm_field_int(dmac, UVM_ALL_ON)               // ② 给 UVM（登记清单）
    `uvm_field_array_int(pload, UVM_ALL_ON)
  `uvm_object_utils_end
endclass
```

**为什么要登记两次**：SV **没有反射（reflection）**，UVM 无法自己发现类有哪些成员。

### 自动获得的方法

```systemverilog
b.copy(a);              a.compare(b);          a.print();
a.pack_bytes(q);        a.unpack_bytes(q);     a.clone();
```

**driver 和 monitor 因此大幅简化**：

```systemverilog
data_size = tr.pack_bytes(data_q) / 8;     // 打包（返回位数，除8得字节数）
tr.unpack_bytes(data_q);                   // 还原
```

⚠️ **打包顺序 = 宏的登记顺序**（不是变量声明顺序），**必须和协议的字段顺序一致**。

### 宏的种类

| 变量类型 | 宏 |
|---|---|
| 整数 / 实数 / 字符串 / 对象 | `uvm_field_int` / `_real` / `_string` / `_object` |
| **枚举** | `uvm_field_enum(类型, 变量, FLAG)` ★ **三个参数** |
| **动态数组** | `uvm_field_array_int` |
| **静态数组** | `uvm_field_sarray_int` |
| **队列** | `uvm_field_queue_int` |
| **关联数组** | `uvm_field_aa_int_string`（存int、索引string） |

### 控制域 FLAG

```systemverilog
`uvm_field_int(crc_err, UVM_ALL_ON | UVM_NOPACK)
```

| 标志 | 关闭什么 |
|---|---|
| `UVM_NOPACK` | 不参与 pack/unpack |
| `UVM_NOCOMPARE` / `UVM_NOPRINT` / `UVM_NOCOPY` | 同理 |

**判断标准：这个字段会出现在 DUT 端口上吗？**
- 纯控制标志（`crc_err`、`is_vlan`）→ **必须 NOPACK**
- 真实协议字段 → 正常打包

### 对 component 的价值：省掉 get

```systemverilog
class my_driver extends uvm_driver;
  int pre_num;
  `uvm_component_utils_begin(my_driver)
    `uvm_field_int(pre_num, UVM_ALL_ON)
  `uvm_component_utils_end

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);     // ★ 自动从 config_db 取 pre_num
  endfunction
endclass
```

**三个名字必须一致**：变量名 = 宏里的名字 = config_db 的 field_name。

### 缺点

仿真慢、不够灵活、调试难。**大项目常改为手写 `do_compare`/`do_copy`/`do_print`**。

## 13. sequence 机制

见 [06-sequence.md](06-sequence.md)，这里只列基本形态：

```systemverilog
// sequencer：一行逻辑都不用写
class my_sequencer extends uvm_sequencer #(my_transaction);
  `uvm_component_utils(my_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

// sequence
class my_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(my_sequence)                   // ★ object 版
  function new(string name = "my_sequence");
    super.new(name);
  endfunction

  virtual task body();
    uvm_phase phase = get_starting_phase();        // UVM 1.2
    if (phase != null) phase.raise_objection(this);
    repeat (5) `uvm_do(m_trans)
    #100;
    if (phase != null) phase.drop_objection(this);
  endtask
endclass

// driver：只剩三个固定动作
task my_driver::main_phase(uvm_phase phase);
  while (1) begin
    seq_item_port.get_next_item(req);    // ① 要（阻塞）
    drive_one_pkt(req);                  // ② 驱动
    seq_item_port.item_done();           // ③ 回执 —— 忘写会卡死在第一个包
  end
endtask
```

⚠️ **driver 派生时要带参数** `uvm_driver #(my_transaction)`，才能用基类的 `req`。

### 启动

```systemverilog
uvm_config_db#(uvm_object_wrapper)::set(this,
    "env.i_agt.sqr.main_phase",      // 路径末尾指明 phase
    "default_sequence",              // ★ 固定字符串
    my_sequence::type_id::get());
```

## 14. base_test 与测试用例

```systemverilog
class base_test extends uvm_test;
  my_env env;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = my_env::type_id::create("env", this);
  endfunction

  function void report_phase(uvm_phase phase);      // ★ 最后统计
    uvm_report_server server;
    int err_num;
    super.report_phase(phase);
    server  = get_report_server();
    err_num = server.get_severity_count(UVM_ERROR);
    if (err_num != 0) $display("TEST CASE FAILED");
    else              $display("TEST CASE PASSED");
  endfunction
endclass

class my_case0 extends base_test;                   // ★ 派生自 base_test
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(uvm_object_wrapper)::set(this,
        "env.i_agt.sqr.main_phase", "default_sequence",
        my_sequence::type_id::get());               // ★ 只有这里各用例不同
  endfunction
endclass
```

### 各层职责

| 层 | 职责 | 改动频率 |
|---|---|---|
| top_tb | 例化接口、连 DUT、投递 vif、run_test | 几乎不改 |
| **test** | 配置：选 sequence、设 override | **每个用例一个** |
| env | 搭平台：创建组件、连端口 | 几乎不改 |
| agent/driver/monitor | 实现协议 | 几乎不改 |
| **sequence** | 产生激励 | **每种激励一个** |

**变的只有 test 和 sequence。**

### 命令行选用例

```systemverilog
run_test();                     // 括号留空
```

```bash
./simv +UVM_TESTNAME=my_case0
```

**一次编译跑多个用例**——回归测试的基础。
