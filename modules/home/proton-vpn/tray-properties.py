"""Check the real tray property methods without connecting to a desktop bus."""

from types import SimpleNamespace

import dbus
from proton.vpn.app.gtk.widgets.main.tray_icon import SNI_INTERFACE, _StatusNotifierItem


item = SimpleNamespace(
    tray=SimpleNamespace(
        status="Active",
        app_id="proton.vpn.app.gtk",
        title="Proton VPN",
        icon_name="proton-vpn-sign",
        icon_desc="",
    )
)
properties = _StatusNotifierItem.GetAll(item, SNI_INTERFACE)
pixmaps = {
    "Get": _StatusNotifierItem.Get(item, SNI_INTERFACE, "IconPixmap"),
    "GetAll": properties.get("IconPixmap"),
}
for method, value in pixmaps.items():
    assert isinstance(value, dbus.Array), f"{method}: IconPixmap must be an array, got {value!r}"
    assert value.signature == "(iiay)" and not value, f"{method}: expected empty a(iiay)"

assert _StatusNotifierItem.Get(item, SNI_INTERFACE, "IconName") == item.tray.icon_name
assert properties["IconName"] == item.tray.icon_name
print("PASS: Get and GetAll return typed empty pixmaps and preserve the named icon")
