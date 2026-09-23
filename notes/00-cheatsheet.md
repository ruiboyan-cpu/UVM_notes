# UVM 固定写法速查表

> 对应《UVM实战》第 2 章。凡是"必须这么写"的东西都在这里。

---

## 一、必须一字不差的字符串

写错了**不报错但功能静默失效**，是最难查的一类 bug。

| 字符串 | 用在哪 | 含义 |
|---|---|---|
| `"uvm_test_top"` | config_db 路径的开头 | `run_test` 创建的根节点的**固定实例名** |
| `"default_sequence"` | config_db 的 field_name | UVM 内部查找 sequence 用的**固定字段名** |
| `+UVM_TESTNAME=xxx` | 命令行 | 指定跑哪个测试用例 |
| `main_phase` / `build_phase` / `connect_phase` / `run_phase` / `report_phase` | phase 方法名、config_db 路径末尾 | phase 的**标准名字** |

**不是固定的**（你自己起、set/get 一致即可）：

| 字符串 | 说明 |
|---|---|
| `"vif"` | 只是习惯叫法，叫别的也行 |
| `"env"` / `"i_agt"` / `"drv"` / `"sqr"` | 组件名，create 时你传什么就是什么 |

⚠️ 路径 = 每一层 create 时传的 name 串起来：

```
uvm_test_top . env . i_agt . drv
     ↑          ↑      ↑      ↑
  run_test  base_test env里  agent里
   固定      create   create create
```

---

## 二、各组件的固定模板

### 通用骨架（uvm_component 系）

```systemverilog
class my_xxx extends uvm_xxx;              // ① 派生自对应基类
  `uvm_component_utils(my_xxx)             // ② 注册（component 版）

  function new(string name, uvm_component parent);   // ③ 两个参数
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);              // ④ 必须先调 super
    // 创建子组件、get config_db
  endfunction
endclass
```

### 通用骨架（uvm_object 系）

```systemverilog
class my_xxx extends uvm_xxx;
  `uvm_object_utils(my_xxx)                // ★ object 版

  function new(string name = "my_xxx");    // ★ 只有一个参数
    super.new(name);
  endfunction
endclass
```

### 派生自哪个基类

| 你写的类 | 派生自 | 带参数？ |
|---|---|---|
| transaction | `uvm_sequence_item` | ❌ |
| sequence | `uvm_sequence #(my_transaction)` | ✅ |
| driver | `uvm_driver #(my_transaction)` | ✅ |
| sequencer | `uvm_sequencer #(my_transaction)` | ✅ |
| monitor | `uvm_monitor` | ❌ |
| agent | `uvm_agent` | ❌ |
| scoreboard | `uvm_scoreboard` | ❌ |
| reference model | `uvm_component` | ❌ |
| env | `uvm_env` | ❌ |
| test | `uvm_test` | ❌ |

**带参数的三个（driver / sequencer / sequence）必须写同一个 transaction 类型**，否则连不上。

---

## 三、库自带的名字（你不用声明，直接用）

### 成员变量

| 名字 | 来自 | 是什么 |
|---|---|---|
| `req` | `uvm_driver` | 装取回的 transaction，类型 = 参数 REQ |
| `seq_item_port` | `uvm_driver` | 向 sequencer 索取的端口 |
| `seq_item_export` | `uvm_sequencer` | 供 driver 取的口 |
| `is_active` | `uvm_agent` | `UVM_ACTIVE` / `UVM_PASSIVE` |
| `starting_phase` | `uvm_sequence_base` | 启动本 sequence 的 phase（1.2 后改用 `get_starting_phase()`） |

### 方法

| 方法 | 谁的 | 作用 |
|---|---|---|
| `get_next_item(req)` / `item_done()` | `seq_item_port` | driver 取货 / 报完成 |
| `start_item()` / `finish_item()` | sequence | `` `uvm_do `` 内部用 |
| `write(tr)` | `uvm_analysis_port` | 非阻塞广播 |
| `get(tr)` | `uvm_blocking_get_port` | 阻塞取 |
| `connect(...)` | 所有 port | 连接端口 |
| `raise_objection(this)` / `drop_objection(this)` | `uvm_phase` | 控制仿真结束 |
| `type_id::create(name, parent)` | 注册宏生成 | 经 factory 创建 |
| `get_type()` | 注册宏生成 | 取类型句柄，用于 override |
| `body()` | `uvm_sequence` | 你重写它，写激励逻辑 |

### 端口 / FIFO 类型

| 类型 | 用途 | 自带的口 |
|---|---|---|
| `uvm_analysis_port #(T)` | 一对多广播发送 | — |
| `uvm_blocking_get_port #(T)` | 阻塞取 | — |
| `uvm_tlm_analysis_fifo #(T)` | 缓冲 | `analysis_export`（入口）<br>`blocking_get_export`（出口） |

### 宏

| 宏 | 作用 |
|---|---|
| `` `uvm_component_utils(T) `` | 注册组件 |
| `` `uvm_object_utils(T) `` | 注册数据类 |
| `` `uvm_info(ID, MSG, VERBOSITY) `` | 打印（结尾**不加分号**） |
| `` `uvm_warning/error/fatal(ID, MSG) `` | 分级报错 |
| `` `uvm_do(tr) `` | sequence 里：造 + 随机 + 发送 |
| `` `uvm_do_with(tr, {约束}) `` | 同上，带内联约束 |

### 全局

| 名字 | 作用 |
|---|---|
| `run_test("类名")` | 创建根节点 + 启动 phase 机制 |
| `run_test()` | 同上，用命令行 `+UVM_TESTNAME` 指定 |
| `uvm_config_db #(T)::set/get` | 全局配置表 |

---

## 四、几个必背的固定句式

### 1. config_db 传虚接口

```systemverilog
// top_tb 里 set
uvm_config_db#(virtual my_if)::set(null, "uvm_test_top.env.i_agt.drv", "vif", input_if);
//                                  └┬┘   └───────────┬────────────┘  └─┬─┘  └───┬──┘
//                             起点(null=根)        收件地址           名字     值

// 组件里 get
if (!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif))
  `uvm_fatal("my_driver", "virtual interface must be set for vif!!!")
//                                       └┬─┘ └┘
//                                   get 时固定写 (this, "")
```

**规则**：
- set 的三要素（**类型 + 路径 + 名字**）必须和 get 完全对上
- get **必须检查返回值**，取不到就 fatal

### 2. driver 的主循环

```systemverilog
task my_driver::main_phase(uvm_phase phase);
  while (1) begin
    seq_item_port.get_next_item(req);    // ① 要（阻塞）
    drive_one_pkt(req);                  // ② 驱动
    seq_item_port.item_done();           // ③ 回执 —— 忘写会卡死在第一个包
  end
endtask
```

⚠️ **用了 sequence 后 driver 不控制 objection**（无限循环，drop 执行不到）。

### 3. sequence 的 body

```systemverilog
virtual task body();
  if (starting_phase != null)
    starting_phase.raise_objection(this);

  repeat (5) `uvm_do(m_trans)
  #100;                                   // drain time，等 DUT 处理完

  if (starting_phase != null)
    starting_phase.drop_objection(this);
endtask
```

**要点**：
- **只有顶层 sequence** 控制 objection，嵌套的子 sequence 不碰
- `!= null` 判断必写——手动 `start()` 启动时它是 null

### 4. 指定测试用例的 sequence

```systemverilog
uvm_config_db#(uvm_object_wrapper)::set(this,
    "env.i_agt.sqr.main_phase",          // 路径末尾是 phase 名
    "default_sequence",                   // ★ 固定字符串
    my_sequence::type_id::get());
```

### 5. 端口连接（connect_phase）

```systemverilog
function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  drv.seq_item_port.connect(sqr.seq_item_export);
  mon.ap.connect(fifo.analysis_export);
  scb.exp_port.connect(fifo.blocking_get_export);
endfunction
```

**规则**：永远 **`port.connect(export)`** —— 谁有 port 谁打头，与数据流向无关。

### 6. base_test 的 report_phase

```systemverilog
function void report_phase(uvm_phase phase);
  uvm_report_server server;
  int err_num;
  super.report_phase(phase);
  server  = get_report_server();
  err_num = server.get_severity_count(UVM_ERROR);
  if (err_num != 0) $display("TEST CASE FAILED");
  else              $display("TEST CASE PASSED");
endfunction
```

---

## 五、phase 执行顺序

```
build_phase      ← 自顶向下，创建组件
connect_phase    ← 自底向上，连接端口
...
main_phase       ← 并行跑，耗时，受 objection 控制
...
report_phase     ← 最后，统计报告
```

**两条规则**：
- **function phase**（build/connect/report）**一律先调 `super.xxx_phase(phase)`**
- **task phase**（main/run）如果父类实现是无限循环，**不调 super**

---

## 六、最常见的低级错误

| 错误 | 症状 |
|---|---|
| 忘了 `item_done()` | **只发出一个包**就停住 |
| config_db 的 name 拼错 | get 返回 0 → vif 是 null → 运行时崩 |
| `"default_sequence"` 拼错 | **没有任何激励**，也不报错 |
| 用 `new()` 而非 `type_id::create()` | factory override 失效 |
| 忘加 `virtual` | 框架调到基类空实现，**你的代码没执行也不报错** |
| 在无限循环里 raise_objection | drop 执行不到，**仿真永不结束** |
| 组件用了 `uvm_object_utils` | 构造函数参数对不上，编译报错 |
| 忘调 `super.build_phase()` | field automation 等机制静默失效 |

---

## 七、component vs object 对照（最根本的分类）

| | `uvm_component` | `uvm_object` |
|---|---|---|
| 代表 | **组件**（driver、monitor、env、test） | **数据**（transaction、sequence） |
| 生命周期 | 整个仿真 | 用完即弃 |
| 在 UVM 树上 | ✅ | ❌ |
| 构造函数 | `new(name, parent)` | `new(name)` |
| 注册宏 | `` `uvm_component_utils `` | `` `uvm_object_utils `` |
| 创建方式 | `type_id::create(name, parent)` | `new(name)` 或 `type_id::create(name)` |
| 有 phase 吗 | ✅ | ❌ |

**比喻**：component 是工厂里的机器（一直在），object 是流水线上的产品（造出来、用掉、扔掉）。
