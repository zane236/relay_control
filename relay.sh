#!/usr/bin/env python3
import glob
import os
import sys
import time
import select
import termios
import queue
import threading
import tkinter as tk
from tkinter import ttk, messagebox
from datetime import datetime

BAUD_RATE = 9600

COMMANDS = {
    (1, "on"):  bytes([0xA0, 0x01, 0x01, 0xA2]),
    (1, "off"): bytes([0xA0, 0x01, 0x00, 0xA1]),

    (2, "on"):  bytes([0xA0, 0x02, 0x01, 0xA3]),
    (2, "off"): bytes([0xA0, 0x02, 0x00, 0xA2]),

    (3, "on"):  bytes([0xA0, 0x03, 0x01, 0xA4]),
    (3, "off"): bytes([0xA0, 0x03, 0x00, 0xA3]),

    (4, "on"):  bytes([0xA0, 0x04, 0x01, 0xA5]),
    (4, "off"): bytes([0xA0, 0x04, 0x00, 0xA4]),
}

QUERY_COMMAND = bytes([0xFF])


def find_ports():
    return sorted(glob.glob("/dev/ttyUSB*"))


def bytes_to_hex(data):
    return " ".join(f"{b:02X}" for b in data)


def baud_to_termios_speed(baud):
    baud_map = {
        9600: termios.B9600,
        19200: termios.B19200,
        38400: termios.B38400,
        57600: termios.B57600,
        115200: termios.B115200,
    }
    return baud_map.get(baud, termios.B9600)


def configure_fd(fd):
    attrs = termios.tcgetattr(fd)

    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CLOCAL | termios.CREAD
    attrs[3] = 0

    speed = baud_to_termios_speed(BAUD_RATE)
    attrs[4] = speed
    attrs[5] = speed

    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 10

    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)


def send_raw(port, data, read_response=False, timeout=1.5):
    fd = None

    try:
        fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        configure_fd(fd)

        os.write(fd, data)
        termios.tcdrain(fd)

        if not read_response:
            return b""

        response = b""
        end_time = time.time() + timeout

        while time.time() < end_time:
            readable, _, _ = select.select([fd], [], [], 0.1)

            if fd in readable:
                try:
                    chunk = os.read(fd, 1024)
                    if chunk:
                        response += chunk
                except BlockingIOError:
                    pass

        return response

    finally:
        if fd is not None:
            os.close(fd)


def parse_status_text(text):
    parsed = {}

    lines = text.replace("\r", "\n").split("\n")

    for line in lines:
        line = line.strip().upper()

        if not line:
            continue

        for ch in range(1, 5):
            prefix = f"CH{ch}:"

            if line.startswith(prefix):
                value = line[len(prefix):].strip()

                if value.startswith("ON"):
                    parsed[ch] = "ON"
                elif value.startswith("OFF"):
                    parsed[ch] = "OFF"

    return parsed


def resolve_command_port(explicit_port=None):
    if explicit_port:
        if not os.path.exists(explicit_port):
            raise RuntimeError(f"Serial port does not exist: {explicit_port}")
        return explicit_port

    env_port = os.environ.get("RELAY_PORT", "").strip()
    if env_port:
        if not os.path.exists(env_port):
            raise RuntimeError(f"RELAY_PORT does not exist: {env_port}")
        return env_port

    default_port = "/dev/ttyUSB0"
    if not os.path.exists(default_port):
        raise RuntimeError(f"Default serial port does not exist: {default_port}")
    return default_port


def print_usage():
    print("Usage:")
    print("  ./relay.sh")
    print("      Open UI")
    print("")
    print("  ./relay.sh 1|2|3|4 on|off")
    print("      Control relay using default port /dev/ttyUSB0")
    print("")
    print("  ./relay.sh status")
    print("      Query relay status using default port /dev/ttyUSB0")
    print("")
    print("  ./relay.sh /dev/ttyUSB0 1|2|3|4 on|off")
    print("      Control relay using specified serial port")
    print("")
    print("  ./relay.sh /dev/ttyUSB0 status")
    print("      Query relay status using specified serial port")
    print("")
    print("  RELAY_PORT=/dev/ttyUSB0 ./relay.sh 1|2|3|4 on|off")
    print("      Control relay using RELAY_PORT")
    print("")
    print("  RELAY_PORT=/dev/ttyUSB0 ./relay.sh status")
    print("      Query relay status using RELAY_PORT")


def run_status_mode(explicit_port=None):
    try:
        port = resolve_command_port(explicit_port)

        response = send_raw(
            port,
            QUERY_COMMAND,
            read_response=True,
            timeout=1.5
        )

        print(f"Port: {port}")

        if not response:
            print("Error: No response received", file=sys.stderr)
            return 1

        text = response.decode("ascii", errors="ignore")
        parsed = parse_status_text(text)

        if parsed:
            for ch in range(1, 5):
                print(f"CH{ch}: {parsed.get(ch, 'UNKNOWN')}")
            return 0

        print(text.strip())
        return 1

    except PermissionError:
        print("Permission denied.", file=sys.stderr)
        print("Run:", file=sys.stderr)
        print("  sudo usermod -aG dialout $USER", file=sys.stderr)
        print("Then log out and log in again.", file=sys.stderr)
        return 1

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


def run_command_mode(argv):
    explicit_port = None

    if len(argv) == 1 and argv[0].lower() == "status":
        return run_status_mode()

    if len(argv) == 2 and argv[1].lower() == "status":
        explicit_port = argv[0]
        return run_status_mode(explicit_port)

    if len(argv) == 2:
        channel_text = argv[0]
        action = argv[1].lower()

    elif len(argv) == 3:
        explicit_port = argv[0]
        channel_text = argv[1]
        action = argv[2].lower()

    else:
        print_usage()
        return 2

    try:
        channel = int(channel_text)
    except ValueError:
        print(f"Invalid relay channel: {channel_text}", file=sys.stderr)
        return 2

    if channel not in [1, 2, 3, 4]:
        print("Relay channel must be 1, 2, 3, or 4", file=sys.stderr)
        return 2

    if action not in ["on", "off"]:
        print("Action must be on or off", file=sys.stderr)
        return 2

    try:
        port = resolve_command_port(explicit_port)
        data = COMMANDS[(channel, action)]

        send_raw(port, data)

        print("OK")
        print(f"Port: {port}")
        print(f"Relay: {channel}")
        print(f"Action: {action.upper()}")
        print(f"TX HEX: {bytes_to_hex(data)}")

        return 0

    except PermissionError:
        print("Permission denied.", file=sys.stderr)
        print("Run:", file=sys.stderr)
        print("  sudo usermod -aG dialout $USER", file=sys.stderr)
        print("Then log out and log in again.", file=sys.stderr)
        return 1

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


class LargeCheckBox(tk.Frame):
    def __init__(self, parent, text, variable, command=None):
        super().__init__(parent)

        self.variable = variable
        self.command = command

        self.canvas = tk.Canvas(
            self,
            width=34,
            height=34,
            highlightthickness=0,
            bg=self.cget("bg")
        )
        self.canvas.pack(side="left", padx=(0, 6))

        self.label = tk.Label(
            self,
            text=text,
            font=("Arial", 13),
            bg=self.cget("bg")
        )
        self.label.pack(side="left")

        self.canvas.bind("<Button-1>", self.toggle)
        self.label.bind("<Button-1>", self.toggle)
        self.bind("<Button-1>", self.toggle)

        self.draw()

    def toggle(self, event=None):
        self.variable.set(not self.variable.get())
        self.draw()

        if self.command:
            self.command()

    def draw(self):
        self.canvas.delete("all")

        self.canvas.create_rectangle(
            4,
            4,
            30,
            30,
            outline="#333333",
            width=2,
            fill="#ffffff"
        )

        if self.variable.get():
            self.canvas.create_line(
                9,
                17,
                15,
                24,
                26,
                10,
                fill="#0078d4",
                width=4,
                capstyle="round",
                joinstyle="round"
            )


class RelayUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Linux Relay Control")
        self.root.geometry("760x570")
        self.root.resizable(False, False)

        self.port_var = tk.StringVar()
        self.last_status_var = tk.StringVar(value="Last Status: starting...")
        self.busy_var = tk.StringVar(value="Ready")

        self.relay_vars = {
            1: tk.BooleanVar(value=False),
            2: tk.BooleanVar(value=False),
            3: tk.BooleanVar(value=False),
            4: tk.BooleanVar(value=False),
        }

        self.relay_state_vars = {
            1: tk.StringVar(value="UNKNOWN"),
            2: tk.StringVar(value="UNKNOWN"),
            3: tk.StringVar(value="UNKNOWN"),
            4: tk.StringVar(value="UNKNOWN"),
        }

        self.large_checkboxes = {}
        self.lamp_canvases = {}
        self.lamp_items = {}
        self.log_text = None

        self.task_queue = queue.Queue()
        self.stop_worker = False
        self.worker_thread = threading.Thread(target=self.worker_loop, daemon=True)

        self.build_ui()
        self.refresh_ports()

        self.worker_thread.start()

        self.log("Program started")
        self.log("Baud rate: 9600")
        self.log("Port filter: /dev/ttyUSB*")

        self.root.after(500, self.auto_query_status)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

    def build_ui(self):
        main = ttk.Frame(self.root, padding=16)
        main.pack(fill="both", expand=True)

        title = ttk.Label(main, text="Serial Relay Control", font=("Arial", 16, "bold"))
        title.pack(pady=(0, 14))

        port_frame = ttk.Frame(main)
        port_frame.pack(fill="x", pady=5)

        ttk.Label(port_frame, text="Serial Port:", width=14).pack(side="left")

        self.port_combo = ttk.Combobox(
            port_frame,
            textvariable=self.port_var,
            width=35,
            state="readonly"
        )
        self.port_combo.pack(side="left", padx=5)
        self.port_combo.bind("<<ComboboxSelected>>", self.on_port_selected)

        ttk.Button(port_frame, text="Refresh", command=self.refresh_ports).pack(side="left", padx=5)

        baud_frame = ttk.Frame(main)
        baud_frame.pack(fill="x", pady=5)

        ttk.Label(baud_frame, text="Baud Rate:", width=14).pack(side="left")
        ttk.Label(baud_frame, text=str(BAUD_RATE)).pack(side="left", padx=5)

        busy_frame = ttk.Frame(main)
        busy_frame.pack(fill="x", pady=5)

        ttk.Label(busy_frame, text="Task State:", width=14).pack(side="left")
        ttk.Label(busy_frame, textvariable=self.busy_var).pack(side="left", padx=5)

        relay_frame = ttk.LabelFrame(main, text="Relay Selection")
        relay_frame.pack(fill="x", pady=12)

        relay_left = ttk.Frame(relay_frame)
        relay_left.pack(side="left", fill="both", expand=True, padx=(12, 6), pady=10)

        relay_right = ttk.Frame(relay_frame)
        relay_right.pack(side="right", fill="y", padx=(6, 16), pady=10)

        relay_grid = ttk.Frame(relay_left)
        relay_grid.pack(fill="x")

        for ch in range(1, 5):
            item = ttk.Frame(relay_grid, padding=8)
            item.grid(row=0, column=ch - 1, padx=10, sticky="n")

            large_check = LargeCheckBox(
                item,
                text=f"Relay {ch}",
                variable=self.relay_vars[ch]
            )
            large_check.pack(pady=(0, 8))
            self.large_checkboxes[ch] = large_check

            canvas = tk.Canvas(
                item,
                width=42,
                height=42,
                highlightthickness=0,
                bg=self.root.cget("bg")
            )
            canvas.pack()

            lamp = canvas.create_oval(
                6,
                6,
                36,
                36,
                fill="#f0c000",
                outline="#555555",
                width=2
            )

            self.lamp_canvases[ch] = canvas
            self.lamp_items[ch] = lamp

            status_label = ttk.Label(
                item,
                textvariable=self.relay_state_vars[ch],
                width=8,
                anchor="center"
            )
            status_label.pack(pady=(6, 0))

        select_frame = ttk.Frame(relay_left)
        select_frame.pack(fill="x", pady=(10, 0))

        ttk.Button(select_frame, text="Select All", command=self.select_all).pack(side="left", padx=5)
        ttk.Button(select_frame, text="Clear", command=self.clear_all).pack(side="left", padx=5)

        ttk.Label(
            relay_right,
            text="Status",
            font=("Arial", 11, "bold")
        ).pack(anchor="w", pady=(0, 8))

        self.create_legend_lamp_vertical(relay_right, "#00c853", "ON")
        self.create_legend_lamp_vertical(relay_right, "#9e9e9e", "OFF")
        self.create_legend_lamp_vertical(relay_right, "#f0c000", "UNKNOWN")

        button_frame = ttk.Frame(main)
        button_frame.pack(fill="x", pady=12)

        self.open_button = tk.Button(
            button_frame,
            text="Turn ON Selected",
            width=17,
            height=2,
            bg="#77dd77",
            command=lambda: self.operate_selected("on")
        )
        self.open_button.pack(side="left", padx=(20, 10))

        self.close_button = tk.Button(
            button_frame,
            text="Turn OFF Selected",
            width=17,
            height=2,
            bg="#ff9999",
            command=lambda: self.operate_selected("off")
        )
        self.close_button.pack(side="left", padx=10)

        self.query_button = tk.Button(
            button_frame,
            text="Query Status",
            width=15,
            height=2,
            bg="#99ccff",
            command=self.query_status
        )
        self.query_button.pack(side="left", padx=10)

        log_frame = ttk.LabelFrame(main, text="Operation Log")
        log_frame.pack(fill="both", expand=True, pady=(8, 0))

        self.log_text = tk.Text(
            log_frame,
            height=8,
            wrap="word",
            state="normal",
            bg="white",
            fg="black",
            insertbackground="black"
        )
        self.log_text.pack(side="left", fill="both", expand=True, padx=(8, 0), pady=8)

        scrollbar = ttk.Scrollbar(log_frame, command=self.log_text.yview)
        scrollbar.pack(side="right", fill="y", pady=8)

        self.log_text.configure(yscrollcommand=scrollbar.set)

        bottom_status = ttk.Label(
            main,
            textvariable=self.last_status_var,
            anchor="w"
        )
        bottom_status.pack(fill="x", pady=(8, 0))

    def create_legend_lamp_vertical(self, parent, color, text):
        row = ttk.Frame(parent)
        row.pack(anchor="w", pady=5)

        canvas = tk.Canvas(
            row,
            width=22,
            height=22,
            highlightthickness=0,
            bg=self.root.cget("bg")
        )
        canvas.pack(side="left", padx=(0, 6))
        canvas.create_oval(4, 4, 18, 18, fill=color, outline="#555555")

        ttk.Label(row, text=text).pack(side="left")

    def ui_call(self, func, *args, **kwargs):
        self.root.after(0, lambda: func(*args, **kwargs))

    def log(self, message):
        now = datetime.now().strftime("%H:%M:%S")
        line = f"[{now}] {message}"

        self.last_status_var.set(f"Last Status: {message}")

        if self.log_text is not None:
            self.log_text.configure(state="normal")
            self.log_text.insert("end", line + "\n")
            self.log_text.see("end")
            self.log_text.configure(state="normal")

        self.root.update_idletasks()

    def thread_log(self, message):
        self.ui_call(self.log, message)

    def set_busy(self, text):
        self.busy_var.set(text)

    def thread_set_busy(self, text):
        self.ui_call(self.set_busy, text)

    def set_relay_state(self, ch, state):
        state = state.upper()

        if state == "ON":
            color = "#00c853"
            text = "ON"
        elif state == "OFF":
            color = "#9e9e9e"
            text = "OFF"
        else:
            color = "#f0c000"
            text = "UNKNOWN"

        self.relay_state_vars[ch].set(text)

        if ch in self.lamp_canvases and ch in self.lamp_items:
            self.lamp_canvases[ch].itemconfig(self.lamp_items[ch], fill=color)

    def thread_set_relay_state(self, ch, state):
        self.ui_call(self.set_relay_state, ch, state)

    def refresh_ports(self):
        old_port = self.port_var.get()
        ports = find_ports()

        self.port_combo["values"] = ports

        if old_port in ports:
            self.port_var.set(old_port)
            self.log(f"Keep selected port: {old_port}")

        elif len(ports) == 1:
            self.port_var.set(ports[0])
            self.log(f"Found one port, auto selected: {ports[0]}")

        elif len(ports) > 1:
            self.port_var.set("")
            self.log(f"Found multiple ports: {', '.join(ports)}")
            self.log("Please select one serial port manually")

        else:
            self.port_var.set("")
            self.log("No /dev/ttyUSB* device found")

    def on_port_selected(self, event=None):
        port = self.port_var.get()

        if not port:
            return

        self.log(f"Serial port selected: {port}")
        self.enqueue_query(port, source="port selected")

    def auto_query_status(self):
        port = self.port_var.get()

        if not port:
            self.log("Auto query skipped: no serial port selected")
            return

        self.enqueue_query(port, source="startup")

    def select_all(self):
        for ch in range(1, 5):
            self.relay_vars[ch].set(True)
            self.large_checkboxes[ch].draw()
        self.log("Selected all relays")

    def clear_all(self):
        for ch in range(1, 5):
            self.relay_vars[ch].set(False)
            self.large_checkboxes[ch].draw()
        self.log("Cleared relay selection")

    def get_selected_relays(self):
        return [ch for ch in range(1, 5) if self.relay_vars[ch].get()]

    def check_port(self, show_popup=True):
        port = self.port_var.get()

        if not port:
            if show_popup:
                messagebox.showerror("Error", "Please select serial port")
            self.log("No serial port selected")
            return None

        if not os.path.exists(port):
            if show_popup:
                messagebox.showerror("Error", f"Serial port does not exist: {port}")
            self.log(f"Serial port does not exist: {port}")
            self.refresh_ports()
            return None

        return port

    def enqueue_task(self, task):
        self.task_queue.put(task)
        self.log(f"Task queued: {task['type']}")

    def enqueue_query(self, port, source="manual"):
        self.enqueue_task({
            "type": "query",
            "port": port,
            "source": source,
        })

    def query_status(self, show_popup=True):
        port = self.check_port(show_popup=show_popup)
        if not port:
            return

        self.enqueue_query(port, source="manual")

    def operate_selected(self, action):
        port = self.check_port()
        if not port:
            return

        selected = self.get_selected_relays()

        if not selected:
            messagebox.showwarning("Info", "Please select at least one relay")
            self.log("Operation cancelled: no relay selected")
            return

        action_text = "ON" if action == "on" else "OFF"

        self.enqueue_task({
            "type": "operate",
            "port": port,
            "action": action,
            "action_text": action_text,
            "selected": selected,
        })

        self.clear_all()

    def worker_loop(self):
        while not self.stop_worker:
            try:
                task = self.task_queue.get(timeout=0.2)
            except queue.Empty:
                continue

            try:
                self.thread_set_busy("Running")

                if task["type"] == "operate":
                    self.worker_operate(task)
                elif task["type"] == "query":
                    self.worker_query(task["port"], task.get("source", "manual"))

            except PermissionError:
                self.thread_log("Permission denied")
            except Exception as e:
                self.thread_log(f"Task failed: {e}")

            finally:
                self.task_queue.task_done()

                if self.task_queue.empty():
                    self.thread_set_busy("Ready")
                else:
                    self.thread_set_busy(f"Waiting tasks: {self.task_queue.qsize()}")

    def worker_operate(self, task):
        port = task["port"]
        action = task["action"]
        action_text = task["action_text"]
        selected = task["selected"]

        self.thread_log(f"Start operation: {action_text} relay(s) {selected}")

        for ch in selected:
            data = COMMANDS[(ch, action)]
            send_raw(port, data)

            hex_text = bytes_to_hex(data)
            self.thread_set_relay_state(ch, action_text)
            self.thread_log(f"Relay {ch} -> {action_text}, TX HEX: {hex_text}")

            time.sleep(0.08)

        self.thread_log(f"Operation done: {action_text} {len(selected)} relay(s)")
        self.worker_query(port, source="after operation")

    def worker_query(self, port, source="manual"):
        if not os.path.exists(port):
            self.thread_log(f"Query skipped, port does not exist: {port}")
            return

        self.thread_log(f"Query status ({source}), TX HEX: FF")

        response = send_raw(
            port,
            QUERY_COMMAND,
            read_response=True,
            timeout=1.5
        )

        if not response:
            self.thread_log("No response received")
            return

        hex_text = bytes_to_hex(response)
        self.thread_log(f"RX HEX: {hex_text}")

        text = response.decode("ascii", errors="ignore")
        text_clean = text.strip()

        if text_clean:
            self.thread_log("RX TEXT:")
            for line in text_clean.splitlines():
                self.thread_log(f"  {line}")

        parsed = parse_status_text(text)

        if not parsed:
            self.thread_log("Status parse failed")
            return

        for ch in range(1, 5):
            if ch in parsed:
                self.thread_set_relay_state(ch, parsed[ch])
            else:
                self.thread_set_relay_state(ch, "UNKNOWN")

        summary = ", ".join(
            f"CH{ch}:{parsed.get(ch, 'UNKNOWN')}"
            for ch in range(1, 5)
        )

        self.thread_log(f"Parsed status: {summary}")

    def on_close(self):
        self.stop_worker = True
        self.root.destroy()


def run_ui_mode():
    root = tk.Tk()
    app = RelayUI(root)
    root.mainloop()


def main():
    if len(sys.argv) == 1:
        run_ui_mode()
        return 0

    return run_command_mode(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
