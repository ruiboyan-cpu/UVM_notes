# 07 factory 机制

> 对应《UVM实战》Ch8。

## 1. SV 本身对重载的支持（铺垫）

### 函数重载 = 多态

```systemverilog
class bird extends uvm_object;
  virtual function void hungry();  $display("I am a bird");  endfunction
  function void hungry2();         $display("bird hungry2"); endfunction    // 无 virtual
endclass
class parrot extends bird;
  virtual function void hungry();  $display("I am a parrot"); endfunction
  function void hungry2();         $display("parrot hungry2");endfunction
endclass
```

父类句柄指向子类对象时：**virtual 调子类版本，非 virtual 调父类版本**。

### 约束重载（SV 独有）

**子类定义同名约束会覆盖父类的**：

```systemverilog
class my_transaction extends uvm_sequence_item;
  rand bit crc_err;
  constraint crc_err_cons { crc_err == 1'b0; }      // 正常情况不出错
endclass

class new_transaction extends my_transaction;
  constraint crc_err_cons { crc_err dist {0:=2, 1:=1}; }   // ★ 同名 → 覆盖
endclass
```

| | 行为 |
|---|---|
| **同名** | **覆盖**（父类那条失效） |
| 不同名 | 叠加（两条都生效） |

**所以一个错误一个约束、名字独立**——子类才能精确覆盖其中一条。

### 另一种做法：关掉约束

```systemverilog
m_trans = new();                                  // ★ 必须先实例化
m_trans.crc_err_cons.constraint_mode(0);
`uvm_rand_send_with(m_trans, {crc_err dist {0:=2, 1:=1};})
```

⚠️ 不能直接用 `` `uvm_do ``——宏内部才 create，之前访问是 null。

### 两者的共同局限

**必须在创建对象的地方显式写出子类名**：

```systemverilog
new_transaction ntr;       // ★ 要改 sequence 的代码
`uvm_do(ntr)
```

**factory 解决的正是这一点。**

## 2. factory 式重载

```systemverilog
set_type_override_by_type(bird::get_type(), parrot::get_type());
bird_inst = bird::type_id::create("bird_inst");     // ★ 写的是 bird
// → 实际创建的是 parrot
```

### 原理：查表

```
set_type_override(bird, parrot)  →  factory 表里加一条记录
                                     ┌──────┬────────┐
                                     │ bird │ parrot │
                                     └──────┴────────┘
bird::type_id::create()  →  查表 → 有记录 → 创建 parrot
                         →  赋给 bird 句柄（合法：父类句柄指向子类对象）
```

**`create` 不是"创建 bird"，而是"去工厂问一下 bird 现在对应什么"。**

### 四个前提

| 前提 | 违反的后果 |
|---|---|
| **① 两个类都要注册** | factory 不认识 |
| **② 必须用 `type_id::create` 而非 `new`** | **重载静默失效**（最隐蔽） |
| **③ 重载类必须派生自被重载类** | `UVM_FATAL [FCTTYP]` |
| **④ component 和 object 不能互相重载** | 构造函数签名不同（有无 parent），factory 无所适从 |

**第 ③ 条的两种错法**：

```systemverilog
set_type_override_by_type(bird::get_type(),   bear::get_type());   // ✗ 无派生关系
set_type_override_by_type(parrot::get_type(), bird::get_type());   // ✗ 方向反了
```

**本质是第 4 课那条规则**：父类句柄能指向子类对象，反过来不行。

### 隐含要求：方法要 virtual

**factory 替换了对象，但要让新行为生效，被调用的方法必须是 virtual**——否则静态绑定到父类版本。

这就是为什么 **UVM 所有 phase 方法都是 virtual**。

## 3. 重载的方式

|  | **按类型**（`_by_type`） | **按名字**（字符串） |
|---|---|---|
| **类型重载**（全部替换） | `set_type_override_by_type` | `set_type_override` |
| **实例重载**（只替换某个） | `set_inst_override_by_type` | `set_inst_override` |

```systemverilog
// 类型重载：所有 my_monitor 都换
set_type_override_by_type(my_monitor::get_type(), new_monitor::get_type());

// 实例重载：只换 env.o_agt.mon
set_inst_override_by_type("env.o_agt.mon",        // ★ 路径在最前
                          my_monitor::get_type(), new_monitor::get_type());
```

⚠️ **参数顺序不同**：

```systemverilog
set_type_override_by_type(原类型, 新类型, [replace])
set_inst_override_by_type(相对路径, 原类型, 新类型)     ← 路径在前
```

### by_type vs 字符串

| | `_by_type` | 字符串 |
|---|---|---|
| 可读性 | 较差 | 好 |
| **拼错** | **编译报错** | ⚠️ 运行时才发现或静默失效 |

**推荐 `_by_type`。**

### 在 component 之外重载

四个函数都是 `uvm_component` 的成员。在 `top_tb` 的 initial 里用**全局 `factory` 对象**：

```systemverilog
initial begin
  factory.set_type_override_by_type(bird::get_type(), parrot::get_type());
end
```

⚠️ **factory 版的路径参数在最后，且要用完整路径**：

```systemverilog
factory.set_inst_override_by_type(原类型, 新类型, "uvm_test_top.env.o_agt.mon");
```

**规律**：component 版路径在前、相对路径；factory 版路径在后、完整路径。

### 命令行重载

```bash
./simv +uvm_set_type_override="my_monitor,new_monitor"
./simv +uvm_set_inst_override="my_monitor,new_monitor,uvm_test_top.env.o_agt.mon"
```

**用途**：临时调试。正式用例还是写代码里。

### 写在哪

**test 的 `build_phase` 里、`super.build_phase` 之后、子组件 create 之前**——重载必须在创建之前设置。

## 4. 复杂重载与调试

### 连续重载

```systemverilog
set_type_override_by_type(bird::get_type(),   parrot::get_type());
set_type_override_by_type(parrot::get_type(), sparrow::get_type());
// bird → parrot → sparrow，最终创建 sparrow
```

**factory 一直查到没有记录才创建。**

**规则修正**：多级重载时，**最终创建的类**必须派生自**最初被请求的类**，中间环节不要求。

⚠️ 但实践中别这么绕——上例中直接 `parrot::type_id::create()` 会得到 sparrow，而 sparrow 不是 parrot 的子类，**赋不进 parrot 句柄、报错**。

### replace 参数

```systemverilog
set_type_override_by_type(原类型, 新类型, bit replace = 1);
```

| replace | 同一原类型被重载两次时 |
|---|---|
| **1**（默认） | **后设置的覆盖前面的** |
| 0 | **先设置的保留**，后面的被忽略 |

**用途**：base_test 想"锁死"某个重载不让派生类改，设 0。实践中几乎总用默认值。

### 调试三件套

```systemverilog
// ① 这个位置会创建什么？（参数是【原始类型】）
env.o_agt.mon.print_override_info("my_monitor");

// ② 设了哪些重载？
factory.print(0);        // 0=只打印重载记录，1=+用户注册的类，2=+UVM 内部的类

// ③ 实际创建出了什么？
uvm_top.print_topology();
```

`print_topology` 的 **Type 列**直接显示实际类型：

```
o_agt         my_agent
  mon         new_monitor      ← ★ 一眼看出被换了
```

**书里建议把它放进 base_test**——不只调试重载，组件有没有创建、名字对不对、层次挂没挂错都能看出来。

### 排查"重载不生效"的顺序

```
1. factory.print(0)      → 重载记录在不在？
2. print_topology()      → 实际类型对不对？
3. 检查创建处            → 用了 new 而不是 type_id::create？（最常见）
4. 检查方法              → 是 virtual 吗？
5. 检查时机              → 在 create 之前设置的吗？
```

## 5. 常用重载场景

**同一个需求（构造 CRC 错误用例）有四种做法：**

### ① 写新 sequence（最直接）

```systemverilog
class abnormal_sequence extends uvm_sequence #(my_transaction);
  virtual task body();
    repeat (10) `uvm_do_with(m_trans, {m_trans.crc_err == 1;})
  endtask
endclass
```

### ② 重载 transaction（最简洁）

```systemverilog
class crc_err_tr extends my_transaction;
  constraint crc_err_cons { crc_err == 1; }      // ★ 约束重载
endclass

// test 里一行，sequence 完全不动
factory.set_type_override_by_type(my_transaction::get_type(), crc_err_tr::get_type());
```

**用正常 sequence 跑出了异常激励**——同时用到了**约束重载（SV）**和 **factory 重载（UVM）**。

### ③ 重载 sequence

```systemverilog
class abnormal_sequence extends normal_sequence;    // ★ 派生自 normal_sequence
  virtual task body(); ...异常激励... endtask
endclass

factory.set_type_override_by_type(normal_sequence::get_type(),
                                  abnormal_sequence::get_type());
```

**适合替换复杂嵌套结构中的某个子 sequence。**

### ④ 重载 driver（时序层面的异常）

```systemverilog
class crc_driver extends my_driver;
  virtual function void inject_crc_err(my_transaction tr);
    if ($urandom_range(10, 0) == 0) tr.crc = $urandom;
  endfunction

  virtual task main_phase(uvm_phase phase);
    while (1) begin
      seq_item_port.get_next_item(req);
      inject_crc_err(req);               // ★ 驱动前篡改
      drive_one_pkt(req);
      seq_item_port.item_done();
    end
  endtask
endclass
```

**优势场景**：包中途拉低 valid、违反协议时序、产生毛刺——这些是**驱动方式**的异常，sequence 管不到信号级时序。

**reference model 尤其适合重载**：

> DUT 80% 的代码可能都在处理异常。参考模型**拆成数十个、每个处理一种异常**，建立对应用例时重载掉正常的那个——代码清晰、可读性高。

### 四种方式对比

| 方式 | 适合 |
|---|---|
| 新 sequence | 激励模式完全不同 |
| **重载 transaction** | **数据内容**的异常（最简洁） |
| 重载 sequence | 替换复杂结构中的子 sequence |
| **重载 driver** | **驱动时序**的异常 |

### ⚠️ 不要只靠重载 driver

书里明确反对"放弃 sequence、全靠重载 driver"：

| 问题 | 说明 |
|---|---|
| 职能倒退 | 引入 sequence 就是为了剥离激励，绕回去等于退步 |
| 各有所长 | 有些用例 driver 方便，有些 sequence 方便 |
| **无法复用** | sequence 能嵌套复用，driver 只能把函数堆在基类里，**代码量恐怖** |
| 无法协调 | virtual sequence 能同步多接口，多 driver 之间很难 |

> **只有将 driver 的重载与 sequence 相结合，才与 UVM 的设计初衷相符。**

**原则**：数据层面用 sequence/transaction，时序层面用 driver 重载。

## 6. factory 的实现原理

### 问题：SV 不能按字符串创建对象

```systemverilog
string type_name = "my_driver";
// SV 没有这种能力，new 必须写死类名
```

但 `run_test("my_case0")` 恰恰这么做了。

### 解法：每个类配一个"代理"

`` `uvm_component_utils(my_driver) `` 展开后大致生成：

```systemverilog
typedef uvm_component_registry #(my_driver, "my_driver") type_id;
//                               └───┬───┘  └────┬────┘
//                              要创建的类    名字字符串

static function type_id get_type();
  return type_id::get();
endfunction
```

**这就是 `type_id` 和 `get_type()` 的来源。**

代理类内部：

```systemverilog
class uvm_component_registry #(type T, string Tname) extends uvm_object_wrapper;
  virtual function uvm_component create_component(string name, uvm_component parent);
    T obj;
    obj = new(name, parent);           // ★ 只有它知道 T，写死了 new T
    return obj;
  endfunction

  static function this_type get();
    if (me == null) begin
      me = new;
      factory.register(me);            // ★ 注册到 factory
    end
    return me;
  endfunction
endclass
```

### factory 内部是关联数组

```systemverilog
uvm_object_wrapper m_type_names[string];     // 名字 → 代理
```

```
┌──────────────┬────────────────────────────────────┐
│ "my_driver"  │ uvm_component_registry#(my_driver) │
│ "my_case0"   │ uvm_component_registry#(my_case0)  │
└──────────────┴────────────────────────────────────┘
```

### 按字符串创建的全过程

```
run_test("my_case0")
  ① 查表 m_type_names["my_case0"]
  ② 拿到代理
  ③ 调用代理的 create_component()
  ④ 代理内部执行 new my_case0(...)     ← 只有代理知道具体类型
```

**"写死类名"这件事被转移到了代理里**，而代理是宏自动生成的。

### 重载的实现：再加一张表

```
override 表:
┌──────────────┬──────────────┐
│ my_driver    │ crc_driver   │
└──────────────┴──────────────┘
```

`type_id::create` 先查 override 表（一直查到没记录），再调对应代理的 create。

### 这解释了所有规则

| 规则 | 原因 |
|---|---|
| 必须注册 | 不注册表里没有代理 |
| 必须用 `type_id::create` | `new` 绕过了查表 |
| 重载类必须是子类 | 返回的对象要赋给原类型的句柄 |
| 多级重载一直查下去 | override 表查到没记录为止 |
| component/object 不能互相重载 | 代理的 create 签名不同 |

### 本质

> **factory 的本质就是对 SystemVerilog 中 new 函数的重载。**

```
原生 SV：  new → 固定创建写死的那个类
factory：  type_id::create → 查表 → 可能创建任何一个注册过的子类
```

**把"创建哪个类"的决定从编译时推迟到运行时。**
