import "dart:convert";
import "dart:typed_data";

import "../../utils/utils.dart";

import "field_definition.dart";

/// Interfaz para la parametrización de como empacar/desempacar un campo ISO.
///
/// De acuerdo a cada implementación particular, hay distintas maneras de
/// representar e interpretar las distintas partes de un mensaje ISO para su
/// envío a través de la red.
///
/// Por ejemplo, los valores alfanúmericos pueden ser enviados en ASCII y los
/// valores númericos en otro formato más compacto como BCD.
///
/// -[pack] cumple la función de transformar la representación en texto de un
/// valor a una respectiva lista de bytes debidamente codificada para enviar.
///
/// Ej: Valor [str]="0210" después de invocar [pack] con algoritmo BCD pasa a
/// ser la lista de bytes (0x02, 0x10).
///
/// -[unpack] decodifica una lista de bytes a su respectivo valor en texto para
/// su manejo en el mensaje ISO.
///
/// Ej: La lista de bytes (0x31, 0x32, 0x33) con codificación ASCII pasa a ser
/// el valor de texto "123".
///
/// -[packedLen] retorna la longitud de campo en formato packed(ya codificado)
/// en función de su longitud original en formato de texto. Este método es
/// necesario para interpretar correctamente los campos de longitud fija la
/// cuál varía de su forma de texto cuando el campo está "empacado".
///
/// Ej: int packedLen(int len) => len % 2 == 0 ? len ~/ 2 : (len + 1) ~/ 2;
/// Para convertir la longitud en dígitos a bytes de un campo númerico empacado
/// en BCD. Nótese que esto se debe a que para un valor como "333" la longitud
/// es igual a 3, pero representado en bytes: (0x03, 0x03) su longitud es
/// igual a 2.
abstract class FieldPacker {
  Uint8List pack(String str);
  String unpack(Uint8List bytes);
  int packedLen(int len);
}

/// Empaqueta campos en formato de texto ASCII
class AsciiPacker implements FieldPacker {
  Uint8List pack(String str) => AsciiCodec().encode(str);
  String unpack(Uint8List bytes) => AsciiCodec().decode(bytes);
  int packedLen(int len) => len;
}

/// Empaqueta campos en formato binario a partir de una cadena hexadecimal
class BinaryPacker implements FieldPacker {
  Uint8List pack(String str) => strHexToBytes(str);
  String unpack(Uint8List bytes) => bytesToHexStr(bytes);
  int packedLen(int len) => len % 2 == 0 ? len ~/ 2 : (len + 1) ~/ 2;
}

/// Empaqueta campos númericos en formato BCD **packed** SIN signo
///
/// NOTA: Al hacer "unpack" del campo se eliminan los 0s a la izquierda.
/// Si el campo es de longitud fija dichos 0s serán recuperados al setear en
/// la estructura de mensaje.
class NumericFieldPacker extends FieldPacker {
  Uint8List pack(String str) => strToBcdPackedUnsigned(str);
  String unpack(Uint8List bytes) {
    String str = bcdPackedUnsignedToStr(bytes);

    // si solo contiene 0s entonces retornamos 1 carácter para '0'
    if (RegExp(r"^0*$").hasMatch(str)) return "0";

    // si no es solo 0s entonces...
    return str.replaceFirst(RegExp(r"^0+"), ""); //elimina los 0s a la izquierda
  }

  int packedLen(int len) => len % 2 == 0 ? len ~/ 2 : (len + 1) ~/ 2;
}

/// Empaqueta valores númericos en formato BCD **packed** SIN signo
class BcdPackedUnsignedPacker extends FieldPacker {
  Uint8List pack(String str) => strToBcdPackedUnsigned(str);
  String unpack(Uint8List bytes) => bcdPackedUnsignedToStr(bytes);
  int packedLen(int len) => len % 2 == 0 ? len ~/ 2 : (len + 1) ~/ 2;
}

/// Empaqueta valores númericos en formato BCD **packed** CON signo
class BcdPackedSignedPacker extends FieldPacker {
  Uint8List pack(String str) => strToBcdPackedSigned(str);
  String unpack(Uint8List bytes) => bcdPackedSignedToStr(bytes);
  int packedLen(int len) => len % 2 == 0 ? len ~/ 2 : (len + 1) ~/ 2;
}

final defaultMtiPacker = BcdPackedUnsignedPacker();

final defaultBitmapPacker = BinaryPacker();

final defaultLenPacker = BcdPackedUnsignedPacker();

final Map<IsoFieldFormat, FieldPacker> defaultFieldPackers = {
  IsoFieldFormat.A: AsciiPacker(),
  IsoFieldFormat.N: NumericFieldPacker(),
  IsoFieldFormat.S: AsciiPacker(),
  IsoFieldFormat.AN: AsciiPacker(),
  IsoFieldFormat.AS: AsciiPacker(),
  IsoFieldFormat.NS: AsciiPacker(),
  IsoFieldFormat.ANS: AsciiPacker(),
  IsoFieldFormat.B: BinaryPacker(),
  IsoFieldFormat.XN: BcdPackedSignedPacker(),
  IsoFieldFormat.Z: AsciiPacker(),
};
