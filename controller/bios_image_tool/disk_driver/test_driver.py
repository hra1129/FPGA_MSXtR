"""Run the disk_if driver of the DOS ROM on a Z80 model (pip install z80).

usage: python test_driver.py <rom> <2dd.dsk> <dos2|dos1>
    Run build_dos_rom.py first: the driver_<variant>.sym files are used.
    DSKIO/DSKCHG/GETDPB are called directly with a disk_if model that
    serves the 720KB image; kernel helpers (WA_HELPER, RDSLT, XFER)
    are emulated.
"""
import os
import re
import sys
import z80

ROM, DSK, VAR = sys.argv[1], sys.argv[2], sys.argv[3]
SYMBASE = "driver"
BANK = 0 if VAR == "dos2" else 3
WA_HELPER = 0x4DD8 if VAR == "dos2" else 0x5FC2
REG_HELPER = 0x4E09 if VAR == "dos2" else 0x5FF6
RDSLT = 0x000C
SENT = 0x0100
WA = 0xF100
SECBUF = 0xE000
DPB = 0xE800


def load_sym(path):
    s = {}
    for line in open(path):
        m = re.match(r"(\w+) equ 0*([0-9a-fA-F]+)h", line)
        if m:
            s[m.group(1)] = int(m.group(2), 16)
    return s


SYM = load_sym(os.path.join(os.path.dirname(os.path.abspath(__file__)), f"{SYMBASE}_{VAR}.sym"))


class DiskIf:
    def __init__(self, img):
        self.img = bytearray(img)
        self.buf = bytearray(512)
        self.ptr = 0
        self.busy = 0
        self.err = 0
        self.changed = 1
        self.ready = 1
        self.wprot = 0
        self.errcode = 0
        self.drive = 0
        self.media = 0
        self.sector = [0, 0, 0, 0]
        self.pend = None
        self.log = []

    def status(self):
        if self.busy:
            self.busy -= 1
            if self.busy == 0:
                self.complete()
                return self.status()
            return 0x80 | (self.err << 6) | (self.changed << 5) | (self.ready << 4) | (self.wprot << 3)
        return (self.err << 6) | (self.changed << 5) | (self.ready << 4) | (self.wprot << 3)

    def complete(self):
        cmd = self.pend
        lba = self.sector[0] | self.sector[1] << 8 | self.sector[2] << 16 | self.sector[3] << 24
        nsec = len(self.img) // 512
        self.ptr = 0
        if not self.ready or self.drive != 0:
            self.err, self.errcode = 1, 2
            return
        if lba >= nsec:
            self.err, self.errcode = 1, 8
            self.buf[:] = b"\xff" * 512
            return
        if cmd == 1:
            self.buf[:] = self.img[lba * 512:(lba + 1) * 512]
            self.err = 0
        else:
            if self.wprot:
                self.err, self.errcode = 1, 0
                return
            self.img[lba * 512:(lba + 1) * 512] = self.buf
            self.err = 0
        self.log.append(("RD" if cmd == 1 else "WR", lba))

    def read(self, a):
        if a == 0x7FF2:
            return self.status()
        if a == 0x7FF3:
            return self.drive
        if a == 0x7FF4:
            return self.media
        if 0x7FF5 <= a <= 0x7FF8:
            return self.sector[a - 0x7FF5]
        if a == 0x7FF9:
            if self.busy:
                return 0xFF
            v = self.buf[self.ptr]
            self.ptr = (self.ptr + 1) & 511
            return v
        if a == 0x7FFA:
            return self.errcode
        if a == 0x7FFB:
            return 0x01
        return 0xFF

    def write(self, a, v):
        if a == 0x7FF2:
            if self.busy:
                if v == 0x80:
                    self.busy, self.err, self.errcode, self.ptr = 0, 1, 2, 0
                return
            self.ptr = 0
            if v in (1, 2):
                self.pend, self.busy, self.err = v, 5, 0
            elif v == 0x10:
                self.changed = 0
            return
        if self.busy:
            return
        if a == 0x7FF3:
            self.drive = v
        elif a == 0x7FF4:
            self.media = v
        elif 0x7FF5 <= a <= 0x7FF8:
            self.sector[a - 0x7FF5] = v
        elif a == 0x7FF9:
            self.buf[self.ptr] = v
            self.ptr = (self.ptr + 1) & 511


class Machine:
    def __init__(self):
        self.m = z80.Z80Machine()
        rom = open(ROM, "rb").read()
        self.m.set_memory_block(0x4000, rom[BANK * 0x4000:(BANK + 1) * 0x4000])
        self.dif = DiskIf(open(DSK, "rb").read())
        mem = self.m.memory
        mem[0xF34D] = SECBUF & 0xFF
        mem[0xF34E] = SECBUF >> 8
        mem[0xFCC1] = 0x80
        self.a8 = 0xFC
        self.xfer = 0
        self.m.set_input_callback(self.io_in)
        self.m.set_output_callback(self.io_out)

    def io_in(self, port):
        port &= 0xFF
        if port == 0xA8:
            return self.a8
        return 0x00

    def io_out(self, port, v):
        if port & 0xFF == 0xA8:
            self.a8 = v

    def ret(self):
        m = self.m
        m.pc = m.memory[m.sp] | m.memory[m.sp + 1] << 8
        m.sp += 2

    def call(self, entry, a=0, f=0, bc=0, de=0, hl=0, limit=3000000):
        m = self.m
        m.sp = 0xF000
        m.sp -= 2
        m.memory[m.sp] = SENT & 0xFF
        m.memory[m.sp + 1] = SENT >> 8
        m.pc = entry
        m.af = a << 8 | f
        m.bc, m.de, m.hl = bc, de, hl
        m.ix = 0x1234
        steps = 0
        while True:
            pc = m.pc
            if pc == SENT:
                return m
            if pc == WA_HELPER:
                m.ix = WA
                m.hl = WA
                m.bc = 0x001B
                m.a = 0x5A
                self.ret()
                continue
            if pc == REG_HELPER:
                self.ret()
                continue
            if pc == RDSLT:
                m.a = 0x98
                self.ret()
                continue
            if pc == 0xF36E:
                n = m.bc
                blk = bytes(m.memory[m.hl:m.hl + n])
                m.set_memory_block(m.de, blk)
                m.hl, m.de, m.bc = m.hl + n, m.de + n, 0
                self.xfer += 1
                self.ret()
                continue
            mem = m.memory
            op = mem[pc]
            ad = mem[pc + 1] | mem[pc + 2] << 8
            if op == 0x3A and 0x7FF2 <= ad <= 0x7FFB:
                m.a = self.dif.read(ad)
                m.pc = pc + 3
            elif op == 0x32 and 0x7FF2 <= ad <= 0x7FFB:
                self.dif.write(ad, m.a)
                m.pc = pc + 3
            else:
                if 0x4000 <= pc < 0x8000:
                    assert not (op == 0x7E and 0x7FF2 <= m.hl <= 0x7FFB), "indirect reg access"
                m.ticks_to_stop = 1
                m.run()
            steps += 1
            if steps > limit:
                raise RuntimeError("runaway at %04X" % m.pc)


def cy(m):
    return m.f & 1


fails = []


def check(name, cond):
    print(("  ok   " if cond else "  FAIL ") + name)
    if not cond:
        fails.append(name)


mc = Machine()
m = mc.m
img = bytes(mc.dif.img)
sec = lambda n: img[n * 512:(n + 1) * 512]

print("INIENV")
mc.call(SYM["INIENV_BODY"])
check("IFPRESENT set", m.memory[WA] & 1 == 1)

print("DRIVES")
mc.call(SYM["DRIVES_BODY"], f=0x00)
check("L=2", m.l == 2)

print("DSKCHG (changed)")
mc.call(SYM["DSKCHG_BODY"], a=0, bc=0x00F9, hl=DPB)
check("Cy=0", not cy(m))
check("B=FFh", m.b == 0xFF)
check("C kept", m.c == 0xF9)
check("HL kept", m.hl == DPB)
check("CHANGED cleared", mc.dif.changed == 0)

print("GETDPB")
mc.call(SYM["GETDPB_BODY"], a=0, bc=0xF9F9, hl=DPB)
check("Cy=0", not cy(m))
dpb = bytes(m.memory[DPB + 1:DPB + 19])
print("  DPB+1:", dpb.hex(" "))
want = bytes([0xF9, 0x00, 0x02, 0x0F, 0x04, 0x01, 0x02, 0x01, 0x00, 0x02,
              0x70, 0x0E, 0x00, 0xCA, 0x02, 0x03, 0x07, 0x00])
check("DPB = standard 2DD", dpb == want)

print("DSKIO read 4 sectors (0..3) -> 9000h")
mc.dif.log.clear()
mc.call(SYM["DSKIO_BODY"], a=0, f=0, bc=0x04F9, de=0, hl=0x9000)
check("Cy=0", not cy(m))
check("data", bytes(m.memory[0x9000:0x9000 + 4 * 512]) == img[0:4 * 512])
check("log 0..3", mc.dif.log == [("RD", i) for i in range(4)])
check("work area intact", m.memory[WA] & 3 == 3)

print("DSKIO read 3 sectors (5..7) -> 5000h (page 1 via SECBUF)")
mc.dif.log.clear()
mc.call(SYM["DSKIO_BODY"], a=0, f=0, bc=0x03F9, de=5, hl=0x5000)
check("Cy=0", not cy(m))
check("data", bytes(m.memory[0x5000:0x5000 + 3 * 512]) == img[5 * 512:8 * 512])
check("log 5..7", mc.dif.log == [("RD", i) for i in range(5, 8)])
check("XFER used 3 times", mc.xfer == 3)

print("DSKIO write 2 sectors (30,31) <- 6000h (page 1 via SECBUF)")
pat1 = bytes((i * 13 + 5) & 0xFF for i in range(1024))
m.set_memory_block(0x6000, pat1)
mc.dif.log.clear()
mc.call(SYM["DSKIO_BODY"], a=0, f=1, bc=0x02F9, de=30, hl=0x6000)
check("Cy=0", not cy(m))
check("image updated", bytes(mc.dif.img[30 * 512:32 * 512]) == pat1)
check("log", mc.dif.log == [("WR", 30), ("WR", 31)])

print("DSKIO write 2 sectors (20,21) <- A000h")
pat = bytes((i * 7 + 3) & 0xFF for i in range(1024))
m.set_memory_block(0xA000, pat)
mc.dif.log.clear()
mc.call(SYM["DSKIO_BODY"], a=0, f=1, bc=0x02F9, de=20, hl=0xA000)
check("Cy=0", not cy(m))
check("image updated", bytes(mc.dif.img[20 * 512:22 * 512]) == pat)
check("log", mc.dif.log == [("WR", 20), ("WR", 21)])

print("GETDPB again (media already valid)")
m.set_memory_block(DPB, bytes(20))
mc.call(SYM["GETDPB_BODY"], a=1, bc=0xF9F9, hl=DPB)
check("Cy=0", not cy(m))
check("DPB = standard 2DD", bytes(m.memory[DPB + 1:DPB + 19]) == want)

print("DSKIO read beyond end (1439, 1440)")
mc.call(SYM["DSKIO_BODY"], a=0, f=0, bc=0x02F9, de=1439, hl=0x9000)
check("Cy=1", cy(m) == 1)
check("A=8", m.a == 8)
check("B=1 remaining", m.b == 1)

print("DSKCHG (unchanged)")
mc.call(SYM["DSKCHG_BODY"], a=0, bc=0x00F9, hl=DPB)
check("B=01h", m.b == 0x01 and not cy(m))

print("RESULT:", "PASS" if not fails else f"FAIL ({len(fails)})")
