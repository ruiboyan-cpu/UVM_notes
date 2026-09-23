# 04 TLM 通信

> 对应《UVM实战》Ch4。组件之间怎么传数据。

## 1. 为什么需要 TLM

用 SV 原生手段（mailbox、public 变量）的问题：**代码量大、没有约束、阻塞行为难统一**。

**TLM 的思路**：在两个组件之间建**专用通道**，信息只在通道内流动，通道自带阻塞/非阻塞特性。

**TLM = Transaction Level Modeling**——组件之间传递的是 **transaction 对象**，不是信号。

## 2. 四种操作

| 操作 | 数据流 | FIFO 里的数据 | 一次几笔 |
|---|---|---|---|
| **put** | 发起者 → 目标 | +1 | 1 |
| **get** | 目标 → 发起者 | **-1（取走）** | 1 |
| **peek** | 目标 → 发起者 | **不变（只看）** | 1 |
| **transport** | 双向 | — | **2（一来一回）** |

### get vs peek

```systemverilog
// FIFO 里有 [A, B, C]
port.get(tr);     // tr = A，FIFO → [B, C]        消费掉
port.peek(tr);    // tr = A，FIFO → [A, B, C]     只复制
```

### get_peek 是"二合一端口"

不是新操作，而是**同时支持 get 和 peek 的端口**（对方要实现两个方法）。

### transport 是原子的"一来一回"

```systemverilog
uvm_blocking_transport_port #(my_request, my_response) port;
//                            └────┬────┘  └────┬────┘
//                             发出的类型    收回的类型
port.transport(req, rsp);      // 一次调用，发 req 收 rsp
```

**比 put + get 两步强在**：保证一来一回是**配对**的，中间不会被别的事务插队。

**用途**：寄存器读、需要立即拿到回复的场景。

## 3. PORT / EXPORT / IMP

### 核心认识：体现的是控制流，不是数据流

| 操作 | 数据流方向 | A 的端口 | B 的端口 |
|---|---|---|---|
| **put** | A → B | **PORT** | EXPORT |
| **get** | **B → A** | **PORT** | EXPORT |

**数据流方向相反，但端口类型不变**——**发起者永远是 PORT**。

这解释了那个反直觉的写法：

```systemverilog
scb.exp_port.connect(fifo.blocking_get_export);
//   └──┬───┘
//  数据是 FIFO→scb，但 scb 拿 PORT，因为【它主动去 get】
```

### 三者的角色

```
优先级：  PORT  >  EXPORT  >  IMP
           ↓        ↓         ↓
角色：   发起者    中转      终点 + 实现
```

**只有高优先级能向低优先级发起操作**，所以 `connect` 永远是：

```systemverilog
A.port.connect(B.export);      // ✓ 主动方打头
B.export.connect(A.port);      // ✗
```

### 15 种 PORT（命名规律）

```
uvm_ [blocking|nonblocking|无] _ [put|get|peek|get_peek|transport] _ port
      └──── 阻塞特性 ────┘        └────── 操作类型 ──────┘
```

- 带 `blocking` → 只能阻塞操作
- 带 `nonblocking` → 只能非阻塞操作
- 都不带 → 两种都能

EXPORT 和 IMP 各有对应的 15 种，只换后缀。**不用背，按规律拼。**

**一个端口只能做一种操作**——想做别的就再声明一个。

## 4. IMP —— 通信链路的终点

### 只连 PORT 和 EXPORT 会报错

```
UVM_ERROR [Connection Error] connection count of 0 does not meet required minimum of 1
UVM_FATAL stopping due to build errors
```

**因为 PORT 和 EXPORT 都只是"门"——只转发，不做实际工作。**

> PORT 恰如一道门，EXPORT 也如此。**它不可能把一笔 transaction 存储下来**，除了转发之外不作其他操作。

**必须有个东西真正接住并处理——这就是 IMP。**

### 用法

```systemverilog
class B extends uvm_component;
  uvm_blocking_put_imp #(my_transaction, B) B_imp;
  //                     └──────┬─────┘ └┬┘
  //                        数据类型   ★ 谁来实现（IMP 独有的第二个参数）

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    B_imp = new("B_imp", this);
  endfunction

  task put(my_transaction tr);      // ★★ 必须实现同名方法
    ...
  endtask
endclass
```

### 调用链

```
A_port.put(tr) → B_export.put(tr) → B_imp.put(tr) → B.put(tr)
    转发            转发              转发         ★ 你写的，真正执行
```

### 方法名由端口类型决定

| IMP 类型 | 实现方式 | 方法名 |
|---|---|---|
| `uvm_blocking_put_imp` | **task** | `put` |
| `uvm_nonblocking_put_imp` | **function** | `try_put` + `can_put` |
| `uvm_blocking_get_imp` | **task** | `get` |
| `uvm_blocking_peek_imp` | **task** | `peek` |
| `uvm_blocking_get_peek_imp` | task | **`get` 和 `peek` 都要** |
| `uvm_analysis_imp` | **function void** | **`write`** |

**规律**：`blocking` → task、`nonblocking` → function（带返回值）、`analysis` → function void。

不实现会报：`No field named 'put'`。

⚠️ 非阻塞版**即使只用 `try_put` 也必须定义 `can_put`**，否则编译报错。

### 合法的连接

| 从 → 到 | 合法 |
|---|---|
| PORT → EXPORT / IMP | ✅ |
| EXPORT → IMP | ✅ |
| PORT → PORT、EXPORT → EXPORT | ✅ **层次连接** |
| IMP → 任何 | ❌ IMP 是终点 |

**一条链路的终点必须是 IMP。**

### 层次连接：把内部端口暴露到外层

```systemverilog
// A 内部
function void A::connect_phase(uvm_phase phase);
  C_inst.C_port.connect(this.A_port);       // 内层 port 连外层 port
endfunction
// env 里
A_inst.A_port.connect(B_inst.B_imp);
```

外面不用知道 A 的内部结构。**这正是 connect_phase 自底向上执行的原因**。

## 5. analysis port —— 一对多广播

| | put/get 系列 | **analysis** |
|---|---|---|
| 连接数量 | 一对一 | **一对多**（广播） |
| 阻塞概念 | 有 blocking/nonblocking | **没有** |
| 操作 | put/get/peek/transport | **只有 `write`** |

**为什么没有阻塞概念**：广播发出去就不管，不等接收方。所以 `write` 是 `function void`。

```systemverilog
// 发送方
uvm_analysis_port #(my_transaction) ap;
ap = new("ap", this);
ap.write(tr);                          // 非阻塞，立即返回

// 连接多个接收方 = 广播
mon.ap.connect(scb.imp);
mon.ap.connect(mdl.imp);
mon.ap.connect(cov.imp);
```

⚠️ analysis_port 只能连 **analysis 家族**（`analysis_export` 或 `analysis_imp`），不能连 put/get 系列。

### 多个同类型 IMP 的方法重名问题

scoreboard 要收两路数据 → 两个 `analysis_imp` → **一个类不能有两个 `write`**。

**解法：`uvm_analysis_imp_decl` 宏**

```systemverilog
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_act)

class my_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp_exp #(my_transaction, my_scoreboard) exp_imp;   // 类型带后缀
  uvm_analysis_imp_act #(my_transaction, my_scoreboard) act_imp;

  function void write_exp(my_transaction tr); ... endfunction      // 方法也带后缀
  function void write_act(my_transaction tr); ... endfunction
endclass
```

## 6. FIFO

### 它解决 IMP 方式的两个麻烦

| IMP 方式的问题 | FIFO 怎么解决 |
|---|---|
| **节奏被绑死**（被动调用、function 不能耗时） | 接收方**主动 get**，用 task 能等能 fork |
| **多路输入方法重名** | 两个 FIFO 两个 get_port，天然不冲突 |

### 用法

```systemverilog
uvm_tlm_analysis_fifo #(my_transaction) fifo;
fifo = new("fifo", this);                      // ★ 用 new

mon.ap.connect(fifo.analysis_export);          // monitor → FIFO（入口）
scb.exp_port.connect(fifo.blocking_get_export);// FIFO → scoreboard（出口）
```

### FIFO 上那些 export 其实是 IMP

```systemverilog
// UVM 源码
uvm_analysis_imp #(T, uvm_tlm_analysis_fifo #(T)) analysis_export;
//   ↑ 类型是 IMP                                  ↑ 名字叫 export
```

**UVM 故意起名叫 `export` 来"掩饰 IMP 的存在"**，让初学者不用面对它。FIFO 内部已实现好所有方法。

### FIFO 的端口

```
写入侧：analysis_export、put_export、blocking_put_export...
读出侧：get_export、blocking_get_export、peek_export、get_peek_export...
额外：  put_ap（每次放入时广播一份）、get_ap（每次取走时广播一份）
```

`put_ap`/`get_ap` 用于**监控 FIFO 的活动**（统计吞吐量、调试）。

### 两种 FIFO

| | `uvm_tlm_analysis_fifo` | `uvm_tlm_fifo` |
|---|---|---|
| 有 `analysis_export` | ✅ | ❌ |
| 接 monitor 的 ap | ✅ | 不能 |

**唯一差别就是有没有 analysis_export。**

### 调试函数

```systemverilog
fifo.used()        // 里面有几个
fifo.is_empty()
fifo.is_full()
```

```systemverilog
if (fifo.used() > 100)
  `uvm_warning("SCB", "FIFO 积压严重，消费方跟不上")
```

## 7. FIFO 还是 IMP

| 场景 | 选择 |
|---|---|
| 接收方要控制节奏（能等、能 fork） | **FIFO** |
| 多路输入（避免 write 重名） | **FIFO** |
| 只是简单处理、不耗时（如 coverage collector） | IMP |
| 对内存/性能敏感 | IMP（少一层缓冲） |

**scoreboard 用 FIFO，coverage collector 常用 IMP**：

```systemverilog
class my_coverage extends uvm_component;
  uvm_analysis_imp #(my_transaction, my_coverage) imp;
  covergroup cg; ... endgroup

  function void write(my_transaction tr);
    cg.sample();          // 采样一下就完事，不耗时
  endfunction
endclass
```
