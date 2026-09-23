# UVM 验证学习笔记

基于《UVM实战（卷Ⅰ）》（张强著）的学习笔记，面向**已有 SystemVerilog 基础、目标是 IC 验证岗**的读者。

配套的 SystemVerilog 笔记见 [systemverilog-notes](https://github.com/ruiboyan-cpu/systemverilog-notes)。

## 环境

所有代码在 [EDA Playground](https://www.edaplayground.com/) 上验证通过。

- **语言**：SystemVerilog/Verilog
- **UVM 版本**：UVM 1.2（书基于 1.1d，差异见下）
- **仿真器**：Synopsys VCS 或 Aldec Riviera-PRO

⚠️ **UVM 1.1d vs 1.2 的关键差异**：

```systemverilog
// 1.1d（书里）
if (starting_phase != null) starting_phase.raise_objection(this);

// 1.2（推荐）—— starting_phase 不再自动赋值，会是 null
uvm_phase phase = get_starting_phase();
if (phase != null) phase.raise_objection(this);
```

沿用书里写法会导致**仿真在时刻 0 立刻结束、一个包都不发**。

## 目录

| 章节 | 内容 | 对应原书 |
|---|---|---|
| [00 固定写法速查表](notes/00-cheatsheet.md) ★ | 必须一字不差的字符串、组件模板、库自带名字、常见错误 | — |
| [01 UVM 是什么](notes/01-what-is-uvm.md) | 类库+方法学、验证平台组成、agent、sequence | Ch1 + 2.1 |
| [02 搭建完整验证平台](notes/02-build-testbench.md) ★ | factory / objection / config_db / transaction / env / monitor / agent / TLM / scoreboard / field automation / sequence / base_test | Ch2 |
| [03 UVM 基础](notes/03-uvm-basics.md) | component vs object、树形结构、打印控制、config_db 深入 | Ch3 |
| [04 TLM 通信](notes/04-tlm.md) | 四种操作、PORT/EXPORT/IMP、analysis port、FIFO | Ch4 |
| [05 phase 与 objection](notes/05-phase-objection.md) | phase 列表与顺序、super.phase、超时、objection 深入 | Ch5 |
| [06 sequence](notes/06-sequence.md) ★ | 启动与握手、uvm_do 家族、回调、仲裁、嵌套、virtual sequence、response | Ch6 |
| [07 factory 机制](notes/07-factory.md) ★ | 四个前提、重载方式、调试、常用场景、实现原理 | Ch8 |
| [08 代码可重用性](notes/08-reusability.md) | callback 机制、三种机制对比、小而美、模块级到芯片级 | Ch9 |

**跳过的章节**：Ch7 寄存器模型、Ch10 高级应用。

## 动手练习

| 文件 | 内容 |
|---|---|
| [01 最小 UVM 环境](lab/01-minimal-uvm-blank.sv) | 32 个填空。driver + monitor + scoreboard + env + FIFO，激励写在 driver 里 |
| [02 标准 UVM 环境](lab/02-standard-uvm-blank.sv) | 26 个填空。在上面基础上加 sequence + sequencer + agent + test |

两份都是**填空练习**（骨架已给、关键处留空），在 EDA Playground 上可直接跑通。

**推荐顺序**：先做 01 跑通闭环，体会"激励写死在 driver 里"的不便，再做 02 重构——这样对 sequence 机制的理解最深。

## 验证平台结构

```
uvm_test_top (my_case0)              ← 配置层：选 sequence、设 override
      └── env                        ← 环境层：创建组件、连接端口
           ├── i_agt (UVM_ACTIVE)
           │     ├── sqr ←──┐
           │     ├── drv ───┘ seq_item_port ↔ seq_item_export
           │     └── mon ──ap──┐
           ├── o_agt (UVM_PASSIVE)   │
           │     └── mon ──ap────────┼──► FIFO ──► scb
           └── scb ◄─────────────────┘
```

| 层 | 职责 | 改动频率 |
|---|---|---|
| top_tb | 例化接口、连 DUT、投递 vif、run_test | 几乎不改 |
| **test** | 配置：选 sequence、设 override | **每个用例一个** |
| env | 搭平台 | 几乎不改 |
| agent / driver / monitor | 实现协议 | 几乎不改 |
| **sequence** | 产生激励 | **每种激励一个** |

**变的只有 test 和 sequence，其余全是复用的。**

## 四大机制

| 机制 | 解决什么 | 关键 |
|---|---|---|
| **factory** | 不改代码替换组件实现 | `type_id::create` + `set_type_override` |
| **phase** | 自动编排仿真流程 | build 自顶向下、connect 自底向上 |
| **config_db** | 跨层次传配置（vif、参数） | 类型+路径+名字三者必须匹配 |
| **sequence** | 激励与驱动分离 | sequence 发什么、driver 怎么发 |

## 与手搓 testbench 的对照

| 手搓的 | UVM 里的 |
|---|---|
| Transaction 类 | `uvm_sequence_item` |
| Driver / Monitor / Scoreboard | `uvm_driver` / `uvm_monitor` / `uvm_scoreboard` |
| mailbox | TLM analysis port + FIFO |
| top 里手动 new + fork | **factory + phase 机制** |
| 手动传 virtual interface | **config_db 机制** |
| driver 里直接 randomize | **sequence 机制** |

**最后三行是 UVM 真正新增的东西。**

## 最常见的低级错误

| 错误 | 症状 |
|---|---|
| 忘了 `item_done()` | **只发出一个包**就停住 |
| `"default_sequence"` 拼错 | **没有任何激励**，也不报错 |
| 用 `new()` 而非 `type_id::create()` | factory override 失效 |
| 忘加 `virtual` | 框架调到基类空实现，**你的代码没执行也不报错** |
| 在无限循环里 raise_objection | **仿真永不结束** |
| 没有 raise_objection | **仿真在时刻 0 立刻结束** |
| config_db 的名字拼错 | get 返回 0 → vif 是 null → 运行时崩 |
| 忘调 `super.build_phase()` | field automation 静默失效 |

完整列表见 [速查表](notes/00-cheatsheet.md)。

## 调试手段

```bash
+UVM_VERBOSITY=UVM_HIGH        # 调冗余度
+UVM_PHASE_TRACE               # 打印 phase 流程
+UVM_OBJECTION_TRACE           # 查 raise/drop（仿真不结束或立刻结束）
+UVM_CONFIG_DB_TRACE           # 查 config_db 的 set/get
+UVM_MAX_QUIT_COUNT=10         # 限制错误数
+uvm_set_type_override="A,B"   # 临时重载
```

```systemverilog
uvm_top.print_topology();      // ★ 打印整棵树（建议放进 base_test）
factory.print(0);              // 所有重载记录
check_config_usage();          // 哪些 config_db 的 set 没被用到
```

## 说明

- 术语首次出现时标注英文
- 每章有**速记表**和**常见陷阱**
- 示例代码尽量完整可运行，变量命名避免缩写
- 标 ★ 的是最核心的章节
