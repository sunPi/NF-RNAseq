#!/usr/bin/env python3
"""Local desktop launcher for NF-RNAseq."""

from pathlib import Path
import queue
import shlex
import subprocess
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from ui_model import ROOT, available_modules, build_command


class Launcher(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("NF-RNAseq")
        self.geometry("900x760")
        self.minsize(700, 600)
        self.process = None
        self.events = queue.Queue()
        self.project = tk.StringVar()
        self.assembly = tk.StringVar(value="GRCh38")
        self.layout = tk.StringVar(value="paired")
        self.mode = tk.StringVar(value="core")
        self.input_dir = tk.StringVar()
        self.design = tk.StringVar()
        self.status = tk.StringVar(value="Ready")
        self.module_flags = {}
        self._build()
        self._update_mode()
        self.protocol("WM_DELETE_WINDOW", self._close)
        self.after(100, self._drain_events)

    def _build(self):
        outer = ttk.Frame(self, padding=16)
        outer.pack(fill="both", expand=True)
        ttk.Label(outer, text="Welcome to NF-RNAseq", font=("TkDefaultFont", 19, "bold")).pack(anchor="w")
        ttk.Label(outer, text="Run bulk RNA-seq core processing or analyses for a named project. "
                  "Each project keeps its results in a separate folder.", wraplength=820).pack(anchor="w", pady=(4, 14))

        form = ttk.Frame(outer)
        form.pack(fill="x")
        for col in (1, 3):
            form.columnconfigure(col, weight=1)
        ttk.Label(form, text="Project name").grid(row=0, column=0, sticky="w", pady=4)
        existing = sorted(p.name for p in (ROOT / "results").iterdir() if p.is_dir()) if (ROOT / "results").is_dir() else []
        ttk.Combobox(form, textvariable=self.project, values=existing).grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Label(form, text="Assembly").grid(row=0, column=2, sticky="w")
        ttk.Combobox(form, textvariable=self.assembly, values=("GRCh38", "GRCh37", "hg38", "hg19"), state="readonly").grid(row=0, column=3, sticky="ew")
        ttk.Label(form, text="Read layout").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Combobox(form, textvariable=self.layout, values=("paired", "single"), state="readonly").grid(row=1, column=1, sticky="ew", padx=8)
        ttk.Label(form, text="What to run").grid(row=1, column=2, sticky="w")
        ttk.Combobox(form, textvariable=self.mode, values=("core", "optional", "modules"), state="readonly").grid(row=1, column=3, sticky="ew")
        self.mode.trace_add("write", lambda *_: self._update_mode())

        ttk.Label(form, text="FASTQ input folder").grid(row=2, column=0, sticky="w", pady=4)
        self.input_entry = ttk.Entry(form, textvariable=self.input_dir)
        self.input_entry.grid(row=2, column=1, columnspan=2, sticky="ew", padx=8)
        self.input_button = ttk.Button(form, text="Browse…", command=lambda: self._browse_directory(self.input_dir))
        self.input_button.grid(row=2, column=3, sticky="ew")
        ttk.Label(form, text="Design TSV/CSV").grid(row=3, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.design).grid(row=3, column=1, columnspan=2, sticky="ew", padx=8)
        ttk.Button(form, text="Browse…", command=self._browse_design).grid(row=3, column=3, sticky="ew")

        ttk.Label(outer, text="Contrasts (one FACTOR:NUMERATOR:DENOMINATOR per line)").pack(anchor="w", pady=(12, 2))
        self.contrasts = tk.Text(outer, height=3)
        self.contrasts.pack(fill="x")
        ttk.Label(outer, text="Optional modules").pack(anchor="w", pady=(12, 2))
        module_frame = ttk.Frame(outer)
        module_frame.pack(fill="x")
        for index, module in enumerate(available_modules()):
            flag = tk.BooleanVar()
            self.module_flags[module.name] = flag
            suffix = " (design + contrast)" if module.requires_contrast else ""
            ttk.Checkbutton(module_frame, text=module.name + suffix, variable=flag).grid(
                row=index // 3, column=index % 3, sticky="w", padx=(0, 20), pady=2)

        actions = ttk.Frame(outer)
        actions.pack(fill="x", pady=(15, 6))
        ttk.Button(actions, text="Preview command", command=self._preview).pack(side="left")
        self.run_button = ttk.Button(actions, text="Run analysis", command=self._run)
        self.run_button.pack(side="left", padx=8)
        self.cancel_button = ttk.Button(actions, text="Stop run", command=self._stop, state="disabled")
        self.cancel_button.pack(side="left")
        ttk.Label(actions, textvariable=self.status).pack(side="right")
        self.log = tk.Text(outer, height=14, state="disabled", wrap="word")
        self.log.pack(fill="both", expand=True)

    def _browse_directory(self, variable):
        chosen = filedialog.askdirectory(parent=self)
        if chosen:
            variable.set(chosen)

    def _browse_design(self):
        chosen = filedialog.askopenfilename(parent=self, filetypes=[("Design files", "*.tsv *.csv"), ("All files", "*")])
        if chosen:
            self.design.set(chosen)

    def _update_mode(self):
        needs_input = self.mode.get() != "modules"
        self.input_entry.configure(state="normal" if needs_input else "disabled")
        self.input_button.configure(state="normal" if needs_input else "disabled")

    def _command(self):
        return build_command(project=self.project.get().strip(), assembly=self.assembly.get(),
                             layout=self.layout.get(), mode=self.mode.get(),
                             input_dir=self.input_dir.get().strip(),
                             modules=tuple(name for name, flag in self.module_flags.items() if flag.get()),
                             design=self.design.get().strip(),
                             contrasts=tuple(line.strip() for line in self.contrasts.get("1.0", "end").splitlines() if line.strip()))

    def _append(self, message):
        self.log.configure(state="normal")
        self.log.insert("end", message)
        self.log.see("end")
        self.log.configure(state="disabled")

    def _preview(self):
        try:
            command = self._command()
        except ValueError as error:
            messagebox.showerror("Check run settings", str(error), parent=self)
            return
        self._append("$ " + shlex.join(command) + "\n")

    def _run(self):
        try:
            command = self._command()
        except ValueError as error:
            messagebox.showerror("Check run settings", str(error), parent=self)
            return
        if not (ROOT / "config" / "main.config").is_file():
            messagebox.showerror("Installation needed", "Install the pipeline first: config/main.config is missing.", parent=self)
            return
        if self.process is not None:
            return
        self._append("$ " + shlex.join(command) + "\n")
        try:
            self.process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT, text=True, bufsize=1,
                                            start_new_session=True)
        except OSError as error:
            self.process = None
            messagebox.showerror("Could not start run", str(error), parent=self)
            return
        self.status.set("Running")
        self.run_button.configure(state="disabled")
        self.cancel_button.configure(state="normal")
        threading.Thread(target=self._read_output, args=(self.process,), daemon=True).start()

    def _read_output(self, process):
        for line in process.stdout:
            self.events.put(("line", line))
        self.events.put(("done", process.wait()))

    def _drain_events(self):
        try:
            while True:
                kind, value = self.events.get_nowait()
                if kind == "line":
                    self._append(value)
                else:
                    self._append(f"\nRun finished with exit code {value}.\n")
                    self.status.set("Completed" if value == 0 else f"Failed ({value})")
                    self.process = None
                    self.run_button.configure(state="normal")
                    self.cancel_button.configure(state="disabled")
        except queue.Empty:
            pass
        self.after(100, self._drain_events)

    def _stop(self):
        if self.process is not None and messagebox.askyesno("Stop run", "Stop the current analysis?", parent=self):
            import os
            import signal
            os.killpg(self.process.pid, signal.SIGTERM)

    def _close(self):
        if self.process is not None:
            messagebox.showinfo("Analysis running", "Stop the current run before closing this window.", parent=self)
            return
        self.destroy()


if __name__ == "__main__":
    Launcher().mainloop()
