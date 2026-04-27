# Hivex Tools

Windows Registry Hive 和 BCD (Boot Configuration Data) 文件处理工具集。

## 功能

- Hive 文件解析和生成
- BCD Store 读取和编辑
- 注册表键值操作
- Hive 合并和差异比较
- BCD 模板生成

## 目录结构

```
src/tools/hivex/
├── root.zig              # 库导出入口
├── hive/                 # 底层 Hive 二进制格式
│   ├── header.zig        # Hive 文件头
│   ├── hbin.zig          # hbin 块结构
│   ├── cell.zig          # Cell 分配管理
│   ├── nk.zig            # NK Cell (命名键)
│   ├── vk.zig            # VK Cell (值键)
│   ├── sk.zig            # SK Cell (安全描述符)
│   ├── lf.zig            # LF/LH Cell (叶子索引)
│   ├── ri.zig            # RI Cell (根索引)
│   ├── db.zig            # DB Cell (大数据)
│   └── log.zig           # 事务日志
├── registry/             # 高层注册表语义
│   ├── key.zig           # 键操作
│   ├── value.zig         # 值操作
│   ├── tree.zig          # 树遍历
│   ├── query.zig         # 路径查询
│   ├── merge.zig         # 合并操作
│   └── diff.zig          # 差异比较
├── bcd/                  # BCD 专用层
│   ├── root.zig          # BCD 库入口
│   ├── store.zig         # BCD Store 管理
│   ├── object/            # BCD 对象
│   │   ├── object.zig     # 对象结构
│   │   ├── type.zig       # 对象类型
│   │   └── guid.zig       # GUID 处理
│   ├── element/           # BCD 元素
│   │   └── type.zig       # 元素类型
│   ├── parser/            # 解析器
│   │   ├── reader.zig      # 读取器
│   │   ├── writer.zig     # 写入器
│   │   ├── json.zig       # JSON 转换
│   │   └── text.zig       # 文本格式化
│   └── template/          # 模板
│       ├── windows.zig    # Windows 模板
│       ├── recovery.zig    # 恢复模板
│       └── zirconos.zig    # ZirconOS 模板
└── bin/                   # CLI 工具
    ├── bcd_dump.zig       # BCD 转储
    ├── bcd_edit.zig       # BCD 编辑
    ├── bcd_create.zig      # BCD 创建
    ├── hive_dump.zig       # Hive 转储
    ├── hive_merge.zig      # Hive 合并
    └── hive_diff.zig       # Hive 差异

tests/tools/hivex/
├── hive_test.zig          # Hive 格式测试
├── registry_test.zig      # 注册表测试
├── bcd_test.zig           # BCD 测试
├── bcd_object_test.zig    # BCD 对象测试
├── bcd_element_test.zig   # BCD 元素测试
├── bcd_parser_test.zig    # BCD 解析器测试
└── integration_test.zig   # 集成测试
```

## 使用方法

### 构建

```bash
zig build
```

### 运行测试

```bash
zig build test
```

### CLI 工具

#### BCD 工具

```bash
# 转储 BCD 内容
./bcd_dump -f /path/to/bcd

# 编辑 BCD
./bcd_edit -f /path/to/bcd --create <guid>

# 创建 BCD
./bcd_create -o output.bcd --windows
```

#### Hive 工具

```bash
# 转储 Hive 内容
./hive_dump -f /path/to/hive

# 合并 Hive
./hive_merge -s source.hive -d dest.hive -o merged.hive

# 比较 Hive 差异
./hive_diff -s old.hive -d new.hive
```

## 许可证

MIT License
