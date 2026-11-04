#!/usr/bin/env python3
"""合并两个 Mach-O 切片为一个 FAT（universal）二进制。

Linux 上没有 lipo，手写 FAT header 即可。

FAT 格式:
  magic       uint32 BE  0xbebafeca  -> 表示下面用大端读取
  nfat_arch   uint32 BE
  fat_arch[n] 20 bytes each:
      cputype    int32  BE
      cpusubtype int32  BE
      offset     uint32 BE   从文件起点算
      size       uint32 BE
      align      uint32 BE   以 2 为底的指数

用法: python3 make_fat.py <输出> <切片1> <切片2> [...]
"""
import struct
import sys

# FAT_MAGIC 写成小端字节序 b'\xca\xfe\xba\xbe' 表示「大端字段」，
# 反之 b'\xbe\xba\xfe\xca' 表示「小端字段」。我们统一用大端。
FAT_MAGIC_BE = b"\xca\xfe\xba\xbe"
HEADER_SIZE = 8
ARCH_SIZE = 20
PAGE = 0x4000  # 16KB, arm64 页大小


def read_thin(path):
    data = open(path, "rb").read()
    magic = data[:4]
    if magic in (FAT_MAGIC_BE, b"\xbe\xba\xfe\xca"):
        raise SystemExit("%s 已经是 FAT，不能作为切片" % path)
    if len(data) < 28:
        raise SystemExit("%s 太小，不是 Mach-O" % path)
    # Mach-O 头字段是小端（magic 0xfeedfacf 按小端读），
    # 而外层 FAT header 用大端。两处别搞混。
    cputype, cpusubtype = struct.unpack("<ii", data[4:12])
    return cputype, cpusubtype, data


def align_up(value, alignment):
    return (value + alignment - 1) // alignment * alignment


CPU_SUBTYPE_ARM64E = 0x80000002  # ARM64E | PTRAUTH_ABI
ARM64E_MARKER = "-e"


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)

    out_path = argv[1]
    paths = argv[2:]
    slices = [read_thin(p) for p in paths]

    # lld writes cpusubtype 0 even for -target arm64e, so the PAC bit is
    # lost in the Mach-O header. Restore it in the FAT header: a path whose
    # basename marks arm64e gets CPU_SUBTYPE_ARM64E (0x80000002), matching
    # what Apple tooling emits.
    fixed = []
    for path, (cputype, cpusubtype, data) in zip(paths, slices):
        # match ".arm64e." / ".arm64e.dylib" so plain ".arm64." is not hit
        is_arm64e = ".arm64e." in path or path.endswith(".arm64e")
        if is_arm64e and cpusubtype == 0:
            cpusubtype = CPU_SUBTYPE_ARM64E
        fixed.append((cputype, cpusubtype, data))
    slices = fixed

    n = len(slices)
    header_len = HEADER_SIZE + ARCH_SIZE * n
    cursor = align_up(header_len, PAGE)

    offsets = []
    for cputype, cpusubtype, data in slices:
        offsets.append(cursor)
        cursor = align_up(cursor + len(data), PAGE)

    with open(out_path, "wb") as f:
        f.write(FAT_MAGIC_BE)
        f.write(struct.pack(">I", n))

        for (cputype, cpusubtype, data), offset in zip(slices, offsets):
            f.write(struct.pack(">IIIII", cputype & 0xFFFFFFFF,
                                 cpusubtype & 0xFFFFFFFF, offset,
                                len(data), 14))  # 2^14 == 16384

        for (cputype, cpusubtype, data), offset in zip(slices, offsets):
            f.seek(offset)
            f.write(data)

    # 自检
    blob = open(out_path, "rb").read()
    assert blob[:4] == FAT_MAGIC_BE
    count = struct.unpack(">I", blob[4:8])[0]
    assert count == n, "切片数不对"
    print("FAT written: %s (%d slices, %d bytes)" % (out_path, count, len(blob)))
    for i in range(count):
        off = HEADER_SIZE + i * ARCH_SIZE
        cpu, sub, o, sz, al = struct.unpack(">IIIII", blob[off:off + ARCH_SIZE])
        print("  slice %d: cputype=%#x subtype=%#x offset=%d size=%d"
              % (i, cpu, sub, o, sz))


if __name__ == "__main__":
    main(sys.argv)
