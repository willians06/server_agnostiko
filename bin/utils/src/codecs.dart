import "dart:typed_data";

/// Convierte una cadena de caracteres HEX a una lista de bytes de 8 bits.
///
/// La conversión se hace en pares de caracteres, donde cada par hexadecimal
/// representa 1 byte de 8 bits en binario.
///
/// Falla con [FormatException] si la longitud de la cadena no es par o si la
/// cadena contiene algún dígito inválido.
Uint8List strHexToBytes(String strHex) {
  if (strHex.length.isOdd) {
    throw FormatException(
        "La cadena hexadecimal '$strHex' no tiene longitud par. " +
            "No puede convertirse directamente a bytes. " +
            "Verifique el valor de dicha cadena.");
  }

  int bytesLen = strHex.length ~/ 2;

  final bytes = Uint8List(bytesLen);
  for (int i = 0; i < strHex.length; i += 2) {
    final byteStr = strHex.substring(i, i + 2);
    final byteValue = int.parse(byteStr, radix: 16);
    bytes[i ~/ 2] = byteValue;
  }
  return bytes;
}

/// Convierte una lista de bytes de 8 bits a una cadena hexadecimal.
///
/// La conversión se hace en pares de caracteres, donde cada par hexadecimal
/// representa 1 byte de 8 bits en binario.
String bytesToHexStr(Uint8List bytes) {
  var value = "";

  for (final byte in bytes) {
    value += byte.toRadixString(16).padLeft(2, '0');
  }

  return value;
}

/// Convierte una cadena númerica a formato BCD **unpacked**.
///
/// Dicho formato directamente codifica cada dígito en el rango 1-9 en
/// 1 byte de 8 bits. Además, no se manejan signos en este formato.
///
/// Ej: la cadena "4321" pasa a ser los bytes => (0x04, 0x03, 0x02, 0x01).
///
/// Falla con [FormatException] si la cadena contiene algún dígito inválido.
Uint8List strToBcdUnpacked(String str) {
  var digits = str.split('');

  int bcdLen = digits.length;
  Uint8List bcd = Uint8List(bcdLen);

  for (int i = 0; i < str.length; i += 1) {
    String digit = digits.elementAt(i);
    int value = int.parse(digit);

    bcd[i] = value;
  }

  return bcd;
}

/// Convierte una lista de bytes en formato BCD **unpacked** a cadena númerica.
///
/// Falla con [FormatException] si los bytes contienen algún dígito inválido.
String bcdUnpackedToStr(Uint8List bytes) {
  var str = "";

  for (int byte in bytes) {
    if (byte > 9) {
      throw FormatException(
          "El formato BCD solo soporta bytes con un valor en rango 0-9.");
    }

    str += byte.toString();
  }

  return str;
}

/// Convierte una cadena númerica a formato BCD **packed** SIN signo.
///
/// Este formato utiliza 1 byte de 8 bits para representar 2 dígitos decimales.
/// De otra manera, se puede decir que cada nibble(4 bits) representa 1 dígito.
///
/// Ej: la cadena "4321" pasa a ser la lista de bytes => (0x43, 0x21).
///
/// Esta versión de algoritmo para formato BCD **packed** no maneja signo
/// para la cifra. Esta versión se justifica a la derecha y en caso de que se
/// tenga un número impar de dígitos se completa a la izquierda con un nibble
/// de valor '0000'.
///
/// Ej: la cadena "127" pasa a ser la lista de bytes => (0x01, 0x27).
///
/// Falla con [FormatException] si la cadena contiene algún dígito inválido.
///
/// Para mayor información:
/// https://en.wikipedia.org/wiki/Binary-coded_decimal#Packed_BCD
Uint8List strToBcdPackedUnsigned(String str) {
  var digits = str.split('');

  if (digits.length.isOdd) digits.insert(0, "0");

  int bcdLen = digits.length ~/ 2;
  Uint8List bcd = Uint8List(bcdLen);

  for (int i = 0; i < str.length; i += 2) {
    String firstDigit = digits.elementAt(i);
    int firstValue = int.parse(firstDigit) << 4;

    String secondDigit = digits.elementAt(i + 1);
    int secondValue = int.parse(secondDigit);

    int combinedValue = firstValue | secondValue;

    bcd[i ~/ 2] = combinedValue;
  }

  return bcd;
}

/// Decodifica una lista de bytes en formato BCD **packed** SIN signo.
///
/// Este formato utiliza 1 byte de 8 bits para representar 2 dígitos decimales.
/// De otra manera, se puede decir que cada nibble(4 bits) representa 1 dígito.
///
/// Ej: los bytes (0x43, 0x21) pasan a ser el String => "4321".
///
/// Esta versión de algoritmo para formato BCD **packed** no maneja signo
/// para la cifra.
///
/// Ej: los bytes (0x01, 0x27) pasan a ser el String => "0127".
///
/// Para mayor información:
/// https://en.wikipedia.org/wiki/Binary-coded_decimal#Packed_BCD
String bcdPackedUnsignedToStr(Uint8List bytes) {
  var str = "";

  for (int byte in bytes) {
    str += byte.toRadixString(16).padLeft(2, '0');
  }

  return str;
}

/// Convierte una cadena númerica a formato BCD **packed** con signo.
///
/// Este formato utiliza 1 byte de 8 bits para representar 2 dígitos decimales.
/// De otra manera, se puede decir que cada nibble(4 bits) representa 1 dígito.
///
/// Ej: la cadena "4321" pasa a ser la lista de bytes => (0x43, 0x21).
///
/// Si el número de dígitos es impar, sobrará un nibble que se utiliza para
/// representar el signo de la cifra (+: positivo o -: negativo).
/// Dicho valor es 0xC para números positivos y 0xD para negativos.
///
/// Por defecto, a falta de signo el valor se toma como positivo.
///
/// Sin embargo, es válido que la cadena empiece con el signo '+' o el
/// caracter 'C' para representar números positivos. Por otro lado,
/// el signo '-' o el caracter 'D' permiten representar números negativos.
///
/// Ej: la cadena "127" pasa a ser la lista de bytes => (0x12, 0x7C).
/// Ej: la cadena "+127" o "C127" pasa a ser la lista de bytes => (0x12, 0x7C).
/// Ej: la cadena "-127" o "D127" pasa a ser la lista de bytes => (0x12, 0x7D).
///
/// Por último, si el número de dígitos es par no entra la representación del
/// signo así que el valor será representado positivo en todo caso.
///
/// Ej: la cadena "C9999" pasa a ser la lista de bytes => (0x99, 0x99).
/// Ej: la cadena "D9999" pasa a ser la lista de bytes => (0x99, 0x99).
///
/// Falla con [FormatException] si la cadena contiene algún dígito inválido.
///
/// Para mayor información:
/// https://en.wikipedia.org/wiki/Binary-coded_decimal#Packed_BCD
Uint8List strToBcdPackedSigned(String str) {
  var digits = str.split('');

  bool isNegativeNumber = false;
  if (digits.first == "+" || digits.first.toUpperCase() == "C") {
    digits.removeAt(0);
  } else if (digits.first == "-" || digits.first.toUpperCase() == "D") {
    digits.removeAt(0);
    isNegativeNumber = true;
  }

  int bcdLen =
      digits.length.isEven ? digits.length ~/ 2 : (digits.length + 1) ~/ 2;

  Uint8List bcd = Uint8List(bcdLen);

  for (int i = 0; i < digits.length; i += 2) {
    String firstDigit = digits.elementAt(i);
    int firstValue = int.parse(firstDigit) << 4;

    String secondDigit;
    try {
      secondDigit = digits.elementAt(i + 1);
    } on RangeError {
      secondDigit = isNegativeNumber ? "13" : "12";
    }
    int secondValue = int.parse(secondDigit);

    int combinedValue = firstValue | secondValue;

    bcd[i ~/ 2] = combinedValue;
  }

  return bcd;
}

/// Decodifica una lista de bytes en formato BCD **packed** CON signo.
///
/// Este formato utiliza 1 byte de 8 bits para representar 2 dígitos decimales.
/// De otra manera, se puede decir que cada nibble(4 bits) representa 1 dígito.
///
/// Ej: los bytes (0x43, 0x21) pasan a ser el String => "4321".
///
/// Si el número de dígitos representados es impar, el último nibble se utiliza
/// para representar el signo de la cifra (+: positivo o -: negativo).
/// Dicho valor es 0xC para números positivos y 0xD para negativos.
///
/// Ej: los bytes (0x12, 0x7C) pasan a ser el String => "C127".
/// Ej: los bytes (0x12, 0x7D) pasan a ser el String => "D127".
///
/// En cambio, si el número de dígitos representados es par entonces el valor
/// no trae signo y se decodifica tal cuál sin signo.
///
/// Ej: los bytes (0x12, 0x34) pasan a ser el String => "1234".
/// Ej: los bytes (0x05, 0x67) pasan a ser el String => "0567".
///
/// Para mayor información:
/// https://en.wikipedia.org/wiki/Binary-coded_decimal#Packed_BCD
String bcdPackedSignedToStr(Uint8List bytes) {
  String str = "";

  // En este formato por lo general el último nibble contiene el signo del
  // valor decimal codificado
  int lastNibble = bytes.last & 0x0F;
  bool hasSign = lastNibble >= 0x0A;
  bool isNegativeNumber = lastNibble == 0x0D;

  // Si el último nibble contenía signo entonces hay que pasar a '0' el último
  // byte y desplazarlo para obtener el último dígito del número representado.
  // Además, guardamos el dígito para agregarlo en última posición sin paddear
  // con 0s como con el resto de dígitos procesados en el loop.
  String lastDigit = "";
  if (hasSign) {
    int lastNumber = (bytes.last & 0xF0) >> 4;
    lastDigit = lastNumber.toString();
    bytes = Uint8List.fromList(bytes.sublist(0, bytes.length - 1));
  }

  for (int byte in bytes) {
    str += byte.toRadixString(16).padLeft(2, '0');
  }

  if (hasSign) {
    str += lastDigit;
    str = isNegativeNumber ? "D$str" : "C$str";
  }

  return str;
}

/// Decodifica una lista de datos tipo "num" (array JSON) a lista de bytes.
Uint8List jsonListToBytes(List<dynamic> jsonList) {
  final list = List<int>.from(jsonList);
  return Uint8List.fromList(list);
}

/// Convierte un valor 'int' a una representación hexadecimal en bytes de 8bits.
///
/// Ej: un 'int' con valor = '925'(decimal) -> '0x39d'(hexadecimal) pasa a ser
/// la lista de bytes: (0x03, 0x9d).
Uint8List intToUint8List(int value) {
  var str = value.toRadixString(16);
  str = str.length % 2 == 0 ? str : "0$str";

  return strHexToBytes(str);
}

/// Retorna los bytes que representan la longitud (la 'L' de TLV) en formato
/// BER-TLV a partir de su valor decimal.
///
/// La implementación es acorde a lo estipulado en el Libro 3 de la
/// especificación EMV - *ANEXO B2 (Coding of the Length Field of BER-TLV Data
/// Objects).*
///
/// Para más información sobre el codificado de dichos bytes de longitud, por
/// favor referirse a dicho anexo.
Uint8List intToBerTlvLen(int len) {
  if (len <= 127) {
    return Uint8List.fromList([len]);
  }

  // Máscara para que el bit b8 del byte más significativo sea = '1' lo cuál
  // indica que la longitud requiere más de 1 byte para su representación ya
  // que su valor es mayor que '127'.
  int mask = 0x80;

  // El resto de bytes son los que codifican la longitud en este caso.
  final lenBytes = List<int>.from(intToUint8List(len));

  // El primer byte contiene el indicador (el bit b8 en '1') y los bits del b7
  // a b1 codifican el número de bytes subsecuentes realmente utilizados para
  // la longitud del valor de TLV.
  int firstByte = mask | lenBytes.length;

  final bytes = [firstByte] + lenBytes;

  return Uint8List.fromList(bytes);
}

extension BytesToAndFromString on Uint8List {
  /// Retorna una cadena HEX donde cada caracter representa un nibble.
  String toHexStr() {
    return bytesToHexStr(this);
  }

  /// Crea una lista de bytes desde un texto con formato HEX.
  static Uint8List fromHexStr(String strHex) {
    return strHexToBytes(strHex);
  }
}

extension StringToAndFromBytes on String {
  /// Retorna una lista de bytes de 8 bits a partir de un texto HEX.
  Uint8List toHexBytes() {
    return strHexToBytes(this);
  }

  /// Crea una cadena de caracteres HEX desde una lista de bytes.
  static String fromHexBytes(Uint8List bytes) {
    return bytesToHexStr(bytes);
  }
}

extension HexPrinting on Uint8List {
  /// Imprime en consola la lista de bytes representados en hexadecimal.
  void printAsHex() {
    int lineWidth = 20;
    for (int i = 0; i < this.length; i += lineWidth) {
      int end = i + lineWidth <= this.length ? i + lineWidth : this.length;
      final sub = this.sublist(i, end);
      final subStr = sub.map((val) => val.toRadixString(16).padLeft(2, '0'));
      final hexStr = subStr.join(" ");

      final str = "${i.toString().padLeft(3, '0')}: $hexStr";
      print(str);
    }
  }
}

/// Valida la 'paridad'='impar' de 1 byte (0-255) de acuerdo a sus bits.
///
/// La 'paridad' se determina mediante el número de bits = '1'.
bool checkOddParity(int byte) {
  return _bitsOnLookupTable[byte].isOdd;
}

/// Valida la 'paridad'='par' de 1 byte (0-255) de acuerdo a sus bits.
///
/// La 'paridad' se determina mediante el número de bits = '1'.
bool checkEvenParity(int byte) {
  return _bitsOnLookupTable[byte].isEven;
}

/// Agrega 1 bit de 'paridad'='impar' a un byte de acuerdo a sus bits.
///
/// Ej: Si [byte] en bits es '110'(par) esta función retornaría '1101' (impar)
/// y si [byte] es '1011'(impar) se retornaría '10110'(impar).
int applyOddParity(int byte) {
  final value = byte << 1;
  return checkOddParity(value) ? value : (value | 0x01);
}

/// Agrega 1 bit de 'paridad'='par' a un byte de acuerdo a sus bits.
///
/// Ej: Si [byte] en bits es '1011'(impar) esta función retornaría '11011' (par)
/// y si [byte] es '110'(par) se retornaría '1100'(par).
int applyEvenParity(int byte) {
  final value = byte << 1;
  return checkEvenParity(value) ? value : (value | 0x01);
}

/// Permite saber la cantidad de bits con valor '1' en un byte en el rango 0-255
List<int> _bitsOnLookupTable = [
  0,
  1,
  1,
  2,
  1,
  2,
  2,
  3,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  5,
  6,
  6,
  7,
  6,
  7,
  7,
  8
];
