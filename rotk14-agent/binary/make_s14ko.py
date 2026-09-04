#!/usr/bin/env python3
"""s14ko 신무장 파일 생성기 — rotk14-agent/binary/포맷.md 의 해석 결과를 그대로 쓴다.

체크섬이 없으므로 바이트를 직접 써넣으면 게임이 받아들인다(A/B 샘플로 확인).
ID 표가 아직 없어 개성·진형·전법은 **번호로만** 받는다.
"""
import struct

BASE = open(__file__.rsplit("/",1)[0] + "/samples/A.s14ko", "rb").read()

OFF = {"성":0x18, "명":0x1E, "자":0x24,
       "통솔":0x5E, "무력":0x5F, "지력":0x60, "정치":0x61, "매력":0x62,
       "개성":0x63, "전법":0x75, "진형":0x79}

def _name(buf, off, text):
    """UTF-16LE, 최대 3자. 남는 자리는 0 으로 채운다."""
    if len(text) > 3:
        raise ValueError(f"이름은 3자까지다: {text!r}")
    raw = text.encode("utf-16le")
    buf[off:off+6] = raw + b"\x00" * (6 - len(raw))

def build(성="", 명="", 자="", 통솔=50, 무력=50, 지력=50, 정치=50, 매력=50,
          개성=(), 진형=(), 전법=0):
    """개성·진형·전법은 ID 번호로 준다. 이름 표는 아직 없다."""
    b = bytearray(BASE)
    for k, v in (("성",성), ("명",명), ("자",자)):
        _name(b, OFF[k], v)
    for k, v in (("통솔",통솔), ("무력",무력), ("지력",지력), ("정치",정치), ("매력",매력)):
        if not 1 <= v <= 255:
            raise ValueError(f"{k} 범위를 벗어났다: {v}")
        b[OFF[k]] = v
    if len(개성) > 5: raise ValueError("개성은 5칸까지다")
    for i in range(5):
        struct.pack_into("<H", b, OFF["개성"] + 2*i, 개성[i] if i < len(개성) else 0)
    if len(진형) > 4: raise ValueError("진형은 4칸까지다")
    for i in range(4):
        b[OFF["진형"] + i] = 진형[i] if i < len(진형) else 0
    struct.pack_into("<H", b, OFF["전법"], 전법)
    return bytes(b)

def read(path):
    b = open(path, "rb").read()
    if b[:15] != b"SAN14EDITPERSON":
        raise ValueError("s14ko 파일이 아니다")
    def name(off): return b[off:off+6].decode("utf-16le").rstrip("\x00")
    return {
        "성": name(0x18), "명": name(0x1E), "자": name(0x24),
        "통솔": b[0x5E], "무력": b[0x5F], "지력": b[0x60],
        "정치": b[0x61], "매력": b[0x62],
        "개성": [struct.unpack_from("<H", b, 0x63 + 2*i)[0] for i in range(5)],
        "진형": list(b[0x79:0x7D]),
        "전법": struct.unpack_from("<H", b, 0x75)[0],
    }

if __name__ == "__main__":
    import sys, json
    if len(sys.argv) > 1:
        print(json.dumps(read(sys.argv[1]), ensure_ascii=False, indent=2))
