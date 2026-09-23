# 01 UVM 是什么

> 对应《UVM实战》Ch1 + 2.1

## 1. 定义

**UVM（Universal Verification Methodology）= SystemVerilog 类库 + 验证方法学。**

| 部分 | 含义 |
|---|---|
| **类库（library）** | 几乎所有东西都是 class，你通过**继承**它们写自己的组件 |
| **方法学（methodology）** | 规定验证平台该长什么样、组件之间怎么协作 |

```systemverilog
class my_driver extends uvm_driver;     // 就是第 4 课学的 extends
```

## 2. 为什么需要方法学

手搓 testbench 时很多决定是**拍脑袋定的**：组件在哪创建？怎么通信？怎么启动？换个人就不一样，**代码无法复用、新人看不懂**。

方法学把这些决定**标准化**：
- 跨项目、跨团队复用
- EDA 工具能提供统一的调试支持

## 3. 为什么是 UVM

| 判断标准 | UVM |
|---|---|
| EDA 厂商支持 | Synopsys / Mentor / Cadence **三家联合推出并全面支持** |
| 业界使用 | IC 公司招验证岗**最基本的要求** |
| 有更好的吗 | 没有 |

**发展史**：OVM(2008) → UVM1.0EA(2010) → UVM1.0(2011.02) → **UVM1.1d** → UVM1.2 → IEEE 1800.2

书基于 1.1d，EDA Playground 上常用 1.2。**差异见"版本差异"一节。**

## 4. 验证平台的四大功能

| 功能 | 组件 |
|---|---|
| 给 DUT 施加激励 | **driver** |
| 收集 DUT 输出 | **monitor** |
| 给出预期结果 | **reference model** |
| 判断是否符合预期 | **scoreboard** |

## 5. UVM 引入的两个新概念

### agent

把**操作同一接口**的 driver + monitor + sequencer 打包：

```
┌─────── agent ────────┐
│  sequencer           │
│     ↓                │
│  driver    monitor   │
└──────────────────────┘
```

**一个 agent = 某个接口的完整代理**，换项目整体搬运。

| 模式 | 包含 | 用在 |
|---|---|---|
| `UVM_ACTIVE` | sequencer + driver + monitor | 输入接口 |
| `UVM_PASSIVE` | **只有 monitor** | 输出接口 |

### sequence

**把激励生成从 driver 剥离**：

```
sequence ──产生 transaction──► sequencer ──► driver ──► DUT
（发什么）                      （仲裁）     （怎么发）
每个用例一个                                写一次复用
```

**比喻**：sequence 是弹夹，transaction 是子弹，sequencer 是枪。

## 6. 典型平台框图

```
┌──────────────── env ─────────────────┐
│  ┌── i_agent ──┐      ┌── o_agent ─┐ │
│  │  sequencer  │      │            │ │
│  │  driver     │      │  monitor   │ │
│  │  monitor ───┼──┐   │      │     │ │
│  └─────────────┘  │   └──────┼─────┘ │
│                   ▼          │       │
│           reference model    │       │
│                   │期望值    │实际值 │
│                   └► scoreboard ◄────┘
└───────────────────────────────────────┘
              ↕ virtual interface
            ┌───────┐
            │  DUT  │
            └───────┘
```

## 7. 为什么两个 agent 都有 monitor

| | 输入侧 monitor | 输出侧 monitor |
|---|---|---|
| 观察 | DUT 的**输入** | DUT 的**输出** |
| 数据给谁 | reference model | scoreboard |

**关键**：reference model 的输入应来自 **input monitor**，不是 driver——

> driver 知道的是"**它打算发的**"，input monitor 看到的是"**DUT 真正收到的**"。

如果 driver 有 bug（时序写错、信号错位），用 driver 的数据算期望值会**误判成 DUT 的 bug**。

## 8. UVM 树

```
uvm_top（隐藏的真正的根）
 └── uvm_test_top（run_test 创建，固定实例名）
      └── env
           ├── i_agt ── sqr, drv, mon
           ├── o_agt ── mon
           └── scb
```

**路径 = 每层 create 时传的 name 串起来**：`uvm_test_top.env.i_agt.drv`

## 9. 与手搓 testbench 的对照

| 手搓的 | UVM 里的 |
|---|---|
| Transaction 类 | `uvm_sequence_item` |
| Driver / Monitor / Scoreboard | `uvm_driver` / `uvm_monitor` / `uvm_scoreboard` |
| mailbox | **TLM port / analysis port** |
| top 里手动 new + fork | **factory + phase 机制** |
| 手动传 virtual interface | **config_db 机制** |
| driver 里直接 randomize | **sequence 机制** |

**最后三行是 UVM 真正新增的东西**，也是学习重点。

## 10. 学习 UVM 需要的 SV 基础

| SV 知识 | 在 UVM 里的作用 |
|---|---|
| **继承** | `class my_driver extends uvm_driver` |
| **多态 + virtual** | 框架用基类句柄调到你的实现（phase 方法全是 virtual） |
| **参数化类** | `uvm_driver #(my_transaction)` |
| **`$cast`** | 向下转型（`mid_do` 的参数、`p_sequencer`） |
| 句柄 | virtual interface、transaction 传递 |
| 约束随机 | transaction 的 rand + constraint |
| 关联数组 | factory 内部的注册表 |
| fork-join | driver/monitor 并发、scoreboard 双进程 |

**这些都懂的话，UVM 的门槛就只剩"记住它的约定"。**

## 11. UVM 1.1d vs 1.2 的差异（踩过的坑）

| | UVM 1.1d（书里） | UVM 1.2 |
|---|---|---|
| sequence 里取 phase | `starting_phase` | **`get_starting_phase()`** |

⚠️ 1.2 里 `starting_phase` **不再自动赋值**（是 null），沿用书里写法会导致：

```
$finish at simulation time  0        ← 仿真立刻结束，一个包都没发
```

**1.2 的正确写法**：

```systemverilog
virtual task body();
  uvm_phase phase;
  phase = get_starting_phase();
  if (phase != null) phase.raise_objection(this);
  ...
  if (phase != null) phase.drop_objection(this);
endtask
```
