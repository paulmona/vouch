// Just enough DER to read X.509 extensions and Android's KeyDescription.

export interface Tlv {
  cls: number; // 0 universal, 1 application, 2 context, 3 private
  constructed: boolean;
  tag: number;
  value: Buffer;
  end: number; // offset after this element in the buffer it was read from
}

export function read(buf: Buffer, offset = 0): Tlv {
  let p = offset;
  const byte = () => {
    const b = buf[p++];
    if (b === undefined) throw new Error("DER: truncated");
    return b;
  };
  const first = byte();
  let tag = first & 0x1f;
  if (tag === 0x1f) {
    tag = 0;
    let b: number;
    do {
      b = byte();
      tag = tag * 128 + (b & 0x7f);
      if (tag > 0xffffff) throw new Error("DER: tag too large");
    } while (b & 0x80);
  }
  let len = byte();
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4) throw new Error("DER: bad length");
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + byte();
  }
  const end = p + len;
  if (end > buf.length) throw new Error("DER: truncated");
  return { cls: first >> 6, constructed: (first & 0x20) !== 0, tag, value: buf.subarray(p, end), end };
}

export function children(t: Tlv): Tlv[] {
  if (!t.constructed) throw new Error("DER: not constructed");
  const out: Tlv[] = [];
  for (let p = 0; p < t.value.length; ) {
    const c = read(t.value, p);
    out.push(c);
    p = c.end;
  }
  return out;
}

// INTEGER or ENUMERATED that fits in a safe integer (non-negative only).
export function int(t: Tlv): number {
  if (t.cls !== 0 || (t.tag !== 2 && t.tag !== 10)) throw new Error("DER: not an integer");
  if (t.value.length === 0 || t.value.length > 7 || (t.value[0]! & 0x80)) throw new Error("DER: unsupported integer");
  return t.value.reduce((n, b) => n * 256 + b, 0);
}
