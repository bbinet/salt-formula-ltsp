{%- from "ltsp/map.jinja" import service with context %}
{%- if service.enabled %}

ltsp_pkgs:
  pkg.installed:
    - pkgs: {{ service.pkgs }}
    - require_in:
      - network: linux_interface_{{ service.iface }}
{%- if salt['pillar.get']('linux:system:repo', {})|length > 0 and salt['pillar.get']('linux:system:enabled', False) %}
    - require:
      - sls: linux.system.repo
{%- endif %}

{%- if service.multiarch and not grains.get('noservices') %}
ltsp_pkgs_multiarch:
  pkg.installed:
    - pkgs: {{ service.pkgs_multiarch }}
{%- if salt['pillar.get']('linux:system:repo', {})|length > 0 and salt['pillar.get']('linux:system:enabled', False) %}
    - require:
      - sls: linux.system.repo
{%- endif %}
{%- if 'qemu-user-static' in service.pkgs_multiarch and grains.get('virtual_subtype') == 'Docker' %}
fix_qemu-user-static_postinst:
  cmd.run:
    - name: >
        sed -i.bak "s/grep.*container= .*environ.*exit 0/#&/" /var/lib/dpkg/info/qemu-user-static.postinst;
        dpkg-reconfigure qemu-user-static;
        mv /var/lib/dpkg/info/qemu-user-static.postinst{.bak,}
    - onchanges:
      - pkg: ltsp_pkgs_multiarch
{%- endif %}
{%- endif %}

/usr/local/bin/nm_unmanage_device.py:
  file.managed:
    - source: salt://ltsp/files/nm_unmanage_device.py
    - mode: 755
    - require_in:
      - network: linux_interface_{{ service.iface }}

/etc/ltsp/ltsp.conf:
  file.managed:
    - source: salt://ltsp/files/ltsp.conf
    - makedirs: True
    - template: jinja

{{ service.basedir }}:
  file.directory:
    - clean: True
    - makedirs: True
{{ service.basedir }}/images:
  file.directory:
    - makedirs: True
    - require_in:
      - file: {{ service.basedir }}
{{ service.tftpdir }}:
  file.directory:
    - clean: True
    - makedirs: True
{{ service.tftpdir }}/ltsp:
  file.directory:
    - makedirs: True
    - require_in:
      - file: {{ service.tftpdir }}

{%- set ltsp_cmd = "ltsp -b %s -t %s" % (service.basedir, service.tftpdir) %}

ltsp-nfs:
  cmd.run:
    - name: {{ ltsp_cmd }} nfs
    - creates:
      - /etc/exports.d/ltsp-nfs.exports
    - require:
      - file: {{ service.basedir }}
      - file: {{ service.tftpdir }}

ltsp-initrd:
  cmd.run:
    - name: {{ ltsp_cmd }} initrd
    - require:
      - file: {{ service.tftpdir }}/ltsp
    - watch:
      - file: /etc/ltsp/ltsp.conf

{%- for mac, chroot in service.get('mac', {}).items() %}
{{ service.tftpdir }}/{{ mac | lower }}:
  file.symlink:
    - target: {{ service.tftpdir }}/ltsp/{{ chroot }}
    - makedirs: True
    - require:
      - file: {{ service.tftpdir }}/ltsp
    - require_in:
      - file: {{ service.tftpdir }}
{%- endfor %}

{%- for chroot, chrootcfg in service.get('chroot', {}).items() %}
{%- if service.chroot[chroot].get('enabled') %}

{{ service.basedir }}/{{ chroot }}:
  file.symlink:
    - target: {{ chrootcfg.path }}
    - makedirs: True
    - require_in:
      - file: {{ service.basedir }}
ltsp-image:
  cmd.run:
    - name: {{ ltsp_cmd }} image {{ chroot }} --mksquashfs-params='-comp lzo'
{%- if not chrootcfg.get('force_recreate') %}
    - creates:
      - {{ service.basedir }}/images/{{ chroot }}.img
{%- endif %}
    - require:
      - file: {{ service.basedir }}/{{ chroot }}
      - file: {{ service.basedir }}/images

{{ service.tftpdir }}/ltsp/{{ chroot }}:
  file.copy:
    - source: {{ chrootcfg.path }}/boot
{%- if chrootcfg.get('force_recreate') %}
    - force: true
{%- endif %}
    - require:
      - file: {{ service.tftpdir }}/ltsp
    - require_in:
      - file: {{ service.tftpdir }}
{{ service.tftpdir }}/ltsp/{{ chroot }}/ltsp.img:
  file.symlink:
    - target: {{ service.tftpdir }}/ltsp/ltsp.img
    - makedirs: True
    - require:
      - cmd: ltsp-initrd
      - file: {{ service.tftpdir }}/ltsp/{{ chroot }}
    - require_in:
      - file: {{ service.tftpdir }}

{%- for fname, file in chrootcfg.get('boot_files', {}).items() %}
{{ service.tftpdir }}/ltsp/{{ chroot }}/{{ fname }}:
{# following code borrowed from linux/system/file.sls #}
{%- if file.symlink is defined %}
  file.symlink:
    - target: {{ file.symlink }}
{%- else %}
{%- if file.serialize is defined %}
  file.serialize:
    - formatter: {{ file.serialize }}
  {%- if file.contents is defined  %}
    - dataset: {{ file.contents|json }}
  {%- elif file.contents_pillar is defined %}
    - dataset_pillar: {{ file.contents_pillar }}
  {%- endif %}
{%- else %}
  file.managed:
    {%- if file.source is defined %}
    - source: {{ file.source }}
    {%- if file.hash is defined %}
    - source_hash: {{ file.hash }}
    {%- else %}
    - skip_verify: True
    {%- endif %}
    {%- elif file.contents is defined %}
    - contents: {{ file.contents|json }}
    {%- elif file.contents_pillar is defined %}
    - contents_pillar: {{ file.contents_pillar }}
    {%- elif file.contents_grains is defined %}
    - contents_grains: {{ file.contents_grains }}
    {%- endif %}
{%- endif %}
    {%- if file.dir_mode is defined %}
    - dir_mode: {{ file.dir_mode }}
    {%- endif %}
    {%- if file.encoding is defined %}
    - encoding: {{ file.encoding }}
    {%- endif %}
{%- endif %}
    - makedirs: {{ file.get('makedirs', 'false') }}
    - user: {{ file.get('user', 'root') }}
    - group: {{ file.get('group', 'root') }}
    {%- if file.mode is defined %}
    - mode: {{ file.mode }}
    {%- endif %}
    - require:
      - file: {{ service.tftpdir }}/ltsp/{{ chroot }}
    - require_in:
      - file: {{ service.tftpdir }}
{%- endfor %}

{%- endif %}
{%- endfor %}

/usr/local/bin/ltsp_dnsmasq.sh:
  file.managed:
    - source: salt://ltsp/files/ltsp_dnsmasq.sh
    - template: jinja
    - mode: 755
    - makedirs: True
    - require:
      - file: {{ service.tftpdir }}

/etc/systemd/system/ltsp.service:
  file.managed:
    - source: salt://ltsp/files/ltsp.service
{%- if service.running and grains.get('noservices') %}
/etc/systemd/system/multi-user.target.wants/ltsp.service:
  file.symlink:
    - target: /etc/systemd/system/ltsp.service
    - require:
      - file: /etc/systemd/system/ltsp.service
    - require_in:
      - service: ltsp
{%- endif %}

dnsmasq:
  service.dead:
    - enable: False
{%- if grains.get('noservices') %}
/etc/systemd/system/multi-user.target.wants/dnsmasq.service:
  file.absent
{%- endif %}

ltsp:
{%- if service.running %}
  {%- if grains.get('noservices') %}
  service.enabled:
    - unless: /bin/true
  {%- else %}
  service.running:
    - enable: True
  {%- endif %}
    - watch:
      - network: linux_interface_{{ service.iface }}
      - file: /etc/systemd/system/ltsp.service
      - file: /usr/local/bin/ltsp_dnsmasq.sh
      - pkg: ltsp_pkgs
    - require:
      - service: dnsmasq
{%- else %}
  service.dead:
    - enable: False
    - require:
      - file: /etc/systemd/system/ltsp.service
{%- endif %}

{%- endif %}
