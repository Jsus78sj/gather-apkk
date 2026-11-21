import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ZipBuildEntry {
  final String path;
  final Uint8List bytes;
  final DateTime? modifiedAt;

  const ZipBuildEntry({
    required this.path,
    required this.bytes,
    this.modifiedAt,
  });
}

/// بانٍ خفيف لأرشيفات ZIP متوافق مع PKWARE APPNOTE (UTF-8 + CRC32 + STORE/DEFLATE).
abstract final class SimpleZipBuilder {
  static const int _flagUtf8 = 0x0800;
  static const int _methodStore = 0;
  static const int _methodDeflate = 8;

  static final Uint32List _crcTable = _buildCrcTable();

  static Uint8List build(List<ZipBuildEntry> entries) {
    final out = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    final rawDeflate = ZLibCodec(raw: true);
    var offset = 0;
    var writtenCount = 0;

    for (final entry in entries) {
      final normalized = _normalizePath(entry.path);
      if (normalized.isEmpty) continue;

      final nameBytes = Uint8List.fromList(utf8.encode(normalized));
      final raw = entry.bytes;
      final crc = crc32(raw);

      var method = _methodStore;
      var payload = raw;
      if (raw.isNotEmpty) {
        final compressed = Uint8List.fromList(rawDeflate.encode(raw));
        if (compressed.length < raw.length) {
          method = _methodDeflate;
          payload = compressed;
        }
      }

      final (dosTime, dosDate) = _encodeDosDateTime(entry.modifiedAt);

      // Local File Header (30 bytes + filename)
      final local = ByteData(30);
      local.setUint32(0, 0x04034B50, Endian.little);
      local.setUint16(4, 20, Endian.little);
      local.setUint16(6, _flagUtf8, Endian.little);
      local.setUint16(8, method, Endian.little);
      local.setUint16(10, dosTime, Endian.little);
      local.setUint16(12, dosDate, Endian.little);
      local.setUint32(14, crc, Endian.little);
      local.setUint32(18, payload.length, Endian.little);
      local.setUint32(22, raw.length, Endian.little);
      local.setUint16(26, nameBytes.length, Endian.little);
      local.setUint16(28, 0, Endian.little);

      out.add(local.buffer.asUint8List());
      out.add(nameBytes);
      out.add(payload);

      // Central Directory Header (46 bytes + filename)
      final cd = ByteData(46);
      cd.setUint32(0, 0x02014B50, Endian.little);
      cd.setUint16(4, 20, Endian.little);
      cd.setUint16(6, 20, Endian.little);
      cd.setUint16(8, _flagUtf8, Endian.little);
      cd.setUint16(10, method, Endian.little);
      cd.setUint16(12, dosTime, Endian.little);
      cd.setUint16(14, dosDate, Endian.little);
      cd.setUint32(16, crc, Endian.little);
      cd.setUint32(20, payload.length, Endian.little);
      cd.setUint32(24, raw.length, Endian.little);
      cd.setUint16(28, nameBytes.length, Endian.little);
      cd.setUint16(30, 0, Endian.little);
      cd.setUint16(32, 0, Endian.little);
      cd.setUint16(34, 0, Endian.little);
      cd.setUint16(36, 0, Endian.little);
      cd.setUint32(38, 0, Endian.little);
      cd.setUint32(42, offset, Endian.little);

      central.add(cd.buffer.asUint8List());
      central.add(nameBytes);

      offset += 30 + nameBytes.length + payload.length;
      writtenCount++;
    }

    final centralBytes = central.takeBytes();
    out.add(centralBytes);

    // End of Central Directory Record (22 bytes)
    final eocd = ByteData(22);
    eocd.setUint32(0, 0x06054B50, Endian.little);
    eocd.setUint16(4, 0, Endian.little);
    eocd.setUint16(6, 0, Endian.little);
    eocd.setUint16(8, writtenCount, Endian.little);
    eocd.setUint16(10, writtenCount, Endian.little);
    eocd.setUint32(12, centralBytes.length, Endian.little);
    eocd.setUint32(16, offset, Endian.little);
    eocd.setUint16(20, 0, Endian.little);

    out.add(eocd.buffer.asUint8List());
    return out.takeBytes();
  }

  static int crc32(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < data.length; i++) {
      crc = _crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }

  static String _normalizePath(String path) {
    var value = path.replaceAll('\\', '/').trim();
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    return value;
  }

  static (int time, int date) _encodeDosDateTime(DateTime? modifiedAt) {
    final dt = (modifiedAt ?? DateTime.now()).toLocal();
    final year = (dt.year - 1980).clamp(0, 127);
    final dosDate = (year << 9) | (dt.month << 5) | dt.day;
    final dosTime = (dt.hour << 11) | (dt.minute << 5) | (dt.second >> 1);
    return (dosTime, dosDate);
  }
}
