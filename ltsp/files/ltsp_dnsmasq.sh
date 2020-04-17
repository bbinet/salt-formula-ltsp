{%- from "ltsp/map.jinja" import service with context %}
{%- set cfg = service.dnsmasq -%}

#!/bin/bash
#
# This file is managed by SaltStack
#

/usr/sbin/dnsmasq \
    --enable-tftp \
    --tftp-root={{ cfg.tftp_root }} \
    --tftp-unique-root=mac \
    --interface {{ service.iface }} \
    --log-dhcp \
    --bind-interfaces \
    --bogus-priv \
    --domain-needed \
    --keep-in-foreground \
{%- for tag, tagcfg in cfg.get('tag', {}).items() %}
{%- for host in tagcfg.dhcp_host %}
    --dhcp-host={{ host }},set:{{ tag }} \
{%- endfor %}

{%- set range = tagcfg.dhcp_range %}
    --dhcp-range=tag:{{ tag }},{{ range.start }},{{ range.end }},{{ range.lease }} \
{%- if tagcfg.dhcp_boot is defined %}
    --dhcp-boot=tag:{{ tag }},{{ tagcfg.dhcp_boot }} \
{%- endif %}
{%- if tagcfg.dhcp_reply_delay is defined %}
    --dhcp-reply-delay=tag:{{ tag }},{{ tagcfg.dhcp_reply_delay }} \
{%- endif %}
{%- if tagcfg.pxe_service is defined %}
    --pxe-service=tag:{{ tag }},{{ tagcfg.pxe_service }} \
{%- endif %}

{%- set nottagcfg = tagcfg.not_tag %}
{%- if nottagcfg.dhcp_range is defined %}
{%- set range = nottagcfg.dhcp_range %}
    --dhcp-range=tag:!{{ tag }},{{ range.start }},{{ range.end }},{{ range.lease }} \
{%- endif %}
{%- if nottagcfg.dhcp_boot is defined %}
    --dhcp-boot=tag:!{{ tag }},{{ nottagcfg.dhcp_boot }} \
{%- endif %}
{%- if nottagcfg.dhcp_reply_delay is defined %}
    --dhcp-reply-delay=tag:!{{ tag }},{{ nottagcfg.dhcp_reply_delay }} \
{%- endif %}
{%- if nottagcfg.pxe_service is defined %}
    --pxe-service=tag:!{{ tag }},{{ nottagcfg.pxe_service }} \
{%- endif %}

{%- endfor %}
    --conf-file
