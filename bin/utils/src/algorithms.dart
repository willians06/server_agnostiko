import 'dart:typed_data';
import 'codecs.dart';

/// Algoritmo para verificar números PAN de Tarjetas de Débito/Crédito.
///
/// Este algoritmo se conoce como "Algoritmo de Luhn" o "Algoritmo de módulo 10"
/// y se utiliza para verificar números de identificación (el número PAN de una
/// tarjeta financiera en este caso).
///
/// Este método lanza un [FormatException] si el valor [pan] contiene
/// caracteres fuera del rango númerico 0-9.
///
/// Para más información sobre el algoritmo:
/// https://www.geeksforgeeks.org/luhn-algorithm/
bool checkLuhn(String pan) {
  int sum = int.parse(pan[pan.length - 1]);
  int digitsCount = pan.length;
  int parity = digitsCount % 2;

  for (int i = 0; i <= digitsCount - 2; i++) {
    int digit = int.parse(pan[i]);

    if (i % 2 == parity) digit = digit * 2;
    if (digit > 9) digit = digit - 9;

    sum = sum + digit;
  }

  return ((sum % 10) == 0);
}

Uint8List calculateCRC32(Uint8List data) {
  int crc, mask;
  int i = 0;
  crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = crc ^ byte;
    for (int j = 7; j >= 0; j--) {
      // Do eight times.
      mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xEDB88320 & mask);
    }
    i = i + 1;
  }
  return (~crc)
      .toUnsigned(4 * 8) // necesario para un valor correcto (4 bytes * 8 bits)
      .toRadixString(16)
      .padLeft(8, "0")
      .toHexBytes();
}
