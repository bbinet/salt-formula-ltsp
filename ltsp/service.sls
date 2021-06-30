{%- from "ltsp/map.jinja" import service with context %}
{%- if service.enabled %}

ltsp_pkgs:
  pkg.installed:
    - pkgs: {{ service.pkgs }}
{%- if salt['pillar.get']('linux:network:enabled', False) and salt['pillar.get']('linux:network:interface:%s:enabled' % service.iface, False) %}
    - require_in:
      - network: linux_interface_{{ service.iface }}
{%- endif %}
{%- if salt['pillar.get']('linux:system:repo', {})|length > 0 and salt['pillar.get']('linux:system:enabled', False) %}
    - require:
      - sls: linux.system.repo
{%- endif %}

{%- if service.multiarch and not grains.get('noservices') %}
add_i386_architecture:
  cmd.run:
    - name: dpkg --add-architecture i386 && apt-get update
    - unless: dpkg --print-foreign-architectures | grep -q i386
ltsp_pkgs_multiarch:
  pkg.installed:
    - pkgs: {{ service.pkgs_multiarch }}
    - require:
      - cmd: add_i386_architecture
{%- if salt['pillar.get']('linux:system:repo', {})|length > 0 and salt['pillar.get']('linux:system:enabled', False) %}
      - sls: linux.system.repo
{%- endif %}
{%- if 'qemu-user-static:i386' in service.pkgs_multiarch and grains.get('virtual_subtype') == 'Docker' %}
{# FIXME: Investigate if we should extract only qemu-arm-static from i386 qemu-user-static deb 
wget -O /tmp/qemu-user-static_i386.deb "$(apt-get install --reinstall --print-uris -qq qemu-user-static | cut -d"'" -f2 | sed "s/amd64/i386/")"
dpkg --fsys-tarfile /tmp/qemu-user-static_i386.deb | tar xOf - ./usr/bin/qemu-arm-static > /path/to/qemu-arm-static
chmod a+x /path/to/qemu-arm-static
echo ":sbuild-arm:M::\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:$(realpath "/path/to/qemu-arm-static"):OCF" > /proc/sys/fs/binfmt_misc/register
# see: https://github.com/RPi-Distro/pi-gen/issues/271#issuecomment-773368420
#}
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

{%- if salt['pillar.get']('linux:network:enabled', False) and salt['pillar.get']('linux:network:interface:%s:enabled' % service.iface, False) %}
/usr/local/bin/nm_unmanage_device.py:
  file.managed:
    - source: salt://ltsp/files/nm_unmanage_device.py
    - mode: 755
    - require_in:
      - network: linux_interface_{{ service.iface }}
{%- endif %}

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

{%- if service.pigen.get('enabled') %}
pigen_pkgs:
  pkg.installed:
    - pkgs: {{ service.pkgs_pigen }}
{%- if salt['pillar.get']('linux:system:repo', {})|length > 0 and salt['pillar.get']('linux:system:enabled', False) %}
    - require:
      - sls: linux.system.repo
{%- endif %}
pigen-repo:
  git.latest:
    - name: {{ service.pigen.repository }}
    - target: {{ service.pigen.path }}
    - rev: {{ service.pigen.revision|default(service.pigen.branch) }}
    - branch: {{ service.pigen.branch|default(service.pigen.revision) }}
    - force_fetch: {{ service.pigen.get("force_fetch", False) }}
    - force_reset: {{ service.pigen.get("force_reset", False) }}
    - identity: {{ grains['root'] }}/.ssh/id_rsa #=> can't use grains['root'] here
touch_{{ service.pigen.path }}/config:
  file.touch:
    - name: {{ service.pigen.path }}/config
keyvalue_{{ service.pigen.path }}/config:
  file.keyvalue:
    - name: {{ service.pigen.path }}/config
    - key_values: {{ service.pigen.config|json }}
    - append_if_not_found: true
    - require:
      - file: touch_{{ service.pigen.path }}/config
{%- endif %}

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
{%- if "cmdline.txt" not in chrootcfg.get('boot_files', {}) %}
{{ service.tftpdir }}/ltsp/{{ chroot }}/cmdline.txt:
  file.managed:
    - contents: >-
        ip=dhcp
        root=/dev/nfs
        nfsroot=192.168.67.1:{{ service.basedir }}/{{ chroot }},vers=3,tcp,nolock
        init=/usr/share/ltsp/client/init/init
        ltsp.image=images/{{ chroot }}.img
        console=serial0,115200
        console=tty1
        elevator=deadline
        fsck.repair=yes
        rootwait
        quiet
        splash
        plymouth.ignore-serial-consoles
        modprobe.blacklist=bcm2835_v4l2
{%- endif %}

/etc/exports.d/ltsp-{{ chroot }}.exports:
  file.managed:
    - contents: "{{ service.basedir }}/{{ chroot }}  *(ro,async,crossmnt,no_subtree_check,no_root_squash,insecure)"
{%- else %}
/etc/exports.d/ltsp-{{ chroot }}.exports:
  file.absent
{%- endif %}
  cmd.run:
    - name: exportfs -ra
    - onchanges:
      - file: /etc/exports.d/ltsp-{{ chroot }}.exports

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
