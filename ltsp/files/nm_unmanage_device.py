#!/usr/bin/python3
"""
Control NetworkManager from dbus to unmanage a device

The Python version of the example at
https://forums.resin.io/t/rpi-3-access-point-hostapd-disconnects-after-a-few-minutes/1987/4

On resin.io devices need to set the system dbus address:
DBUS_SYSTEM_BUS_ADDRESS=unix:path=/host/run/dbus/system_bus_socket
"""
import sys
import os

DBUS_SOCKET_PATH="/host/run/dbus/system_bus_socket"

if not os.access(DBUS_SOCKET_PATH, os.R_OK and os.W_OK):
    # do nothing when host dbus socket does not exist
    print("Host dbus socket does not exist")
    sys.exit(0)


import dbus

if os.path.exists(DBUS_SOCKET_PATH):
    os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=%s" % DBUS_SOCKET_PATH

iface = sys.argv[1]
bus = dbus.SystemBus()

nm_proxy = bus.get_object('org.freedesktop.NetworkManager', '/org/freedesktop/NetworkManager')
nm = dbus.Interface(nm_proxy, dbus_interface='org.freedesktop.NetworkManager')

for device_obj_path in nm.GetDevices():
    device_proxy = bus.get_object('org.freedesktop.NetworkManager', device_obj_path)
    device = dbus.Interface(device_proxy, dbus_interface='org.freedesktop.DBus.Properties')
    #print("%s == %s ?" %(device.Get('org.freedesktop.NetworkManager.Device', 'Interface'), iface))
    #print(device.Get('org.freedesktop.NetworkManager.Device', 'Managed'))
    if device.Get('org.freedesktop.NetworkManager.Device', 'Interface') == iface:
        #print("Iface %s found" % iface)
        device.Set('org.freedesktop.NetworkManager.Device', 'Managed', False)
