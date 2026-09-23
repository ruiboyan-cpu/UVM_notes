# 06 sequence

> 对应《UVM实战》Ch6。最重要的一章，内容几乎全写在 sequence 的 `body()` 里。

## 0. 三者分工

```
sequence  = 决定【发什么】   ← 本章全在讲它，每个用例一个
sequencer = 传递 + 仲裁      ← 基类实现，一行代码不用写
driver    = 决定【怎么发】   ← 三行固定动作，写完不动
```

### transaction vs sequence

| | **transaction** | **sequence** |
|---|---|---|
| 是什么 | **一个包**（纯数据） | **产生包的程序** |
| 比喻 | 子弹 | 弹夹 / 装弹程序 |
| 基类 | `uvm_sequence_item` | `uvm_sequence #(T)` |
| 有 `body()` | ❌ | ✅ |
| driver 看得到 | ✅ **driver 驱动的就是它** | ❌ 完全透明 |

**两者看起来像**，是因为 sequence **继承自** sequence_item（所以也能 randomize、也能被 `` `uvm_do `` 调用），但**最终送到 driver 的永远是 transaction**。

## 1. 启动方式

### 方式一：`start()` 手动启动

```systemverilog
task my_case0::main_phase(uvm_phase phase);
  my_sequence seq;
  phase.raise_objection(this);           // ★ test 来控制 objection
  seq = my_sequence::type_id::create("seq");
  seq.file_name = "data.txt";            // ★ 能传参数
  seq.start(env.i_agt.sqr);              // 阻塞，body 执行完才返回
  phase.drop_objection(this);
endtask
```

完整签名：`seq.start(sequencer, parent_seq, priority)`

### 方式二：`default_sequence`

```systemverilog
uvm_config_db#(uvm_object_wrapper)::set(this,
    "env.i_agt.sqr.main_phase",      // ★ 路径末尾必须指明 phase
    "default_sequence",              // ★ 固定字符串
    my_sequence::type_id::get());
```

| | `start()` | `default_sequence` |
|---|---|---|
| 能传参数 | ✅ | ❌ |
| objection | 外面控制 | sequence 里用 `get_starting_phase()` |
| 适合 | 复杂场景（fork、传值） | **简单场景，最常用** |

## 2. 握手机制

### 时间顺序

```
【1】driver: get_next_item(req)        ← 阻塞，等货
【2】sequence: start_item()            ← 举手"我有货"
     → driver 的 get_next_item 解除阻塞，拿到包
【3】sequence: randomize()             ← ★ driver 来的那一刻才随机
     sequence: finish_item()           ← 阻塞，等回执
     driver:   drive_one_pkt(req)      ← 耗时驱动
【4】driver: item_done()                ← 回执
     → sequence 的 finish_item 解除阻塞
     → driver 回到 get_next_item 继续等
```

**两处阻塞交替解锁**：

| 谁 | 卡在哪 | 被谁解锁 |
|---|---|---|
| driver | `get_next_item()` | sequence 的 `start_item()` |
| sequence | `finish_item()` | driver 的 `item_done()` |

**结果**：sequence 不会跑到 driver 前面堆积，**全程最多一个 transaction 在途**。

⚠️ **忘写 `item_done()` 的症状：只发出一个包就卡死。**

### sequencer 不是 FIFO

| | FIFO | sequencer |
|---|---|---|
| 缓冲 | ✅ 能存多个 | ❌ **不存** |
| 生产者要等吗 | ❌ | ✅ **要等回执** |
| 角色 | 缓冲解耦 | **握手中介 + 仲裁** |

**它的真正价值是仲裁**——多个 sequence 抢同一个 driver 时决定谁先。

### `item_done()` 的深层作用

driver 用 `get_next_item` 取走时，**sequencer 自己也留了一份**。收到 `item_done` 才删掉，否则会**重发**——这是防丢失的握手机制。

### `try_next_item`：非阻塞版

```systemverilog
seq_item_port.try_next_item(req);
if (req == null) @(posedge vif.clk);       // 没货就驱动总线 idle
else begin
  drive_one_pkt(req);
  seq_item_port.item_done();
end
```

**更接近真实 driver 的行为**，但 `get_next_item` 更常用。

### pre_body / post_body

基类里的 **virtual 空方法**，不重写就是什么都没做。

⚠️ **只有 `start()`（含 default_sequence）启动时才调用**——嵌套调用时不执行，所以重要逻辑别放里面。

## 3. uvm_do 宏家族

### 八个宏 = 三个后缀的组合

```
`uvm_do _on _pri _with
         ↓    ↓    ↓
    指定sqr 优先级 约束
```

全由 `` `uvm_do_on_pri_with(ITEM, SEQR, PRI, CONSTRAINTS) `` 实现：

```systemverilog
`define uvm_do(X)  `uvm_do_on_pri_with(X, m_sequencer, -1, {})
```

- **`m_sequencer`**：sequence 自带成员，指向启动它的 sequencer
- **优先级**：≥ -1 的整数，**数字越大优先级越高**，默认 -1
- **`_on` 的真正用处在 virtual sequence**

### 第一个参数可以是 sequence

| 参数是 | 宏做什么 |
|---|---|
| transaction | `start_item` + `finish_item` |
| **sequence** | 调用它的 `start()` → **嵌套** |

### 另外两组宏

```systemverilog
// 组二：中间能加工
`uvm_create(m_trans)
assert(m_trans.randomize());
m_trans.pload[0] = 8'hFF;          // ★ 加工
`uvm_send(m_trans)

// 组三：复用内存
m_trans = new("m_trans");          // 只 new 一次
repeat (1000) `uvm_rand_send(m_trans)
```

⚠️ 复用内存有**数据被覆盖**的风险（scoreboard 里存的是句柄），一般还是用 `` `uvm_do ``。

## 4. start_item / finish_item 与三个回调

### 宏的真身

```systemverilog
// `uvm_do(tr) ≈
tr = new("tr");
start_item(tr);
assert(tr.randomize());        // ★ 在 start_item 之后
finish_item(tr);
```

- 必须**先 new 再 start_item**
- 优先级要在**两处都写**：`start_item(tr, 100); finish_item(tr, 100);`

### 三个回调

```
start_item {
    wait_for_grant()        ← 等 driver
    pre_do(is_item)         ★ task，随机化【之前】
}
                            ← randomize() 在这里
finish_item {
    mid_do(item)            ★ function，随机化后、发送前 —— 最有用
    send_request()
    wait_for_item_done()
    post_do(item)           ★ function，driver 处理完之后
}
```

**`mid_do` 最有用**——在"随机化完成、还没发出去"的空档加工 transaction：

```systemverilog
virtual function void mid_do(uvm_sequence_item this_item);
  my_transaction tr;
  void'($cast(tr, this_item));        // ★ 参数是基类类型，要 $cast
  {tr.pload[p_sz-4], ..., tr.pload[p_sz-1]} = num;    // 写入序号
  tr.crc = tr.calc_crc();
endfunction
```

| 方式 | 特点 |
|---|---|
| `` `uvm_create `` + 加工 + `` `uvm_send `` | 加工代码写在 body 里，每处都要写 |
| **`mid_do`** | **所有 `` `uvm_do `` 自动生效**，body 保持简洁 |

## 5. 仲裁机制

### 优先级

**只在多个 sequence 并行抢同一个 sequencer 时有用。**

```systemverilog
// transaction 级
`uvm_do_pri(m_trans, 200)

// sequence 级（本质是批量设置前者）
seq1.start(sqr, null, 200);
```

⚠️ **光设优先级不生效**——sequencer 默认算法 `SEQ_ARB_FIFO` **不看优先级**：

```systemverilog
env.i_agt.sqr.set_arbitration(SEQ_ARB_STRICT_FIFO);    // ★ 必须加这句
```

| 算法 | 行为 |
|---|---|
| **`SEQ_ARB_FIFO`**（默认） | 先进先出，**不看优先级** |
| `SEQ_ARB_WEIGHTED` | 加权 |
| `SEQ_ARB_RANDOM` | 完全随机 |
| **`SEQ_ARB_STRICT_FIFO`** | **严格按优先级**，同级先进先出 |
| **`SEQ_ARB_STRICT_RANDOM`** | **严格按优先级**，同级随机 |
| `SEQ_ARB_USER` | 自定义 |

### lock / grab —— 独占 sequencer

**优先级只能让 transaction "更早被选"，保证不了连续。**

```systemverilog
lock();                            // 排队后独占
repeat (4) `uvm_do(m_trans)        // 这 4 个连续发出，不被打断
unlock();

grab();                            // 插队后独占
repeat (4) `uvm_do(m_trans)
ungrab();
```

| | `lock()` | `grab()` |
|---|---|---|
| 在仲裁队列的位置 | **末尾**（排队） | **最前**（插队） |
| 拿到所有权 | 等前面的都处理完 | 几乎立即 |

**冲突时**：grab 会插队，但**绝不打断别人正在进行的独占**。

⚠️ **必须成对释放**，否则其他 sequence 永远拿不到 sequencer。

### is_relevant —— 主动退出仲裁

```systemverilog
virtual function bit is_relevant();
  return !has_delayed;              // 返回 0 = 暂时不参与仲裁
endfunction

virtual task wait_for_relevant();   // ★ 必须成对重写
  #10000;
  has_delayed = 0;                  // ★ 必须让条件恢复，否则死锁
endtask
```

只重写 `is_relevant` 会报：`[RELMSM] is_relevant() was implemented without defining wait_for_relevant()`

| | lock / grab | is_relevant |
|---|---|---|
| 效果 | **我要独占**，别人停下 | **我暂时退出**，别人继续 |

**实际很少用。**

## 6. 嵌套 sequence

### 把常用激励封装成原子 sequence

```systemverilog
// 小 sequence：只产生一个 CRC 错误包
class crc_seq extends uvm_sequence #(my_transaction);
  virtual task body();
    my_transaction tr;
    `uvm_do_with(tr, {tr.crc_err == 1; tr.dmac == 48'h980F;})
  endtask
endclass

// 大 sequence：组合调用
class case0_sequence extends uvm_sequence #(my_transaction);
  virtual task body();
    crc_seq  cseq;
    long_seq lseq;
    repeat (10) begin
      `uvm_do(cseq)          // ★ 参数是 sequence
      `uvm_do(lseq)
    end
  endtask
endclass
```

**约束只写一次**，30 个用例都能调用——这是 sequence 的"函数化"。

两种写法等价：

```systemverilog
`uvm_do(cseq)                    // 推荐
cseq = new("cseq"); cseq.start(m_sequencer);
```

⚠️ `start_item`/`finish_item` 的参数**只能是 transaction**，不能是 sequence。

### sequence 里可以有 rand 变量

```systemverilog
class long_seq extends uvm_sequence #(my_transaction);
  rand bit [47:0] ldmac;                   // ★ sequence 自己的 rand 变量
  virtual task body();
    `uvm_do_with(tr, {tr.dmac == ldmac;})
  endtask
endclass

// 父 sequence 调用时对它加约束
`uvm_do_with(lseq, {lseq.ldmac == 48'hFFFF;})
```

**把 sequence 变成"可配置的生成器"。**

### ⚠️ 陷阱：变量同名

```systemverilog
rand bit [47:0] dmac;                      // 和 transaction 的字段同名
`uvm_do_with(tr, {tr.dmac == dmac;})       // ★ 这个 dmac 被解析为 tr.dmac！
// 等价于 {tr.dmac == tr.dmac;}  → 约束了个寂寞
```

**原因**：约束块里的变量**优先解析为被随机化对象的成员**（和 SV 内联约束的作用域规则一致）。

**解法**：

```systemverilog
rand bit [47:0] ldmac;                     // ★ 改名（推荐）
`uvm_do_with(tr, {tr.dmac == local::dmac;})  // 或用 local::
```

### 嵌套时的 objection

**只有顶层 sequence 控制 objection**，子 sequence 不碰（它的 `get_starting_phase()` 返回 null）。

## 7. virtual sequence

### 问题：多个 agent 怎么协调

需求："先在接口 0 发配置包，发完后两个接口同时发数据"。

各自 `default_sequence` 独立启动**做不到**——两个 sequence 互不知道对方。用全局变量同步则**到处飞、难维护**。

### 解法：一个"指挥官"

```
virtual sequence（只调度，不产生 transaction）
     ├── 在 sqr0 上启动 seqA
     └── 在 sqr1 上启动 seqB
```

### 三步实现

**① virtual sequencer —— 装真实 sequencer 的指针**

```systemverilog
class my_vsqr extends uvm_sequencer;          // ★ 不带参数！
  my_sequencer p_sqr0;                        // 只是句柄
  my_sequencer p_sqr1;
  `uvm_component_utils(my_vsqr)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
```

**② 在 test 的 connect_phase 里赋值**

```systemverilog
function void base_test::connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  v_sqr.p_sqr0 = env0.i_agt.sqr;              // ★ 指针赋值
  v_sqr.p_sqr1 = env1.i_agt.sqr;
endfunction
```

**在 connect_phase**——build 全部完成后真实 sequencer 才存在。

**③ virtual sequence —— 调度逻辑**

```systemverilog
class case0_vseq extends uvm_sequence;             // ★ 也不带参数
  `uvm_object_utils(case0_vseq)
  `uvm_declare_p_sequencer(my_vsqr)                // ★ 关键

  virtual task body();
    uvm_phase phase = get_starting_phase();
    if (phase != null) phase.raise_objection(this);     // ★ 唯一的 objection

    `uvm_do_on_with(tr, p_sequencer.p_sqr0, {tr.pload.size == 1500;})   // ① 先配置

    fork                                                                 // ② 再并行
      `uvm_do_on(seq0, p_sequencer.p_sqr0)
      `uvm_do_on(seq1, p_sequencer.p_sqr1)
    join

    if (phase != null) phase.drop_objection(this);
  endtask
endclass
```

**先后靠 body 的顺序执行，并行靠 fork——无需任何同步代码。**

**④ 启动**

```systemverilog
uvm_config_db#(uvm_object_wrapper)::set(this,
    "v_sqr.main_phase",                          // ★ 挂在 virtual sequencer 上
    "default_sequence", case0_vseq::type_id::get());
```

### p_sequencer vs m_sequencer

| | `m_sequencer` | `p_sequencer` |
|---|---|---|
| 来源 | sequence **自带** | **`` `uvm_declare_p_sequencer `` 生成** |
| 类型 | `uvm_sequencer_base`（**基类**） | **你声明的具体类型** |
| 能访问 `p_sqr0` | ❌ 基类里没这个成员 | ✅ |

宏做的事：

```systemverilog
my_vsqr p_sequencer;
$cast(p_sequencer, m_sequencer);     // ★ 向下转型
```

### p_sequencer 的另一个用途

**sequence 是 object、不在 UVM 树上，没法用 config_db 取配置**。但 sequencer 是 component，能取——于是：

```systemverilog
class my_sequencer extends uvm_sequencer #(my_transaction);
  bit [47:0] dmac;                   // 配置放在 sequencer 里
endclass

class my_sequence extends uvm_sequence #(my_transaction);
  `uvm_declare_p_sequencer(my_sequencer)
  virtual task body();
    `uvm_do_with(m_trans, {m_trans.dmac == p_sequencer.dmac;})   // ★ 读配置
  endtask
endclass
```

### virtual sequence 的三个好处

1. **协调多 agent**——先后、并行直接在 body 里写
2. **只有一处 objection**——回到简洁结构
3. **减少 config_db**——路径字符串越少越不容易错

## 8. response（driver 回数据给 sequence）

```systemverilog
// driver
seq_item_port.get_next_item(req);
drive_one_pkt(req);
rsp = new("rsp");
rsp.set_id_info(req);              // ★ 必须：把 req 的 ID 拷给 rsp
rsp.data = read_back_value;
seq_item_port.put_response(rsp);
seq_item_port.item_done();

// sequence
`uvm_do(m_trans)
get_response(rsp);                 // ★ 阻塞等待
```

**`set_id_info` 必须调**——多个 sequence 共享 sequencer 时靠 ID 路由回正确的 sequence。

**每个 request 必须对应一个 response**，否则 `get_response` 一直等。

**用途**：寄存器读、需要根据 DUT 返回值决定下一步的场景。

## 9. sequence library（了解）

让 UVM 从一堆 sequence 里**随机挑选**执行。

```systemverilog
class simple_seq_library extends uvm_sequence_library #(my_transaction);
  `uvm_object_utils(simple_seq_library)
  `uvm_sequence_library_utils(simple_seq_library)
  function new(string name = "simple_seq_library");
    super.new(name);
    init_sequence_library();          // ★ 必须
  endfunction
endclass

// 每个 sequence 登记
`uvm_add_to_seq_lib(seq0, simple_seq_library)
```

| 选择算法 | 行为 |
|---|---|
| `UVM_SEQ_LIB_RAND`（默认） | 完全随机 |
| `UVM_SEQ_LIB_RANDC` | 每个都跑一遍才重复 |
| `UVM_SEQ_LIB_ITEM` | 自己产生 transaction |
| `UVM_SEQ_LIB_USER` | 自定义 |

**使用频率不高**，多用 virtual sequence 手动编排。
