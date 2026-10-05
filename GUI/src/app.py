"""Tkinter GUI for Apple's `container` CLI.

Architecture:
    App (Tkinter/ttk views)
      -> ContainerService (GUI/src/cli.py)
        -> `container` CLI via safe argv-array subprocess
          -> container runtime (apiserver/XPC/VMs)

All long-running CLI calls execute in a worker thread; results are
marshalled back to the Tk mainloop via ``root.after`` polling.
"""

from __future__ import annotations

import queue
import threading
import tkinter as tk
from tkinter import messagebox, simpledialog, ttk
from typing import Callable, List, Optional

from .cli import ContainerCLIError, ContainerService
from .models import ContainerInfo, ImageInfo


class App:
    def __init__(self, root: tk.Tk, service: ContainerService):
        self.root = root
        self.service = service
        self.jobs: "queue.Queue[Callable[[], None]]" = queue.Queue()
        self.busy = False
        self.containers: List[ContainerInfo] = []
        self.images: List[ImageInfo] = []

        root.title("Container Manager (apple/container GUI)")
        root.geometry("900x620")
        root.minsize(760, 500)

        self._build_menu()
        self._build_layout()
        self.root.after(100, self._pump_jobs)
        self.refresh_all()

    # -- layout --------------------------------------------------------
    def _build_menu(self):
        menubar = tk.Menu(self.root)
        app_menu = tk.Menu(menubar, tearoff=False)
        app_menu.add_command(label="Refresh All", command=self.refresh_all)
        app_menu.add_separator()
        app_menu.add_command(label="Quit", command=self.root.destroy)
        menubar.add_cascade(label="File", menu=app_menu)
        help_menu = tk.Menu(menubar, tearoff=False)
        help_menu.add_command(label="About", command=self._about)
        self.root.config(menu=menubar)

    def _build_layout(self):
        header = ttk.Frame(self.root, padding=(12, 10, 12, 4))
        header.pack(fill=tk.X)
        ttk.Label(header, text="Container Manager",
                  font=("Helvetica", 16, "bold")).pack(side=tk.LEFT)
        ttk.Label(
            header,
            text="Lightweight graphical frontend for the `container` CLI",
            foreground="#666").pack(side=tk.LEFT, padx=(12, 0))

        self.status_var = tk.StringVar(value="Starting…")
        self.sys_var = tk.StringVar(value="System: unknown")

        sysbar = ttk.Frame(self.root, padding=(12, 0, 12, 4))
        sysbar.pack(fill=tk.X)
        ttk.Label(sysbar, textvariable=self.sys_var).pack(side=tk.LEFT)
        ttk.Button(sysbar, text="Refresh All",
                   command=self.refresh_all).pack(side=tk.RIGHT)

        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=12, pady=6)

        self._build_containers_tab()
        self._build_images_tab()
        self._build_system_tab()

        out_frame = ttk.LabelFrame(self.root, text="Command Output",
                                   padding=6)
        out_frame.pack(fill=tk.BOTH, padx=12, pady=(0, 6))
        self.output = tk.Text(out_frame, height=8, wrap=tk.WORD,
                              state=tk.DISABLED, font=("Menlo", 11))
        scrollbar = ttk.Scrollbar(out_frame, command=self.output.yview)
        self.output.configure(yscrollcommand=scrollbar.set)
        self.output.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        ttk.Button(out_frame, text="Clear",
                   command=self._clear_output).pack(side=tk.BOTTOM, pady=(4, 0))

        statusbar = ttk.Frame(self.root, padding=(12, 0, 12, 10))
        statusbar.pack(fill=tk.X)
        ttk.Label(statusbar, textvariable=self.status_var,
                  foreground="#444").pack(side=tk.LEFT)

    def _tree(self, parent, columns, widths):
        tree = ttk.Treeview(parent, columns=columns, show="headings",
                            selectmode="browse")
        for col, w in zip(columns, widths):
            tree.heading(col, text=col)
            tree.column(col, width=w, anchor=tk.W)
        vs = ttk.Scrollbar(parent, orient=tk.VERTICAL, command=tree.yview)
        tree.configure(yscrollcommand=vs.set)
        tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        vs.pack(side=tk.RIGHT, fill=tk.Y)
        return tree

    def _build_containers_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Containers")
        toolbar = ttk.Frame(tab)
        toolbar.pack(fill=tk.X, pady=(0, 6))
        for label, cmd in [
            ("Refresh", self.refresh_containers),
            ("Run…", self._run_dialog),
            ("Start", self._start_selected),
            ("Stop", self._stop_selected),
            ("Restart", self._restart_selected),
            ("Remove…", self._remove_selected),
            ("Logs", self._logs_selected),
            ("Inspect", self._inspect_selected),
        ]:
            ttk.Button(toolbar, text=label, command=cmd).pack(side=tk.LEFT,
                                                              padx=(0, 6))
        body = ttk.Frame(tab)
        body.pack(fill=tk.BOTH, expand=True)
        self.ctree = self._tree(body,
                                ["Name", "Image", "State", "IP", "OS/Arch"],
                                [180, 220, 100, 130, 120])
        self.cempty = ttk.Label(tab, text="", foreground="#666")

    def _build_images_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Images")
        toolbar = ttk.Frame(tab)
        toolbar.pack(fill=tk.X, pady=(0, 6))
        for label, cmd in [
            ("Refresh", self.refresh_images),
            ("Pull…", self._pull_dialog),
            ("Remove…", self._remove_image_selected),
        ]:
            ttk.Button(toolbar, text=label, command=cmd).pack(side=tk.LEFT,
                                                              padx=(0, 6))
        body = ttk.Frame(tab)
        body.pack(fill=tk.BOTH, expand=True)
        self.itree = self._tree(body, ["Name", "Tag", "OS/Arch", "Size"],
                                [260, 140, 140, 140])

    def _build_system_tab(self):
        tab = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(tab, text="System")
        ttk.Label(tab, text="System Service", font=("Helvetica", 13, "bold")
                  ).pack(anchor=tk.W)
        self.sys_detail = tk.StringVar(value="Status: unknown")
        ttk.Label(tab, textvariable=self.sys_detail).pack(anchor=tk.W, pady=4)
        btns = ttk.Frame(tab)
        btns.pack(anchor=tk.W, pady=6)
        ttk.Button(btns, text="Refresh Status",
                   command=self.refresh_system).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(btns, text="Start System",
                   command=self._system_start).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(btns, text="Stop System",
                   command=self._system_stop).pack(side=tk.LEFT)
        ttk.Label(tab, text="Version info:").pack(anchor=tk.W, pady=(10, 2))
        self.version_text = tk.Text(tab, height=6, wrap=tk.WORD,
                                    state=tk.DISABLED, font=("Menlo", 11))
        self.version_text.pack(fill=tk.BOTH, expand=True)

    # -- background jobs ----------------------------------------------
    def _set_busy(self, msg: str):
        self.busy = True
        self.status_var.set(msg)

    def _set_idle(self, msg: str = "Ready"):
        self.busy = False
        self.status_var.set(msg)

    def _submit(self, label: str, fn: Callable[[], Callable[[], None]]):
        """Run ``fn`` in a worker thread; its return value runs on the UI thread."""
        if self.busy:
            messagebox.showinfo("Working",
                                "Another operation is in progress. Please wait.")
            return
        self._set_busy(label + "…")

        def worker():
            try:
                apply = fn()
            except ContainerCLIError as e:
                apply = lambda e=e: self._fail(str(e))  # noqa: E731
            except Exception as e:  # defensive: never kill the worker silently
                apply = lambda e=e: self._fail(f"Unexpected error: {e}")  # noqa: E731
            self.jobs.put(apply)

        threading.Thread(target=worker, daemon=True).start()

    def _pump_jobs(self):
        try:
            while True:
                apply = self.jobs.get_nowait()
                try:
                    apply()
                finally:
                    self.jobs.task_done()
        except queue.Empty:
            pass
        self.root.after(100, self._pump_jobs)

    def _fail(self, msg: str):
        self._set_idle("Error — see Command Output")
        self._log(f"ERROR: {msg}")
        messagebox.showerror("Container error", msg)

    # -- output pane ---------------------------------------------------
    def _log(self, text: str):
        self.output.configure(state=tk.NORMAL)
        self.output.insert(tk.END, text.rstrip() + "\n")
        self.output.see(tk.END)
        self.output.configure(state=tk.DISABLED)

    def _log_result(self, cmd: str, stdout: str, stderr: str):
        self._log(f"$ container {cmd}")
        if stdout.strip():
            self._log(stdout.strip())
        if stderr.strip():
            self._log(f"[stderr] {stderr.strip()}")

    def _clear_output(self):
        self.output.configure(state=tk.NORMAL)
        self.output.delete("1.0", tk.END)
        self.output.configure(state=tk.DISABLED)

    # -- refresh -------------------------------------------------------
    def refresh_all(self):
        """Startup refresh: system + containers + images in ONE worker.

        A single job can never be dropped by the busy-guard, and its apply
        step always clears the busy flag — previously three separate silent
        refreshes raced the guard and the dashboard never loaded.
        """
        def work():
            data: dict = {}
            try:
                data["status"] = self.service.system_status()
            except ContainerCLIError as e:
                data["status_err"] = str(e)
            try:
                data["version"] = self.service.system_version()
            except ContainerCLIError:
                data["version"] = "(version unavailable)"
            try:
                data["containers"] = self.service.list_containers()
                data["c_table"] = self.service.run_raw(["list", "--all"])
            except ContainerCLIError as e:
                data["containers_err"] = str(e)
            try:
                data["images"] = self.service.list_images()
                data["i_table"] = self.service.run_raw(["image", "list"])
            except ContainerCLIError as e:
                data["images_err"] = str(e)

            def apply(data=data):
                errs = []
                st = data.get("status")
                if st is not None:
                    self.sys_var.set(f"System: {st.status}")
                    self.sys_detail.set(f"Status: {st.status}")
                else:
                    self.sys_var.set("System: unknown")
                    self.sys_detail.set("Status: unknown")
                    errs.append(data.get("status_err", "system status failed"))
                self.version_text.configure(state=tk.NORMAL)
                self.version_text.delete("1.0", tk.END)
                self.version_text.insert(tk.END, data.get("version", ""))
                self.version_text.configure(state=tk.DISABLED)
                if "containers" in data:
                    self.containers = data["containers"]
                    self._render_containers()
                    tbl = data.get("c_table")
                    if tbl is not None:
                        self._log_result("list --all", tbl.stdout, tbl.stderr)
                else:
                    errs.append(data.get("containers_err",
                                        "container list failed"))
                if "images" in data:
                    self.images = data["images"]
                    self._render_images()
                    tbl = data.get("i_table")
                    if tbl is not None:
                        self._log_result("image list", tbl.stdout, tbl.stderr)
                else:
                    errs.append(data.get("images_err", "image list failed"))
                for e in errs:
                    self._log(f"ERROR: {e}")
                if errs:
                    self._set_idle("Ready (some refreshes failed — see output)")
                else:
                    n, m = len(self.containers), len(self.images)
                    self._set_idle(f"Ready — {n} container(s), {m} image(s)")
            return apply
        self._submit("Refreshing", work)

    def refresh_containers(self):
        def work():
            items = self.service.list_containers()
            res = self.service.run_raw(["list", "--all"])
            def apply(items=items, res=res):
                self.containers = items
                self._render_containers()
                self._log_result("list --all", res.stdout, res.stderr)
                self._set_idle(f"Ready — {len(items)} container(s)")
            return apply
        self._submit("Refreshing containers", work)

    def _render_containers(self):
        for row in self.ctree.get_children():
            self.ctree.delete(row)
        if not self.containers:
            self.cempty.configure(
                text="No containers found. Run one with Containers → Run… "
                     "or `container run --rm alpine echo hello`.")
            self.cempty.pack(pady=8)
        else:
            self.cempty.pack_forget()
            for i, c in enumerate(self.containers):
                state = c.state or "unknown"
                marker = "● " if c.is_running else "○ "
                self.ctree.insert("", tk.END,
                                  iid=c.id or f"row-{i}",
                                  values=(c.display_name, c.image,
                                          marker + state, c.ip,
                                          f"{c.os}/{c.arch}".strip("/")))

    def _render_images(self):
        for row in self.itree.get_children():
            self.itree.delete(row)
        if not self.images:
            self.itree.insert("", tk.END, values=(
                "(no images)", "pull one with Images → Pull…", "", ""))
        for im in self.images:
            self.itree.insert("", tk.END, values=(
                im.name, im.tag,
                f"{im.os}/{im.arch}".strip("/"), im.size))

    def refresh_images(self):
        def work():
            items = self.service.list_images()
            res = self.service.run_raw(["image", "list"])
            def apply(items=items, res=res):
                self.images = items
                self._render_images()
                self._log_result("image list", res.stdout, res.stderr)
                self._set_idle(f"Ready — {len(items)} image(s)")
            return apply
        self._submit("Refreshing images", work)

    def refresh_system(self):
        def work():
            st = self.service.system_status()
            ver = ""
            try:
                ver = self.service.system_version()
            except ContainerCLIError:
                ver = "(version unavailable while system is stopped)"
            def apply(st=st, ver=ver):
                self.sys_var.set(f"System: {st.status}")
                self.sys_detail.set(f"Status: {st.status}")
                self.version_text.configure(state=tk.NORMAL)
                self.version_text.delete("1.0", tk.END)
                self.version_text.insert(tk.END, ver)
                self.version_text.configure(state=tk.DISABLED)
                self._log(f"$ container system status\n{st.status}")
                self._set_idle(f"System: {st.status}")
            return apply
        self._submit("Checking system status", work)

    # -- selection helpers ---------------------------------------------
    def _selected_container_id(self) -> Optional[str]:
        sel = self.ctree.selection()
        if not sel:
            messagebox.showinfo("No selection",
                                "Select a container first.")
            return None
        return sel[0]

    def _selected_image_ref(self) -> Optional[str]:
        sel = self.itree.selection()
        if not sel:
            messagebox.showinfo("No selection", "Select an image first.")
            return None
        vals = self.itree.item(sel[0], "values")
        if not vals or vals[0] == "(no images)":
            return None
        name, tag = vals[0], vals[1] if len(vals) > 1 else ""
        ref = f"{name}:{tag}" if tag else name
        return ref

    # -- container actions ---------------------------------------------
    def _start_selected(self):
        cid = self._selected_container_id()
        if cid is None:
            return
        def work(cid=cid):
            res = self.service.start_container(cid)
            def apply(res=res, cid=cid):
                self._log_result(f"start {cid}", res.stdout, res.stderr)
                self._set_idle(f"Started {cid}")
                self.refresh_containers()
            return apply
        self._submit(f"Starting {cid}", work)

    def _stop_selected(self):
        cid = self._selected_container_id()
        if cid is None:
            return
        def work(cid=cid):
            res = self.service.stop_container(cid)
            def apply(res=res, cid=cid):
                self._log_result(f"stop {cid}", res.stdout, res.stderr)
                self._set_idle(f"Stopped {cid}")
                self.refresh_containers()
            return apply
        self._submit(f"Stopping {cid}", work)

    def _restart_selected(self):
        cid = self._selected_container_id()
        if cid is None:
            return
        if not messagebox.askyesno("Restart",
                                    f"Restart container {cid!r}?"):
            return
        def work(cid=cid):
            res = self.service.restart_container(cid)
            def apply(res=res, cid=cid):
                self._log_result(f"restart {cid}", res.stdout, res.stderr)
                self._set_idle(f"Restarted {cid}")
                self.refresh_containers()
            return apply
        self._submit(f"Restarting {cid}", work)

    def _remove_selected(self):
        cid = self._selected_container_id()
        if cid is None:
            return
        if not messagebox.askyesno(
                "Remove container",
                f"Remove container {cid!r}? This deletes it.",
                icon=messagebox.WARNING):
            return
        def work(cid=cid):
            res = self.service.remove_container(cid)
            def apply(res=res, cid=cid):
                self._log_result(f"rm {cid}", res.stdout, res.stderr)
                self._set_idle(f"Removed {cid}")
                self.refresh_containers()
            return apply
        self._submit(f"Removing {cid}", work)

    def _logs_selected(self):
        cid = self._selected_container_id()
        if cid is None:
            return
        def work(cid=cid):
            res = self.service.container_logs(cid)
            def apply(res=res, cid=cid):
                self._log_result(f"logs {cid}", res.stdout, res.stderr)
                self._set_idle(f"Logs for {cid}")
                self.notebook.select(2)  # keep focus; output pane shows logs
            return apply
        self._submit(f"Fetching logs for {cid}", work)

    def _inspect_selected(self):
        cid = self._selected_container_id()
        if cid is None:
            return
        def work(cid=cid):
            out = self.service.inspect_container(cid)
            def apply(out=out, cid=cid):
                self._log_result(f"inspect {cid}", out, "")
                self._set_idle(f"Inspected {cid}")
            return apply
        self._submit(f"Inspecting {cid}", work)

    def _run_dialog(self):
        image = simpledialog.askstring("Run container",
                                       "Image (e.g. alpine:latest):",
                                       parent=self.root)
        if not image:
            return
        name = simpledialog.askstring("Run container",
                                      "Name (optional):",
                                      parent=self.root) or ""
        def work(image=image, name=name):
            res = self.service.run_container(image.strip(), name.strip())
            def apply(res=res):
                self._log_result("run …", res.stdout, res.stderr)
                self._set_idle("Container started")
                self.refresh_containers()
            return apply
        self._submit(f"Running {image}", work)

    # -- image actions ---------------------------------------------------
    def _pull_dialog(self):
        ref = simpledialog.askstring("Pull image",
                                     "Image reference (e.g. alpine:latest):",
                                     parent=self.root)
        if not ref:
            return
        def work(ref=ref):
            res = self.service.pull_image(ref.strip())
            def apply(res=res, ref=ref):
                self._log_result(f"image pull {ref}", res.stdout, res.stderr)
                self._set_idle(f"Pulled {ref}")
                self.refresh_images()
            return apply
        self._submit(f"Pulling {ref}", work)

    def _remove_image_selected(self):
        ref = self._selected_image_ref()
        if ref is None:
            return
        if not messagebox.askyesno("Remove image",
                                    f"Remove image {ref!r}?",
                                    icon=messagebox.WARNING):
            return
        def work(ref=ref):
            res = self.service.remove_image(ref)
            def apply(res=res, ref=ref):
                self._log_result(f"image rm {ref}", res.stdout, res.stderr)
                self._set_idle(f"Removed image {ref}")
                self.refresh_images()
            return apply
        self._submit(f"Removing image {ref}", work)

    # -- system actions ---------------------------------------------------
    def _system_start(self):
        if not messagebox.askyesno("Start system",
                                    "Start the container system service? "
                                    "This may take a while."):
            return
        def work():
            res = self.service.system_start()
            def apply(res=res):
                self._log_result("system start", res.stdout, res.stderr)
                self._set_idle("System start requested")
                self.refresh_system()
            return apply
        self._submit("Starting system", work)

    def _system_stop(self):
        if not messagebox.askyesno("Stop system",
                                    "Stop the container system service? "
                                    "Running containers will stop.",
                                    icon=messagebox.WARNING):
            return
        def work():
            res = self.service.system_stop()
            def apply(res=res):
                self._log_result("system stop", res.stdout, res.stderr)
                self._set_idle("System stop requested")
                self.refresh_system()
            return apply
        self._submit("Stopping system", work)

    def _about(self):
        messagebox.showinfo(
            "About",
            "Container Manager\n"
            "A lightweight Tkinter frontend for Apple's `container` CLI.\n"
            "Academic open-source contribution prototype.")


def main(service: Optional[ContainerService] = None):
    root = tk.Tk()
    try:
        # Use a clam-like native-ish theme where available.
        style = ttk.Style(root)
        for theme in ("aqua", "clam", "alt"):
            if theme in style.theme_names():
                style.theme_use(theme)
                break
    except Exception:
        pass
    svc = service or ContainerService()
    App(root, svc)
    root.mainloop()
