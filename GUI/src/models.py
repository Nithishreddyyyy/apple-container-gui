"""Data models for the container GUI.

These are lightweight view-model types. They wrap the raw JSON dictionaries
returned by the `container` CLI (`--format json`) with tolerant accessors,
because exact key casing may vary across CLI versions.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional


def _first(d: Dict[str, Any], *keys: str, default: str = "") -> str:
    """Return the first present, non-empty value for any of *keys*."""
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
        cid = _first(d, "id", "ID", "name", "Name")
        return cls(
            id=cid,
            name=_first(d, "name", "Name", default=cid),
            image=_first(d, "image", "Image", "configuration.image"),
            state=_first(d, "state", "State", "status", "Status"),
            ip=_first(d, "ip", "IP", "address", "Address", "ipAddress"),
            os=_first(d, "os", "OS"),
            arch=_first(d, "arch", "Arch", "architecture"),
            started=_first(d, "started", "Started", "created", "Created"),
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
        # CLI verbose rows may repeat the same image per platform; keep one row.
        return cls(
            name=_first(d, "name", "Name", "repository", "Repository"),
            tag=_first(d, "tag", "Tag"),
            digest=_first(d, "digest", "Digest", "manifestDigest",
                           "ManifestDigest"),
            os=_first(d, "os", "OS"),
            arch=_first(d, "arch", "Arch", "architecture"),
            size=_first(d, "size", "Size", "fullSize", "FullSize"),
            created=_first(d, "created", "Created"),
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
