#!/usr/bin/env python3
"""Parse ss without ever printing network addresses or process identities."""
import ipaddress
import sys
ports = set()
for line in sys.stdin:
    fields = line.split()
    if len(fields) < 5 or fields[0] not in ('tcp', 'udp'):
        continue
    endpoint = fields[4]
    try:
        address, port = endpoint.rsplit(':', 1)
        address = address.strip('[]').split('%')[0]
        if address not in ('*', '') and ipaddress.ip_address(address).is_loopback:
            continue
        if port.isdecimal() and 0 < int(port) < 65536:
            ports.add((fields[0], int(port)))
    except ValueError:
        continue
print(', '.join(f'{proto}/{port}' for proto, port in sorted(ports)))
