# relay_control

# Linux Serial Relay Controller

一个用于 Linux 的 4 路串口继电器控制脚本。

该脚本支持两种运行方式：

1. **无参数启动 UI 图形界面**
2. **有参数时作为命令行工具执行，不打开 UI**

脚本文件名建议保存为：

```text
relay.sh
```

虽然文件名是 `.sh`，但脚本内容是 Python。

---

## 功能特性

- 自动扫描 `/dev/ttyUSB*` 串口设备
- 波特率固定为 `9600`
- 支持 4 路继电器控制
- 支持 UI 图形界面
- 支持命令行控制
- 支持命令行查询状态
- 支持指定串口
- 支持通过环境变量指定串口
- UI 中支持多选继电器
- UI 中显示继电器状态灯
- UI 串口操作使用后台队列，界面不会卡住
- 执行任务期间仍可继续选择继电器

---

## 运行环境

支持常见 Linux 桌面环境，例如：

- Ubuntu
- Debian
- Linux Mint
- Raspberry Pi OS
- Fedora
- Arch Linux

脚本只扫描：

```text
/dev/ttyUSB*
```

例如：

```text
/dev/ttyUSB0
/dev/ttyUSB1
```

如果设备是 `/dev/ttyACM0`，当前脚本不会自动显示，需要修改脚本中的 `find_ports()`。

---

## 依赖安装

### Ubuntu / Debian / Linux Mint

```bash
sudo apt update
sudo apt install python3 python3-tk
```

### Fedora / Rocky / CentOS

```bash
sudo dnf install python3 python3-tkinter
```

旧版本系统：

```bash
sudo yum install python3 python3-tkinter
```

### Arch Linux

```bash
sudo pacman -S python tk
```

---

## 串口权限配置

普通用户默认可能没有权限访问 `/dev/ttyUSB0`。

查看权限：

```bash
ls -l /dev/ttyUSB0
```

常见输出类似：

```text
crw-rw---- 1 root dialout ... /dev/ttyUSB0
```

将当前用户加入 `dialout` 组：

```bash
sudo usermod -aG dialout $USER
```

然后注销并重新登录。

确认：

```bash
groups
```

输出中应包含：

```text
dialout
```

不要用 `sudo` 启动 UI，否则可能出现：

```text
Failed to open display
```

---

## 安装脚本

保存脚本为：

```bash
relay.sh
```

添加执行权限：

```bash
chmod +x relay.sh
```

---

## 使用方式

## 1. 打开 UI

无参数运行时打开图形界面：

```bash
./relay.sh
```

UI 中可以：

- 选择串口
- 多选 Relay 1 到 Relay 4
- 打开选中的继电器
- 关闭选中的继电器
- 查询状态
- 查看操作日志

---

## 2. 命令行控制继电器

当只有一个 `/dev/ttyUSB*` 设备时，可以直接执行：

```bash
./relay.sh 1 on
./relay.sh 1 off
./relay.sh 2 on
./relay.sh 2 off
./relay.sh 3 on
./relay.sh 3 off
./relay.sh 4 on
./relay.sh 4 off
```

参数格式：

```bash
./relay.sh 1|2|3|4 on|off
```

示例输出：

```text
OK
Port: /dev/ttyUSB0
Relay: 1
Action: ON
TX HEX: A0 01 01 A2
```

---

## 3. 命令行查询状态

查询当前继电器状态：

```bash
./relay.sh status
```

示例输出：

```text
Port: /dev/ttyUSB0
CH1: OFF
CH2: OFF
CH3: ON
CH4: OFF
```

---

## 4. 指定串口执行

如果系统中有多个 `/dev/ttyUSB*`，需要指定串口。

控制继电器：

```bash
./relay.sh /dev/ttyUSB0 1 on
./relay.sh /dev/ttyUSB0 1 off
```

查询状态：

```bash
./relay.sh /dev/ttyUSB0 status
```

---

## 5. 使用环境变量指定串口

也可以通过 `RELAY_PORT` 指定串口。

控制继电器：

```bash
RELAY_PORT=/dev/ttyUSB0 ./relay.sh 1 on
RELAY_PORT=/dev/ttyUSB0 ./relay.sh 1 off
```

查询状态：

```bash
RELAY_PORT=/dev/ttyUSB0 ./relay.sh status
```

---

## UI 界面说明

### Serial Port

串口选择下拉框。

- 只有一个 `/dev/ttyUSB*` 时，自动选择并查询状态
- 有多个 `/dev/ttyUSB*` 时，需要手动选择
- 手动选择串口后，会自动查询状态

### Refresh

重新扫描 `/dev/ttyUSB*`。

### Baud Rate

固定为：

```text
9600
```

### Task State

显示后台任务状态。

可能显示：

```text
Ready
```

表示空闲。

```text
Running
```

表示正在执行任务。

```text
Waiting tasks: N
```

表示还有 `N` 个任务等待执行。

---

## Relay Selection

继电器选择区域包含：

- Relay 1
- Relay 2
- Relay 3
- Relay 4
- Select All
- Clear
- 状态灯说明

可以同时选择多个继电器，然后统一打开或关闭。

点击 `Turn ON Selected` 或 `Turn OFF Selected` 后，选择框会立即清空，方便继续选择下一组继电器。

---

## 状态灯说明

| 颜色 | 状态 | 含义 |
|---|---|---|
| 绿色 | `ON` | 继电器导通 |
| 灰色 | `OFF` | 继电器断开 |
| 黄色 | `UNKNOWN` | 状态未知 |

---

## UI 操作按钮

### Turn ON Selected

打开当前选中的继电器。

### Turn OFF Selected

关闭当前选中的继电器。

### Query Status

发送 `FF` 查询当前继电器状态。

---

## 串口通信协议

### 串口参数

```text
Baud Rate: 9600
Data Bits: 8
Parity: None
Stop Bits: 1
```

### 控制指令

| 操作 | HEX |
|---|---|
| 打开 1 | `A0 01 01 A2` |
| 关闭 1 | `A0 01 00 A1` |
| 打开 2 | `A0 02 01 A3` |
| 关闭 2 | `A0 02 00 A2` |
| 打开 3 | `A0 03 01 A4` |
| 关闭 3 | `A0 03 00 A3` |
| 打开 4 | `A0 04 01 A5` |
| 关闭 4 | `A0 04 00 A4` |

### 状态查询

发送：

```text
FF
```

设备返回格式：

```text
CH1: OFF
CH2: OFF
CH3: OFF
CH4: OFF
```

或：

```text
CH1: ON
CH2: OFF
CH3: ON
CH4: OFF
```

---

## 自动查询逻辑

UI 模式下会在以下场景自动查询状态：

1. 程序启动后
   - 如果只有一个 `/dev/ttyUSB*`，自动选择并查询
   - 如果有多个 `/dev/ttyUSB*`，等待用户手动选择
2. 用户手动选择串口后
3. 每次打开或关闭继电器后

---

## 后台任务队列

UI 中的串口操作通过后台线程执行。

效果：

- 操作串口时界面不会卡住
- 执行期间复选框仍可选择
- 新任务会进入队列
- 串口任务不会并发执行
- 后一个任务会等待前一个任务完成

---

## Operation Log

`Operation Log` 显示：

- 程序启动信息
- 串口扫描结果
- 任务入队信息
- 发送 HEX
- 接收 HEX
- 接收文本
- 状态解析结果
- 错误信息

示例：

```text
[10:20:01] Program started
[10:20:01] Baud rate: 9600
[10:20:01] Port filter: /dev/ttyUSB*
[10:20:02] Query status (startup), TX HEX: FF
[10:20:03] RX TEXT:
[10:20:03]   CH1: OFF
[10:20:03]   CH2: OFF
[10:20:03]   CH3: OFF
[10:20:03]   CH4: OFF
[10:20:03] Parsed status: CH1:OFF, CH2:OFF, CH3:OFF, CH4:OFF
```

---

## 命令行退出码

| 退出码 | 含义 |
|---|---|
| `0` | 执行成功 |
| `1` | 执行失败，例如无权限、无响应、串口不存在 |
| `2` | 参数错误 |

---

## 常见问题

### 没有串口显示

检查设备：

```bash
ls /dev/ttyUSB*
```

查看系统日志：

```bash
dmesg | grep ttyUSB
```

### 权限不足

错误示例：

```text
Permission denied
```

解决：

```bash
sudo usermod -aG dialout $USER
```

注销并重新登录。

临时解决：

```bash
sudo chmod 666 /dev/ttyUSB0
```

### 多个 ttyUSB 设备时报错

命令行模式下，如果有多个 `/dev/ttyUSB*`，脚本不会自动选择。

请指定串口：

```bash
./relay.sh /dev/ttyUSB0 1 on
```

或：

```bash
RELAY_PORT=/dev/ttyUSB0 ./relay.sh 1 on
```

### 状态一直是 UNKNOWN

可能原因：

- 串口选错
- 设备没有响应 `FF`
- 波特率不对
- 返回格式不是 `CH1: OFF` 这种格式

请查看 UI 的 `Operation Log`，或命令行执行：

```bash
./relay.sh status
```

---

## 快速示例

打开 UI：

```bash
./relay.sh
```

打开 Relay 1：

```bash
./relay.sh 1 on
```

关闭 Relay 1：

```bash
./relay.sh 1 off
```

查询状态：

```bash
./relay.sh status
```

指定串口打开 Relay 2：

```bash
./relay.sh /dev/ttyUSB0 2 on
```

指定串口查询状态：

```bash
./relay.sh /dev/ttyUSB0 status
```

