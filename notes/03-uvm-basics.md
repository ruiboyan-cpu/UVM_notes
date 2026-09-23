# 03 UVM 基础

> 对应《UVM实战》Ch3。component vs object、树形结构、field automation、打印控制、config_db 深入。

## 1. uvm_component 派生自 uvm_object

**不是并列关系，是继承关系**：

```
uvm_object
  ├── uvm_transaction
  │     └── uvm_sequence_item        ← 你的 transaction
  │           └── uvm_sequence_base
  │                 └── uvm_sequence #(T)   ← 你的 sequence
  └── uvm_component                  ← ★ component 也是 object！
        ├── uvm_driver #(T)
        ├── uvm_monitor
        ├── uvm_sequencer #(T)
        ├── uvm_agent
        ├── uvm_scoreboard
        ├── uvm_env
        └── uvm_test
```

**推论**：component 拥有 object 的所有能力（print/compare/copy、field automation），反之不成立。

### component 独有的两大特性

| 特性 | 说明 |
|---|---|
| **树形结构** | 靠 `new` 的 `parent` 参数组成 UVM 树 |
| **phase 自动执行** | 有 build/main 等，被框架自动调用 |

**只有 component 能成为 UVM 树的节点。** 这解释了：
- 为什么 component 构造函数要 `parent`，object 不要
- 为什么 sequence 没有 `main_phase`、只有 `body()`
- 为什么 sequence 要用 `starting_phase`（自己不在 phase 体系里）

### 书里的比喻

> `uvm_object` 是**分子**——`uvm_component` 是由分子搭成的**高级生命**，`sequence_item` 是流通其间的**血液**，`config` 是规范行为的**准则**。

### 各基类的实际内容

**大部分基类几乎什么都没做**——`uvm_monitor`、`uvm_scoreboard`、`uvm_env`、`uvm_test` 只是换了个名字：

```systemverilog
virtual class uvm_monitor extends uvm_component;
  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  const static string type_name = "uvm_monitor";
endclass
```

**真正做了扩展的只有两个**：

| 基类 | 扩展了 |
|---|---|
| `uvm_driver #(REQ, RSP)` | `seq_item_port`、`req`、`rsp` |
| `uvm_sequencer #(REQ, RSP)` | 大量 sequence 管理和仲裁机制 |

`uvm_agent` 只加了一个 `is_active`。**reference model 没有专门基类**，直接派生 `uvm_component`。

## 2. component 的限制：不能 clone

```systemverilog
my_driver drv2;
$cast(drv2, drv1.clone());     // ✗ 报错
```

**原因**：`clone()` 内部只调 `new(name)`（一个参数），但 component 需要 `new(name, parent)`——**没有 parent，克隆出来的挂在哪？**

UVM 源码直接报错：

```
create cannot be called on a uvm_component. Use copy or clone instead.
```

**实践中几乎不需要复制 component**——要复制的是 transaction（object），能 clone。

### clone vs copy

| | 谁 new |
|---|---|
| `b.copy(a)` | **你**——b 必须已 new 好 |
| `b = a.clone()` | **clone 自己** new 一个新的 |

⚠️ `clone()` 返回 `uvm_object`（基类），赋给具体类型要 `$cast`（向下转型）。

## 3. 二元结构：UVM 的设计哲学

| | **uvm_component** | **uvm_object** |
|---|---|---|
| 比喻 | **骨架 / 管道** | **血液 / 数据** |
| 生命周期 | 仿真全程 | 不断产生销毁 |
| 数量 | 固定 | 动态（成千上万） |
| 能 clone | ❌ | ✅ |

```
    ┌─────────┐        ┌──────────┐        ┌────────────┐
    │ driver  │ ──tr──►│   DUT    │ ──tr──►│ scoreboard │
    └─────────┘        └──────────┘        └────────────┘
     component            tr = object（流动的血液）
      骨架不动
```

**判断一个类该派生自谁**：需要一直存在、挂在树上、有 phase 吗？是→component，否→object。

### config 是什么

| | `config_db` | `config` |
|---|---|---|
| 是什么 | **机制**——全局配置表 | **一个 object 类**——装参数的容器 |

参数多了之后打包成一个 object 一次传完，比逐个 config_db 清爽。

## 4. UVM 树形结构

### 真正的根是 uvm_top

```
uvm_top（自动创建，名字 "__top__"，显示时省略）
   └── uvm_test_top（run_test 创建）
        └── env → i_agt → drv
```

**`uvm_top` 的用途**：启动 phase 机制、遍历整棵树、`uvm_top.print_topology()`。

**config_db 里 `null` 会被自动替换成 `uvm_top`**：

```systemverilog
::set(null,            "uvm_test_top.env.i_agt.drv", "vif", input_if);   // 等价
::set(uvm_root::get(), "uvm_test_top.env.i_agt.drv", "vif", input_if);
```

### 路径 ≠ 变量名

```systemverilog
my_driver drv;
drv = my_driver::type_id::create("driver", this);   // ★ 名字是 "driver"
// → 层次上是 env.i_agt.drv（按变量访问）
// → 路径是 env.i_agt.driver（config_db 要用这个）
```

**实践规则：变量名和 create 时的 name 保持一致。**

### 层次访问函数

| 函数 | 作用 |
|---|---|
| `get_full_name()` | 自己的完整路径 |
| `get_parent()` / `get_child("name")` | 父 / 子节点 |
| `get_first_child(name)` / `get_next_child(name)` | 遍历子节点 |

**最实用的**：

```systemverilog
function void end_of_elaboration_phase(uvm_phase phase);
  uvm_top.print_topology();      // ★ 打印整棵树，建议放进 base_test
endfunction
```

```
uvm_test_top      my_case0
  env             my_env
    i_agt         my_agent
      drv         my_driver
      mon         my_monitor
    o_agt         my_agent
      mon         new_monitor     ← 一眼看出被重载了
```

### 树形结构的三个好处

1. **路径寻址**——config_db 投递、报错信息定位
2. **phase 自动遍历**——不用手动调用任何组件的方法
3. **批量操作**——`_hier` 后缀的函数对整个子树生效

## 5. field automation

见 [02-build-testbench.md](02-build-testbench.md#12-field-automation) 的详细说明。核心要点：

- SV **没有反射**，所以要用 `uvm_field_*` 宏**登记清单**
- 自动生成 `copy`/`compare`/`print`/`pack_bytes` 等
- **打包顺序 = 登记顺序**，必须和协议一致
- 对 component 的价值：**自动从 config_db 取参数**（`super.build_phase` 负责）

### 宏里可以写 if（可变长度的包）

```systemverilog
`uvm_object_utils_begin(my_transaction)
  `uvm_field_int(dmac, UVM_ALL_ON)
  if (is_vlan) begin                           // ★ 宏里能写 if
    `uvm_field_int(vlan_info1, UVM_ALL_ON)
    ...
  end
  `uvm_field_int(is_vlan, UVM_ALL_ON | UVM_NOPACK)
`uvm_object_utils_end
```

**原理**：宏展开后是普通 SV 代码，if 也一起展开进去了。

## 6. 打印信息的控制

### 冗余度（verbosity）

```
UVM_NONE(0) < UVM_LOW(100) < UVM_MEDIUM(200) < UVM_HIGH(300) < UVM_FULL(400) < UVM_DEBUG(500)
                                 ↑ 默认阈值
```

**级别 ≤ 阈值才打印。** 只有 `` `uvm_info `` 受控，warning/error/fatal 总是打印。

```systemverilog
env.i_agt.drv.set_report_verbosity_level(UVM_HIGH);        // 单个组件
env.i_agt.set_report_verbosity_level_hier(UVM_HIGH);       // ★ _hier = 整个子树
env.i_agt.drv.set_report_id_verbosity("ID1", UVM_HIGH);    // 按 ID
```

```bash
./simv +UVM_VERBOSITY=UVM_HIGH        # ★ 最实用，不用改代码
```

⚠️ 涉及层次引用（`env.i_agt.drv`）的调用必须在 **`connect_phase` 或更晚**。

### action（打印时做什么）

```
UVM_NO_ACTION | UVM_DISPLAY | UVM_LOG | UVM_COUNT | UVM_EXIT | UVM_CALL_HOOK | UVM_STOP
```

**UVM 的默认设置**：

```systemverilog
set_severity_action(UVM_INFO,    UVM_DISPLAY);
set_severity_action(UVM_WARNING, UVM_DISPLAY);
set_severity_action(UVM_ERROR,   UVM_DISPLAY | UVM_COUNT);   // ★ 会计数
set_severity_action(UVM_FATAL,   UVM_DISPLAY | UVM_EXIT);    // ★ 会退出
```

**这解释了**：为什么 fatal 会终止仿真、为什么 report_phase 能统计错误数。

**可以覆盖**（注意用带 `report` 的版本）：

```systemverilog
env.i_agt.drv.set_report_severity_action(UVM_INFO, UVM_NO_ACTION);           // 彻底关闭
uvm_top.set_report_severity_action_hier(UVM_WARNING, UVM_DISPLAY | UVM_COUNT); // warning 也计数
```

### 错误数限制

```bash
./simv +UVM_MAX_QUIT_COUNT=5      # 出现 5 个 UVM_ERROR 就退出
```

### 输出到文件（三步缺一不可）

```systemverilog
log_file = $fopen("driver.log", "w");                             // ①
env.i_agt.drv.set_report_default_file(log_file);                  // ②
env.i_agt.drv.set_report_severity_action(UVM_INFO,
                                         UVM_DISPLAY | UVM_LOG);  // ③ ★ 不加 UVM_LOG 文件是空的
```

### 函数命名规律

```
set_report_ [severity|id|severity_id] _ [verbosity|action|file] _ [hier]
             └─── 按什么区分 ───┘        └─── 设什么 ───┘      └递归┘
```

### 实践中最常用的三个

```bash
+UVM_VERBOSITY=UVM_HIGH         # 调冗余度
+UVM_MAX_QUIT_COUNT=10          # 限制错误数
```

```systemverilog
`uvm_info("DRV_PKT", $sformatf("send pkt, size=%0d", tr.pload.size()), UVM_MEDIUM)
//          └──┬──┘  ★ 给 ID 起有意义的名字，比学会那堆函数更重要
```

### 即使不写任何 uvm_info

UVM 自己还会打印：`Running test xxx`、版本信息、**最后的 Report Summary**（判断测试是否通过的依据）。

`$display` 完全不受 UVM 控制——这也是推荐用 `` `uvm_info `` 的原因。

## 7. config_db 深入

### 跨层次多重设置：高层优先

```systemverilog
// my_case0 (uvm_test_top) 里
uvm_config_db#(int)::set(this, "env.i_agt.drv", "pre_num", 100);
// my_env 里
uvm_config_db#(int)::set(this, "i_agt.drv", "pre_num", 200);

// 结果：pre_num = 100（高层的赢）
```

**为什么**：让**测试用例能覆盖环境的默认配置**（和 factory override 同一思路）。

**同层次时：后设置的赢。**

### 通配符

```systemverilog
::set(this, "env.*.drv", "pre_num", 100);      // 所有 agent 下的 drv
::set(this, "*",         "pre_num", 100);      // 所有组件（★ 慎用）
```

### 调试

```systemverilog
check_config_usage();        // 检查哪些 set 没被 get 用到（路径/名字写错时）
```

```bash
./simv +UVM_CONFIG_DB_TRACE  # ★ 打印所有 set/get 过程
```

### 四个常见坑（症状都是 get 返回 0）

| 坑 | 排查 |
|---|---|
| field_name 拼错 | `+UVM_CONFIG_DB_TRACE` |
| 路径写错 | `uvm_top.print_topology()` 看真实路径 |
| 类型参数不一致（set 用 int、get 用 bit） | 检查 `#(T)` |
| create 的 name 和变量名不一致 | 保持一致 |

### 旧写法（OVM 遗留）

```systemverilog
set_config_int("env.i_agt.drv", "pre_num", 100);    // 旧，只支持 int/string/object
uvm_config_db#(int)::set(...);                       // ★ 新代码一律用这个
```
