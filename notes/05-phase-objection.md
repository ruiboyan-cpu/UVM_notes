# 05 phase 机制与 objection

> 对应《UVM实战》Ch5。

## 1. phase 的完整列表

| 类型 | 特点 |
|---|---|
| **function phase** | **不耗仿真时间**，瞬间完成 |
| **task phase** | **耗仿真时间**，用 task 实现 |

```
① build                ─┐
② connect               │  function phase
③ end_of_elaboration    │  （不耗时）
④ start_of_simulation  ─┘
───────────────────────────────────
⑤ run_phase            ─┐
  ┌─ pre_reset          │
  ├─ reset              │
  ├─ post_reset         │
  ├─ pre_configure      │  task phase
  ├─ configure          │  （耗时）
  ├─ post_configure     │
  ├─ pre_main           │  ★ run_phase 和这 12 个
  ├─ main               │     是【并行】的
  ├─ post_main          │
  ├─ pre_shutdown       │
  ├─ shutdown           │
  └─ post_shutdown     ─┘
───────────────────────────────────
⑥ extract              ─┐
⑦ check                 │  function phase
⑧ report                │
⑨ final                ─┘
```

### run_phase 与那 12 个并行

```systemverilog
fork
  run_phase();                     // ★ 一条线
  begin
    pre_reset_phase();             // ★ 另一条线，12 个顺序执行
    reset_phase();
    ...
    post_shutdown_phase();
  end
join
```

**驱动代码只能写在其中一边**，两边都写会打架。

### 核心的四个

| phase | 干什么 |
|---|---|
| `reset_phase` | 复位、初始化 |
| `configure_phase` | 配置寄存器 |
| `main_phase` | **主要功能测试** |
| `shutdown_phase` | 断电相关 |

**细分的真正价值是 phase 跳转**（见下）。

### 实际常用的只有四个

```
build_phase → connect_phase → main_phase → report_phase
```

```bash
./simv +UVM_PHASE_TRACE      # 打印每个 phase 的开始/结束/跳过
```

## 2. phase 的执行顺序（空间维度）

### 规则一：build 自顶向下，其余 function phase 自底向上

```
build_phase：           其余 function phase：
   test                      test        ← 最后
    ↓                         ↑
   env                       env
    ↓                         ↑
  i_agt                     i_agt
    ↓                         ↑
   drv                       drv         ← 最先
```

| | 原因 |
|---|---|
| **build 自顶向下** | 子组件由父创建，**父没 build 子根本不存在** |
| **connect 自底向上** | 外层的连接可能依赖内层已连好（如 agent 把 `mon.ap` 转发给自己的 `ap`） |

### 规则二：兄弟组件按"名字的字典序"

**不是按实例化顺序！**

```systemverilog
create("dddd", this);  create("zzzz", this);  create("jjjj", this);  create("aaaa", this);
// 执行顺序：aaaa → dddd → jjjj → zzzz
```

依据是 **create 时传的名字**。

### 规则三：叔侄关系用深度优先

```
       env
      /    \
   i_agt   scb          执行：i_agt → drv → mon → sqr → scb
   /  |  \
 drv mon sqr
```

### 最重要的结论

> **不要写依赖这个顺序的代码。**
>
> 如果代码要求必须先执行 driver 的 build_phase 再执行 monitor 的，**应该立即修改代码**。

**理由**：这个顺序是从源码发现的，UVM 未承诺永远如此；改个组件名就可能改变顺序。

**正确做法**：有先后依赖就**放到不同 phase 里**（build 创建、connect 连接）。

### task phase：自下而上启动，同时运行

```systemverilog
fork
  drv.main_phase(phase);        // 全部 fork...join_none 启动
  mon.main_phase(phase);
  ...
join_none
```

### phase 之间的同步

**所有组件都完成某 phase，才进入下一个**：

```
A: [main 0~100] ......等...... [post_main 200~500]
B: [main 0~200            ] [post_main 200~400] ...等...
                          ↑
                  整个平台在这里同步
```

**从单个组件看有空白等待，从整个平台看没有。**

### 一个限制

**uvm_component 只能在 `build_phase` 实例化**，其他 phase 会报错。**uvm_object 不受限制**（transaction、sequence 可在任何 phase 创建）。

## 3. super.phase 做了什么

**除 build_phase 外，其他 phase 的基类实现基本是空的**：

```systemverilog
function void uvm_component::connect_phase(uvm_phase phase);
  connect();       // 空的（兼容 OVM 的遗留）
endfunction
```

### build_phase 做的唯一重要的事

**自动从 config_db 获取 field automation 登记的字段。**

```systemverilog
// uvm_agent 源码
function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (get_config_int("is_active", active))     // ★ 自动取 is_active
    is_active = uvm_active_passive_enum'(active);
endfunction
```

### 实践规则

| phase | 调 super 吗 |
|---|---|
| **`build_phase`** | ✅ **必须调** |
| 其他 function phase | 建议调（基类空的，调了无害） |
| **task phase**（main/run） | **通常不调**（基类空的，且可能阻塞） |

## 4. 两个保护机制

### build 阶段出 UVM_ERROR 立即停止

```
UVM_ERROR [my_driver] UVM_ERROR test
UVM_FATAL [BUILDERR] stopping due to build errors      ← UVM 自动加的
```

**规则**：`end_of_elaboration_phase` 及之前出现 UVM_ERROR，UVM **自动 fatal**。

**它的价值：一次暴露所有问题**

> 大型设计编译一个多小时。如果搭建阶段的错误用 `uvm_fatal`：
> 编译1小时 → fatal → 修 → 编译1小时 → 又一个 fatal → ...
>
> 用 `uvm_error` 则**一次性打印所有搭建错误**，一次全修完。

**所以搭建阶段的检查建议用 `uvm_error`**。

⚠️ **例外**：virtual interface 没取到应该用 `uvm_fatal`——vif 是 null 的话后面报错信息会很难懂。

### 超时退出

```systemverilog
uvm_top.set_timeout(500ns, 0);     // 第二个参数：0=不可被后面覆盖
```

```bash
./simv +UVM_TIMEOUT=500ns,YES
```

```
UVM_FATAL: Watchdog timeout of '500ns' expired.
```

**每个项目都该设一个**，值取"正常测试时间的 2~3 倍"。防止测试挂起时无限跑下去占着机器。

**常见挂起原因**：driver 忘了 `item_done()`、objection 没 drop、等一个永远不来的信号。

### phase 跳转（细分 phase 的真正价值）

```systemverilog
task my_driver::main_phase(uvm_phase phase);
  fork
    while (1) begin ...正常驱动... end
    begin
      @(negedge vif.rst_n);                        // 检测到复位
      phase.jump(uvm_reset_phase::get());          // ★ 整个平台跳回 reset_phase
    end
  join
endtask
```

各组件在自己的 `reset_phase` 里写好清理代码（清队列、复位状态），跳转时自动执行。

**没有它的话**，你得在 scoreboard、reference model 各处手写"检测到复位就清空"的代码。

**实际项目用得不多**，知道有这个能力即可。

## 5. objection 深入

### 只对 task phase 有效

function phase 不耗时，执行完自然结束，不需要"反对结束"。

### 它实现了 phase 之间的同步

```
A raise → 1
B raise → 2
A drop  → 1        ← A 完成了，但还不能进下一个 phase
B drop  → 0        ← ★ 归零，main_phase 结束
```

**A 在自己 drop 之后到计数归零之间，处于等待状态**——这就是上面那张图的空白。

### 为什么必须写 `phase.`

**每个 phase 有独立的计数器**：

```systemverilog
task main_phase(uvm_phase phase);
  phase.raise_objection(this);     // main_phase 的计数器
endtask
task run_phase(uvm_phase phase);
  phase.raise_objection(this);     // run_phase 的计数器（另一个）
endtask
```

这也解释了为什么 sequence 要 `get_starting_phase()`——`body()` **没有 phase 参数**。

### 在哪控制（最佳实践）

| 位置 | 可行吗 |
|---|---|
| **sequence 里** | ✅ **最佳** |
| test 的 main_phase | ✅（手动 start 时） |
| scoreboard | ✅（需配合 `fork...join_any` 跳出无限循环） |
| **driver / monitor** | ❌ 无限循环，drop 执行不到 |

> UVM 的设计哲学就是全部由 sequence 来控制激励的生成，因此**一般情况下只在 sequence 中控制 objection**。

### drain time

**问题**：sequence 发完最后一个包就 drop，但 DUT 还在处理 → 最后的输出收不到。

**两种解法**：

```systemverilog
// 解法一：手动延时（简单直接）
repeat (5) `uvm_do(m_trans);
#100;
phase.drop_objection(this);

// 解法二：set_drain_time（更规范，在计数归零后再等）
task base_test::main_phase(uvm_phase phase);
  phase.phase_done.set_drain_time(this, 200);
endtask
```

**取多少**：DUT 处理一个最长事务所需时间的 2~3 倍，**宁可多留**。

### 调试

```bash
./simv +UVM_OBJECTION_TRACE      # 打印每一次 raise 和 drop
```

| 症状 | 原因 | trace 里看什么 |
|---|---|---|
| **仿真立刻结束**（时刻 0） | 没人 raise | 完全没有 raise 记录 |
| **仿真永不结束** | 有人 raise 没 drop | 看谁的计数还挂着 |

### raise/drop 必须配对

```systemverilog
phase.raise_objection(this);
phase.raise_objection(this);     // raise 两次
phase.drop_objection(this);      // 只 drop 一次 → 计数仍是 1 → 永不结束
```

也可以一次 raise/drop 多个：

```systemverilog
phase.raise_objection(this, "reason", 3);    // 一次 +3，字符串会出现在 trace 里
```

## 6. raise/drop 的是谁

| 启动方式 | 谁 raise/drop | 写在哪 |
|---|---|---|
| `default_sequence` | **顶层 sequence 自己** | sequence 的 `body()` |
| `seq.start(sqr)` | **启动它的 test** | test 的 `main_phase` |

**整个环境里通常只有一处 raise、一处 drop。**

多 agent 环境如果各自独立启动，会有多个顶层（各自 raise/drop，全部 drop 才结束），但它们**无法互相协调**——所以实际项目用 **virtual sequence** 作为唯一顶层。
