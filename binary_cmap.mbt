// Copyright 2012 Mozilla Foundation
// Licensed under the Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0
// Based on PDF.js src/core/binary_cmap.js at revision
// 89b500f5e1d98ed89bb90211e45b28730b2d99ac.

///|
priv suberror PdfBinaryCMapError {
  InvalidBinaryCMap
} derive(Debug)

///|
priv struct PdfBinaryCMapStream {
  bytes : BytesView
  mut offset : Int
}

///|
fn PdfBinaryCMapStream::byte(
  self : PdfBinaryCMapStream,
) -> Int raise PdfBinaryCMapError {
  guard self.offset < self.bytes.length() else { raise InvalidBinaryCMap }
  let value = self.bytes[self.offset].to_int()
  self.offset += 1
  value
}

///|
fn PdfBinaryCMapStream::number(
  self : PdfBinaryCMapStream,
) -> UInt raise PdfBinaryCMapError {
  let mut value = 0U
  for _ in 0..<5 {
    let byte = self.byte()
    guard value <= 0x01FFFFFFU else { raise InvalidBinaryCMap }
    value = (value << 7) | (byte & 127).reinterpret_as_uint()
    if (byte & 128) == 0 {
      return value
    }
  }
  raise InvalidBinaryCMap
}

///|
fn PdfBinaryCMapStream::signed(
  self : PdfBinaryCMapStream,
) -> Int raise PdfBinaryCMapError {
  let value = self.number()
  let magnitude = (value >> 1).reinterpret_as_int()
  if (value & 1U) == 0U {
    magnitude
  } else {
    -magnitude - 1
  }
}

///|
fn PdfBinaryCMapStream::hex(
  self : PdfBinaryCMapStream,
  length : Int,
) -> Bytes raise PdfBinaryCMapError {
  guard length > 0 && length <= self.bytes.length() - self.offset else {
    raise InvalidBinaryCMap
  }
  let value = self.bytes[self.offset:self.offset + length].to_owned()
  self.offset += length
  value
}

///|
/// Decode a base-128 number modulo the requested byte width, as PDF.js does.
fn PdfBinaryCMapStream::hex_number(
  self : PdfBinaryCMapStream,
  length : Int,
) -> Bytes raise PdfBinaryCMapError {
  guard length > 0 && length <= 16 else { raise InvalidBinaryCMap }
  let bytes = Array::make(length, b'\x00')
  for _ in 0..<19 {
    let byte = self.byte()
    let mut carry = byte & 127
    for index in 0..<length {
      let target = length - 1 - index
      let value = bytes[target].to_int() * 128 + carry
      bytes[target] = (value & 255).to_byte()
      carry = value >> 8
    }
    if (byte & 128) == 0 {
      return Bytes::from_array(bytes)
    }
  }
  raise InvalidBinaryCMap
}

///|
fn PdfBinaryCMapStream::hex_signed(
  self : PdfBinaryCMapStream,
  length : Int,
) -> Bytes raise PdfBinaryCMapError {
  let bytes = self.hex_number(length)
  let sign = if (bytes[length - 1].to_int() & 1) == 1 { 255 } else { 0 }
  let output = Array::make(length, b'\x00')
  let mut carry = 0
  for index in 0..<length {
    carry = ((carry & 1) << 8) | bytes[index].to_int()
    output[index] = ((carry >> 1) ^ sign).to_byte()
  }
  Bytes::from_array(output)
}

///|
fn PdfBinaryCMapStream::text(
  self : PdfBinaryCMapStream,
) -> String raise PdfBinaryCMapError {
  let length = self.number()
  guard length <= 1_000_000U &&
    length <= (self.bytes.length() - self.offset).reinterpret_as_uint() else {
    raise InvalidBinaryCMap
  }
  let codepoints : Array[Int] = []
  for _ in 0..<length.reinterpret_as_int() {
    let value = self.number()
    guard value <= 0xFFFFU else { raise InvalidBinaryCMap }
    codepoints.push(value.reinterpret_as_int())
  }
  @utf8.decode(@pdflite.pdf_utf8_of_codepoints(codepoints)) catch {
    _ => raise InvalidBinaryCMap
  }
}

///|
fn pdf_cmap_hex_add(first : BytesView, second : BytesView) -> Bytes {
  let output = Array::make(first.length(), b'\x00')
  let mut carry = 0
  for index in 0..<first.length() {
    let target = first.length() - 1 - index
    carry += first[target].to_int() + second[target].to_int()
    output[target] = (carry & 255).to_byte()
    carry = carry >> 8
  }
  Bytes::from_array(output)
}

///|
fn pdf_cmap_hex_increment(bytes : BytesView) -> Bytes {
  let output = Array::make(bytes.length(), b'\x00')
  let mut carry = 1
  for index in 0..<bytes.length() {
    let target = bytes.length() - 1 - index
    let value = bytes[target].to_int() + carry
    output[target] = (value & 255).to_byte()
    carry = value >> 8
  }
  Bytes::from_array(output)
}

///|
fn pdf_cmap_hex_code(bytes : BytesView) -> UInt {
  let mut value = 0U
  for byte in bytes {
    value = (value << 8) | byte.to_int().reinterpret_as_uint()
  }
  value
}

///|
priv struct PdfCMapCIDRange {
  first : UInt
  last : UInt
  cid : Int
}

///|
priv struct PdfBuiltinCMap {
  vertical : Bool
  codespaces : Array[@pdflite.PdfCMapCodeSpace]
  cid_chars : Map[Int, Int]
  cid_ranges : Array[PdfCMapCIDRange]
  unicode_chars : Map[Int, Bytes]
  mut usecmap : String?
}

///|
fn pdf_parse_binary_cmap(
  bytes : BytesView,
) -> PdfBuiltinCMap raise PdfBinaryCMapError {
  let stream = PdfBinaryCMapStream::{ bytes, offset: 0, }
  let result : PdfBuiltinCMap = {
    vertical: (stream.byte() & 1) == 1,
    codespaces: [],
    cid_chars: Map([]),
    cid_ranges: [],
    unicode_chars: Map([]),
    usecmap: None,
  }
  while stream.offset < bytes.length() {
    let header = stream.byte()
    let kind = header >> 5
    if kind == 7 {
      match header & 31 {
        0 => ignore(stream.text())
        1 => result.usecmap = Some(stream.text())
        _ => raise InvalidBinaryCMap
      }
      continue
    }
    let sequence = (header & 16) != 0
    let length = (header & 15) + 1
    let count = stream.number()
    guard count <= 1_000_000U else { raise InvalidBinaryCMap }
    if count == 0U {
      continue
    }
    match kind {
      0 | 1 | 3 => {
        guard length <= 4 else { raise InvalidBinaryCMap }
        let mut start = stream.hex(length)
        let mut end = pdf_cmap_hex_add(start, stream.hex_number(length))
        for index in 0..<count.reinterpret_as_int() {
          if index > 0 {
            let next = pdf_cmap_hex_increment(end)
            start = if kind == 3 && sequence {
              next
            } else {
              pdf_cmap_hex_add(next, stream.hex_number(length))
            }
            end = pdf_cmap_hex_add(start, stream.hex_number(length))
          }
          let first = pdf_cmap_hex_code(start)
          let last = pdf_cmap_hex_code(end)
          guard first <= last else { raise InvalidBinaryCMap }
          match kind {
            0 =>
              result.codespaces.push({
                length,
                first: first.reinterpret_as_int(),
                last: last.reinterpret_as_int(),
              })
            1 => ignore(stream.number())
            _ => {
              let cid = stream.number()
              guard cid <= 0x7FFFFFFFU else { raise InvalidBinaryCMap }
              result.cid_ranges.push({
                first,
                last,
                cid: cid.reinterpret_as_int(),
              })
            }
          }
        }
      }
      2 => {
        guard length <= 4 else { raise InvalidBinaryCMap }
        let mut character = stream.hex(length)
        let value = stream.number()
        guard value <= 0x7FFFFFFFU else { raise InvalidBinaryCMap }
        let mut cid = value.reinterpret_as_int()
        result.cid_chars[pdf_cmap_hex_code(character).reinterpret_as_int()] = cid
        for _ in 1..<count.reinterpret_as_int() {
          character = pdf_cmap_hex_increment(character)
          if !sequence {
            character = pdf_cmap_hex_add(character, stream.hex_number(length))
          }
          cid = cid + 1 + stream.signed()
          result.cid_chars[pdf_cmap_hex_code(character).reinterpret_as_int()] = cid
        }
      }
      4 => {
        let mut character = stream.hex(2)
        let mut unicode = stream.hex(length)
        result.unicode_chars[pdf_cmap_hex_code(character).reinterpret_as_int()] = unicode
        for _ in 1..<count.reinterpret_as_int() {
          character = pdf_cmap_hex_increment(character)
          if !sequence {
            character = pdf_cmap_hex_add(character, stream.hex_number(2))
          }
          unicode = pdf_cmap_hex_add(
            pdf_cmap_hex_increment(unicode),
            stream.hex_signed(length),
          )
          result.unicode_chars[pdf_cmap_hex_code(character).reinterpret_as_int()] = unicode
        }
      }
      5 => {
        let mut start = stream.hex(2)
        let mut end = pdf_cmap_hex_add(start, stream.hex_number(2))
        let mut unicode = stream.hex(length)
        for index in 0..<count.reinterpret_as_int() {
          if index > 0 {
            let next = pdf_cmap_hex_increment(end)
            start = if sequence {
              next
            } else {
              pdf_cmap_hex_add(next, stream.hex_number(2))
            }
            end = pdf_cmap_hex_add(start, stream.hex_number(2))
            unicode = stream.hex(length)
          }
          let first = pdf_cmap_hex_code(start).reinterpret_as_int()
          let last = pdf_cmap_hex_code(end).reinterpret_as_int()
          guard first <= last else { raise InvalidBinaryCMap }
          for code in first..<=last {
            result.unicode_chars[code] = unicode
            unicode = pdf_cmap_hex_increment(unicode)
          }
        }
      }
      _ => raise InvalidBinaryCMap
    }
  }
  result
}
