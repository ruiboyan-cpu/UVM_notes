# 08 代码的可重用性（callback 机制）

> 对应《UVM实战》Ch9。

## 1. 广义的 callback：你早就在用

```systemverilog
function void my_transaction::post_randomize();
  crc = calc_crc();          // randomize 后自动算 CRC
endfunction
```

**`post_randomize` 就是最简单的 callback。**

**逻辑**：SV 的设计者（开发者）预料到用户可能想在 `randomize()` 后做点什么，于是提供接口；你（使用者）重写它。

**没有它的话**，每次 randomize 后都要手动调 `calc_crc()`——忘一次就是隐蔽的 bug。

UVM 也提供了一批广义 callback：`pre_body`/`post_body`、`pre_do`/`mid_do`/`post_do`。

### callback 的本质

> **程序的开发者不需要 callback，它完全是由程序的使用者要求的。**

关键在于**开发者能否准确预判使用者的需求**。

## 2. 为什么需要 callback

### 场景一：VIP 的可扩展性

你开发了一个 VIP 给别人用。driver 发送 transaction 前，**不同用户需求不同**：

| 用户 | 想做什么 |
|---|---|
| A | 把最后 4 字节设成包序号（方便定位） |
| B | 发包前先发几个特殊字节 |
| C | 把包截断一部分 |

**你不可能全实现在 driver 里**，但可以留一个接口：

```systemverilog
task my_driver::main_phase(uvm_phase phase);
  while (1) begin
    seq_item_port.get_next_item(req);
    pre_tran(req);                          // ★ 留个钩子
    drive_one_pkt(req);
    seq_item_port.item_done();
  end
endtask
```

### 场景二：构造异常测试用例

不用 callback 时异常处理会污染 driver：

```systemverilog
if (test_mode == CRC_ERR) ...
else if (test_mode == SFD_ERR) ...          // 一堆分支
else 正常驱动;
```

> 在没有 factory 重载之前，**用 callback 构建异常测试用例是最好的实现方式**。

### 核心问题：为什么不能直接派生 driver

```systemverilog
class new_driver extends my_driver;
  virtual task pre_tran(my_transaction tr); ... endtask
endclass
```

**行不通**：

> 虽然派生了 new_driver，但 **VIP 中正常运行时使用的依然是 my_driver**。**new_driver 从来没有被实例化过**，所以 `pre_tran` 从来不会运行。

（当然可以用 factory 重载——但那是 factory 的功能。）

## 3. callback 机制的原理

### 思路一：把钩子搬出 driver

单独定义一个类 A，用户**派生 A**（代价远小于派生 driver）：

```systemverilog
class A;
  virtual task pre_tran(my_transaction tr); endtask
endclass
```

**但 driver 怎么知道用户派生了 A、实例化了它？**

### 思路二：加一个"池子"

```systemverilog
task my_driver::main_phase(uvm_phase phase);
  while (1) begin
    seq_item_port.get_next_item(req);
    foreach (A_pool[i]) begin
      A_pool[i].pre_tran(req);            // ★ 遍历池子，调用所有实例
    end
    drive_one_pkt(req);
    seq_item_port.item_done();
  end
endtask
```

**约定**：driver 执行池子里**所有实例**的 `pre_tran`。

用户只要：**派生 A → 实例化 → 加入 A_pool**。

### 三个要素

| 要素 | 作用 |
|---|---|
| **A 类**（callback 基类） | 定义有哪些钩子，全是 virtual 空方法 |
| **A_pool**（callback 池） | 存放用户派生的实例 |
| **driver 里的遍历** | 在合适位置调用池子里所有实例的钩子 |

**UVM 的实现原理完全一样**，只是用宏封装了。

## 4. callback 的用法

### 开发者：四步

```systemverilog
// ① 定义 callback 基类（callbacks.sv）
class A extends uvm_callback;                       // ★ 必须派生自 uvm_callback
  virtual task pre_tran(my_driver drv, ref my_transaction tr);
  //  ↑ 必须 virtual
  endtask
endclass

// ② 声明 callback 池（紧跟在 A 后面）
typedef uvm_callbacks #(my_driver, A) A_pool;
//                      └───┬───┘  └┬┘
//                   谁会用这个池子  装什么

// ③ 在 driver 里注册（my_driver.sv）
typedef class A;                                    // ★ 前向声明（互相引用）
class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)
  `uvm_register_cb(my_driver, A)                    // ★ 注册
endclass

// ④ 在需要的位置调用
task my_driver::main_phase(uvm_phase phase);
  while (1) begin
    seq_item_port.get_next_item(req);
    `uvm_do_callbacks(my_driver, A, pre_tran(this, req))    // ★
    drive_one_pkt(req);
    seq_item_port.item_done();
  end
endtask
```

`` `uvm_do_callbacks(调用者类, callback类, 方法名(参数)) ``

### 使用者：两步

```systemverilog
// ① 派生 callback 类，实现钩子
class my_callback extends A;
  `uvm_object_utils(my_callback)                    // ★ object 版
  virtual task pre_tran(my_driver drv, ref my_transaction tr);
    // 你想做的事
  endtask
endclass

// ② 实例化并加入池子
function void my_case0::connect_phase(uvm_phase phase);
  my_callback my_cb;
  super.connect_phase(phase);
  my_cb = my_callback::type_id::create("my_cb");
  A_pool::add(env.i_agt.drv, my_cb);                // ★ 指定给哪个 driver 用
endfunction
```

⚠️ **时机**：必须在**使用这个 callback 的 phase 之前**（`connect_phase` 是常见选择）。

⚠️ `add` 的第一个参数指定 driver 实例——可能有多个 my_driver。

### 文件组织

```
callbacks.sv     ← A 类 + A_pool 的 typedef（A 定义在前）
my_driver.sv     ← 开头写 typedef class A; 前向声明
my_case0.sv      ← 必须在 callbacks.sv 之后（要用 A_pool::add）
```

## 5. 子类继承父类的 callback

**场景**：第二代产品派生了 `new_driver`，希望第一代的测试用例不改就能跑。

**问题**：`A_pool` 声明时写死了 `my_driver`。

**解法**：

```systemverilog
class new_driver extends my_driver;
  `uvm_component_utils(new_driver)
  `uvm_set_super_type(new_driver, my_driver)        // ★ 关联子类和父类
endclass

task new_driver::main_phase(uvm_phase phase);
  ...
  `uvm_do_callbacks(my_driver, A, pre_tran(this, req))    // ★ 第一个参数写【父类】
  ...
endtask
```

**原来的测试用例一个字不用改。**

## 6. 三种机制的对比

### callback 也能完全取代 sequence

把 driver 的全部逻辑搬进 callback：

```systemverilog
class A extends uvm_callback;
  virtual function bit gen_tran(); endfunction      // 留给用户重写

  virtual task run(my_driver drv, uvm_phase phase);
    phase.raise_objection(drv);                     // objection 也在这里
    while (gen_tran()) drv.drive_one_pkt(tr);
    phase.drop_objection(drv);
  endtask
endclass

task my_driver::main_phase(uvm_phase phase);
  `uvm_do_callbacks(my_driver, A, run(this, phase))   // driver 只剩一行
endtask
```

**完全没有 sequence、没有 sequencer。**

### 但都不推荐（四条理由）

| 理由 | 说明 |
|---|---|
| **职能倒退** | 引入 sequence 就是为了剥离激励，绕回去等于退步 |
| **各有所长** | 有些用例 driver 方便，有些 sequence 方便 |
| **无法复用** | sequence 能嵌套复用；driver/callback 只能把函数堆在基类里，**代码量恐怖** |
| **无法协调** | virtual sequence 能同步多接口，多 driver 之间很难 |

> **三者并不是互斥的**。当三者互相结合时，又会产生许多新的解决问题的方式。

### 怎么选

```
sequence  = 改变【发什么】
factory   = 换掉【谁来做】
callback  = 在【预留的位置】插入
```

| 场景 | 推荐 |
|---|---|
| 数据内容的变化 | **sequence** |
| 驱动时序的变化 | **factory 重载 driver** |
| VIP 留给外部用户扩展 | **callback** |
| 替换整个组件行为 | factory |
| 在固定位置插入小段逻辑 | callback |

### factory vs callback 的本质区别

| | **factory 重载** | **callback** |
|---|---|---|
| 做法 | **换掉整个类** | **在特定位置插入代码** |
| 能改的范围 | 任意 | **只有开发者预留的钩子** |
| 性质 | **事后补救**（开发者没预料到也没关系） | **事先预留**（只能在想到的地方插入） |

## 7. 小而美：可重用性的前提

### Linux 的启发

```bash
ls | grep "aaa" | wc          # 三个小工具组合
```

如果做成一个 `lsgrepwc` 大命令，**参数列表会长到吓人**。

**小而美 = 功能模块化、标准化。**

### 对 factory 重载的直接影响

**写法一：拆成子任务** ✓

```systemverilog
task A_driver::drive_one_pkt;
  drive_preamble();
  drive_sfd();
  drive_data();
endtask
```

构造 SFD 错误 → 派生 `B_driver`，**只重载 `drive_sfd()`**。

**写法二：一个大任务** ✗

```systemverilog
task A_driver::drive_one_pkt;
  // drive preamble ...
  // drive sfd ...
  // drive data ...
endtask
```

想改 SFD → 必须重载整个任务，**preamble 和 data 的代码要复制过去**。

**复制的代价**：容易出错；原代码改了复制的不会跟着改 → **两份代码不一致**。

### 但也不能无限拆

把 `ls`、`ls -a`、`ls -l` 做成三个命令也不合理——**共同参数大量冗余**。

**小而美的前提是功能划分合理。**

### 放弃"强大 sequence"的想法

**别写一个能处理所有情况的万能 sequence**（一堆 if/else 和配置开关），**而应该写一批小 sequence，靠嵌套组合**。

## 8. 模块级到芯片级的重用

### 基于 env 的重用

```systemverilog
// 模块级的验证环境
class moduleA_env extends uvm_env; ... endclass

// 芯片级直接复用
class chip_env extends uvm_env;
  moduleA_env env_a;                    // ★ 原封不动搬过来
  moduleB_env env_b;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env_a = moduleA_env::type_id::create("env_a", this);
    env_b = moduleB_env::type_id::create("env_b", this);
  endfunction
endclass
```

**要改的通常只有一处**：

| | 模块级 | 芯片级 |
|---|---|---|
| agent 模式 | `UVM_ACTIVE`（要驱动） | **`UVM_PASSIVE`**（上游模块接管驱动） |

**这就是为什么 monitor 要写在 `is_active` 判断之外**——切换模式时 monitor 保留，driver 和 sequencer 自动消失。

### virtual sequence 的重用

模块级各自的 sequence 保持不变，**芯片级写一个新的 virtual sequence** 来协调它们。
