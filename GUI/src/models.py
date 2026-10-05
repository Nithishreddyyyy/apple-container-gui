"""Data models for the container GUI.

These are lightweight view-model types. They wrap the raw JSON dictionaries
returned by the `container` CLI (`--format json`) with tolerant accessors,
because exact key casing may vary across CLI versions.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional


def _nested(d: Dict[str, Any], *path: str) -> Any:
    """Walk nested dicts along *path*; return None if anything is missing."""
    cur: Any = d
    for key in path:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(key)
        if cur is None:
            return None
    return cur


def _str(v: Any, default: str = "") -> str:
    if v is None or isinstance(v, (list, dict)):
        return default
    s = str(v)
    return s if s != "" else default


def _split_ref(ref: str) -> tuple[str, str]:
    """Split `registry/name:tag` into (name, tag). Digest refs keep tag=''."""
    ref = (ref or "").strip()
    if not ref or "@sha256" in ref or ref.startswith("sha256:"):
        return ref, ""
    if ":" in ref and "/" in ref:
        # Only treat the part after the LAST colon as a tag if it follows
        # the last slash (avoids registry :port confusion).
        name, _, tag = ref.rpartition(":")
        if "/" in tag or not tag:
            return ref, ""
        return name, tag
    if ":" in ref:
        name, _, tag = ref.rpartition(":")
        return (name, tag) if tag and "/" not in tag else (ref, "")
    return ref, ""


def _fmt_size(v: Any) -> str:
    try:
        n = int(v)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return _str(v)
    if n < 0:
        return _str(v)
    units = ["B", "KB", "MB", "GB", "TB"]
    f = float(n)
    for u in units:
        if f < 1024 or u == units[-1]:
            return f"{f:.1f} {u}" if u != "B" else f"{n} B"
        f /= 1024
    return f"{n} B"


def _ip_from_networks(networks: Any) -> str:
    if not isinstance(networks, list):
        return ""
    ips = []
    for item in networks:
        if isinstance(item, str) and item:
            ips.append(item)
        elif isinstance(item, dict):
            for k in ("address", "ip", "ipAddress", "IPAddress"):
                if item.get(k):
                    ips.append(str(item[k]))
                    break
    return ", ".join(ips)


def _first(d: Dict[str, Any], *keys: str, default: str = "") -> str:
    """Return the first present, non-empty scalar value for any of *keys*."""
    for k in keys:
        v = d.get(k)
        if v is not None and v != "":
            if isinstance(v, (list, dict)):
                continue
            return str(v)
    # case-insensitive fallback
    lowered = {str(k).lower(): v for k, v in d.items()}
    for k in keys:
        v = lowered.get(k.lower())
        if v is not None and v != "" and not isinstance(v, (list, dict)):
            return str(v)
    return default


@dataclass
class ContainerInfo:
    """A single container row for the dashboard."""

    id: str = ""
    name: str = ""
    image: str = ""
    state: str = ""
    ip: str = ""
    os: str = ""
    arch: str = ""
    started: str = ""
    raw: Dict[str, Any] = field(default_factory=dict)

    @property
    def display_name(self) -> str:
        return self.name or self.id

    @property
    def is_running(self) -> bool:
        return self.state.strip().lower() in ("running", "up", "started")

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "ContainerInfo":
        # Real CLI 1.x shape:
        #   {"id": ..., "configuration": {"id", "image": {"reference"},
        #    "platform": {"os", "architecture"}, "creationDate", ...},
        #    "status": {"state", "networks": [...]}, ...}
        # Flat keys are kept as fallbacks for older/newer outputs.
        cfg = _nested(d, "configuration")
        if not isinstance(cfg, dict):
            cfg = {}
        st = _nested(d, "status")
        if not isinstance(st, dict):
            # Some outputs use a plain string status.
            st = {}
        status_str = _nested(d, "status")
        if isinstance(status_str, str):
            state = status_str
        else:
            state = _str(_nested(st, "state")) or _first(d, "state", "State")
        plat = _nested(cfg, "platform")
        if not isinstance(plat, dict):
            plat = {}
        img = _nested(cfg, "image")
        image = _str(_nested(img, "reference") if isinstance(img, dict) else img)
        cid = _first(d, "id", "ID") or _str(_nested(cfg, "id"))
        name = (_first(d, "name", "Name")
                or _str(_nested(cfg, "name"))
                or _str(_nested(cfg, "hostname"))
                or cid)
        ip = (_ip_from_networks(_nested(st, "networks"))
              or _ip_from_networks(_nested(d, "networks"))
              or _first(d, "ip", "IP", "address", "Address", "ipAddress"))
        return cls(
            id=cid,
            name=name or cid,
            image=image or _first(d, "image", "Image"),
            state=state,
            ip=ip,
            os=_str(_nested(plat, "os")) or _first(d, "os", "OS"),
            arch=(_str(_nested(plat, "architecture"))
                  or _first(d, "arch", "Arch", "architecture")),
            started=(_str(_nested(cfg, "creationDate"))
                     or _first(d, "started", "Started", "created", "Created")),
            raw=dict(d),
        )


@dataclass
class ImageInfo:
    """A single image row for the images view."""

    name: str = ""
    tag: str = ""
    digest: str = ""
    os: str = ""
    arch: str = ""
    size: str = ""
    created: str = ""
    raw: Dict[str, Any] = field(default_factory=dict)

    @property
    def reference(self) -> str:
        if self.name and self.tag:
            return f"{self.name}:{self.tag}"
        return self.name or self.digest

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "ImageInfo":
        # Real CLI 1.x shape:
        #   {"configuration": {"name": "registry/repo:tag", ...},
        #    "id": ..., "variants": [{"digest", "platform": {...},
        #    "size": bytes}, ...]}
        # One row per image; first variant supplies os/arch/size.
        cfg = _nested(d, "configuration")
        if not isinstance(cfg, dict):
            cfg = {}
        variants = d.get("variants")
        first_variant = (variants[0] if isinstance(variants, list)
                         and variants and isinstance(variants[0], dict)
                         else {})
        vplat = _nested(first_variant, "platform")
        if not isinstance(vplat, dict):
            vplat = {}
        full_ref = (_str(_nested(cfg, "name"))
                    or _first(d, "name", "Name", "repository", "Repository"))
        name, tag = _split_ref(full_ref)
        if not tag:
            tag = _first(d, "tag", "Tag")
            if tag and not name:
                name = full_ref
        digest = (_str(_nested(first_variant, "digest"))
                  or _first(d, "digest", "Digest", "manifestDigest",
                            "ManifestDigest")
                  or _str(d.get("id")))
        size_raw = (_nested(first_variant, "size")
                    if "size" in first_variant else d.get("size",
                    d.get("fullSize")))
        created = (_str(_nested(cfg, "creationDate"))
                   or _str(_nested(first_variant, "created"))
                   or _first(d, "created", "Created"))
        return cls(
            name=name or full_ref,
            tag=tag,
            digest=digest,
            os=_str(_nested(vplat, "os")) or _first(d, "os", "OS"),
            arch=(_str(_nested(vplat, "architecture"))
                  or _first(d, "arch", "Arch", "architecture")),
            size=_fmt_size(size_raw),
            created=created,
            raw=dict(d),
        )


@dataclass
class SystemStatus:
    """Result of `container system status --format json`."""

    status: str = "unknown"
    raw: Dict[str, Any] = field(default_factory=dict)

    @property
    def is_running(self) -> bool:
        return self.status.strip().lower() == "running"

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "SystemStatus":
        return cls(status=_first(d, "status", "Status", default="unknown"),
                   raw=dict(d))
