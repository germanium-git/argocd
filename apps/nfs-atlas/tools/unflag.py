#!/usr/bin/env python3
# Clears the UGOS "inherit share ACL" bit (0x02 in byte 2 of ug.archive_bit) on every entry of one
# folder under /volume1/nfs and gives the owner rw (+x on dirs). Saves the old values first:
#   /root/acl-pilot/<folder>.<timestamp>.xattr  (restore: setfattr --restore=<file>)
#   /root/acl-pilot/<folder>.<timestamp>.modes  ("<octal mode> <path>")
# Usage on the NAS: sudo python3 unflag.py <folder name under /volume1/nfs>   (see ../readme.md)
import os, stat, sys, time
name = sys.argv[1].strip("/")
root = os.path.join("/volume1/nfs", name)
assert os.path.isdir(root) and "/" not in name, root
bak = "/root/acl-pilot"
os.makedirs(bak, exist_ok=True)
ts = time.strftime("%Y%m%d-%H%M%S")
xattr_out = open(f"{bak}/{name}.{ts}.xattr", "w"); modes_out = open(f"{bak}/{name}.{ts}.modes", "w")
n = cleared = chmodded = 0
for dirpath, dirs, files in os.walk(root):
    for p in [dirpath] + [os.path.join(dirpath, f) for f in files]:
        st = os.lstat(p)
        if stat.S_ISLNK(st.st_mode):
            continue
        n += 1
        modes_out.write(f"{stat.S_IMODE(st.st_mode):o} {p}\n")
        try:
            v = bytearray(os.getxattr(p, "ug.archive_bit"))
        except OSError:
            v = None
        if v is not None:
            xattr_out.write(f"# file: {p}\nug.archive_bit=0x{v.hex()}\n\n")
            if len(v) > 1 and v[1] & 0x02:
                v[1] &= 0xFD
                os.setxattr(p, "ug.archive_bit", bytes(v))
                cleared += 1
        want = st.st_mode | stat.S_IRUSR | stat.S_IWUSR | (stat.S_IXUSR if stat.S_ISDIR(st.st_mode) else 0)
        if want != st.st_mode:
            os.chmod(p, stat.S_IMODE(want))
            chmodded += 1
print(f"{name[:60]}: entries={n} flag-cleared={cleared} chmod={chmodded}")
