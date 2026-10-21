import 'dart:io';
import 'dart:typed_data';

/// Ảnh minh họa DEMO bằng hình học, không giả làm ảnh chụp thật.
/// Tạo PNG bằng thư viện Dart sẵn có; không cần cài công cụ bên ngoài.
Future<void> createDemoClosureImage() async {
  const width = 384, height = 216;
  final pixels = Uint8List(width * height * 3);
  void rect(int x, int y, int w, int h, List<int> color) {
    for (var py = y; py < y + h; py++) {
      for (var px = x; px < x + w; px++) {
        if (px < 0 || py < 0 || px >= width || py >= height) continue;
        final i = (py * width + px) * 3;
        pixels[i] = color[0];
        pixels[i + 1] = color[1];
        pixels[i + 2] = color[2];
      }
    }
  }

  rect(0, 0, width, height, [242, 238, 222]);
  rect(0, 0, width, 65, [35, 85, 68]);
  rect(268, 12, 94, 42, [213, 233, 224]);
  rect(313, 12, 4, 42, [35, 85, 68]);
  rect(268, 31, 94, 4, [35, 85, 68]);
  const letters = {
    'D': ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
    'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
    'M': ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
    'O': ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
  };
  var cursor = 22;
  for (final letter in 'DEMO'.split('')) {
    final glyph = letters[letter]!;
    for (var y = 0; y < 7; y++) {
      for (var x = 0; x < 5; x++) {
        if (glyph[y][x] == '1') {
          rect(cursor + x * 5, 15 + y * 5, 5, 5, [222, 241, 166]);
        }
      }
    }
    cursor += 31;
  }
  for (final x in [55, 170, 285]) {
    for (final y in [108, 175]) {
      rect(x - 19, y - 25, 38, 10, [62, 102, 78]);
      rect(x - 19, y + 15, 38, 10, [62, 102, 78]);
      rect(x - 30, y - 14, 60, 28, [162, 112, 66]);
      rect(x - 25, y - 10, 50, 20, [196, 151, 96]);
      rect(x - 2, y - 6, 4, 12, [239, 235, 220]);
    }
  }
  rect(354, 104, 20, 82, [63, 106, 79]);
  rect(350, 169, 28, 28, [153, 102, 66]);
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    raw.add(pixels.sublist(y * width * 3, (y + 1) * width * 3));
  }
  int crc32(List<int> data) {
    var crc = 0xffffffff;
    for (final b in data) {
      crc ^= b;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  final png = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final content = [...type.codeUnits, ...data];
    png.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    png.add(content);
    png.add((ByteData(4)..setUint32(0, crc32(content))).buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibCodec().encode(raw.toBytes()));
  chunk('IEND', []);
  final file = File('database/demo_assets/closure_sample.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png.toBytes(), flush: true);
}
