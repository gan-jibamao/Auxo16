#!/usr/bin/env python3
"""架构门禁：确认包内 dylib 真的含有 arm64 切片。

用法: python3 tools/verify_arch.py <dylib路径>
"""
import struct
import sys

CPU_TYPE_ARM64 = 0x0100000C
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_LE = 0xBEBAFECA


def main(path: str) -> int:
    data = open(path, "rb").read()
    magic = struct.unpack("<I", data[:4])[0]

    if magic in (FAT_MAGIC, FAT_MAGIC_LE):
        count = struct.unpack(">I", data[4:8])[0]
        print("FAT binary, %d slices" % count)
        found = False
        for i in range(count):
            off = 8 + i * 20
            cputype, cpusub, offset, size, align = struct.unpack(
                ">iiIII", data[off:off + 20]
            )
            name = "arm64" if cputype == CPU_TYPE_ARM64 else hex(cputype)
            print("  slice %d: cputype=%s subtype=%#x size=%d"
                  % (i, name, cpusub & 0xFFFFFFFF, size))
            if cputype == CPU_TYPE_ARM64:
                found = True
        if not found:
            print("GATE FAIL: no arm64 slice present")
            return 1
    else:
        cputype, cpusub, filetype = struct.unpack("<iiI", data[4:16])
        print("thin binary: cputype=%#x subtype=%#x filetype=%d"
              % (cputype, cpusub, filetype))
        if cputype != CPU_TYPE_ARM64:
            print("GATE FAIL: not arm64")
            return 1

    print(">>> ARCH GATE PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
