import "dart:convert";
import "dart:typed_data";

import "../../utils/utils.dart";

import "field_definition.dart";
import "mti.dart";
import "field_packer.dart";

/// Mensaje ISO8583 parametrizable con formato de campos.
///
/// Internamente, la data de los campos se almacena en tipo de datos "String".
/// Esto incluye a los valores binarios los cuales se manejan internamente
/// como una cadena de caracteres hexadecimales que representan su valor.
///
/// Sin embargo, a la hora de enviar los mensajes ISO8583 a través de la red,
/// es necesario "empaquetar" el mismo en formato de bytes.
///
/// De acuerdo con lo anterior, al llamar al método [pack] se utilizan las
/// funciones definidas como packer tanto para MTI, bitmap y longitud de los
/// campos, como para cada uno de los formatos de campos.

/// Dichas funciones, son customizables de acuerdo a cada especificación y
/// permiten convertir la representación en texto del mensaje ISO a su versión
/// "empaquetada" en bytes lista para enviar.
class IsoMessage {
  /// Intérprete para hacer pack/unpack de MTI hacia/desde lista de bytes.
  static FieldPacker mtiPacker = defaultMtiPacker;

  /// Intérprete para hacer pack/unpack de bitmap hacia/desde lista de bytes.
  static FieldPacker bitmapPacker = defaultBitmapPacker;

  /// Intérprete para hacer pack/unpack de longitud de campo hacia/desde bytes.
  static FieldPacker lenPacker = defaultLenPacker;

  /// Intérpretes para hacer pack/unpack de campos hacia/desde lista de bytes.
  static Map<IsoFieldFormat, FieldPacker> fieldPackers = defaultFieldPackers;

  final Map<int, FieldDefinition> _fieldDefinitions;
  final Map<int, String> _dataElements = Map();

  Mti? mti;

  /// Mapa de campos y sus valores definidos en el mensaje ISO.
  Map<int, String> get fields {
    return {..._dataElements};
  }

  IsoMessage._(this._fieldDefinitions) {
    final sortedFieldNumbers = _fieldDefinitions.keys.toList()..sort();
    final firstFieldNumber = sortedFieldNumbers[0];

    if (firstFieldNumber <= 1) {
      throw ArgumentError("No defina campos ISO cuyo número sea <= 1 " +
          "(el campo #1 para bitmap extendido se maneja internamente).");
    }
  }

  /// Construye un mensaje con definición de campos [standardFieldDefinitions].
  ///
  /// Dicha definición comprende los 127 campos (exceptuando el campo 1: bitmap)
  /// y está basada en el estándar original de ISO8583.
  ///
  /// IMPORTANTE: esto solo debería usarse para pruebas del módulo.
  /// Es importante que cada implementación defina sus campos de acuerdo a
  /// su respectiva especificación.
  factory IsoMessage.standard() {
    return IsoMessage._(standardFieldDefinitions);
  }

  /// Construye un mensaje con la definición [fieldDefinitions] para los campos.
  ///
  /// Esto permite parametrizar el formato de cada campo de acuerdo a los
  /// requerimientos específicos de cada implementación particular del
  /// formato ISO8583.
  factory IsoMessage.withFields(Map<int, FieldDefinition> fieldDefinitions) {
    return IsoMessage._(fieldDefinitions);
  }

  /// Parsea el mensaje desde la cadena de texto ([isoStr]).
  ///
  /// Se debe proveer una definición de campos [fieldDefinitions] para la
  /// correcta interpretación de los mismos de acuerdo a cada especificación.
  ///
  /// Se puede utilizar las definiciones [standardFieldDefinitions] para
  /// pruebas. Sin embargo, es importante que cada implementación defina sus
  /// propios campos.
  factory IsoMessage.fromString(
    String isoStr, {
    required Map<int, FieldDefinition> fieldDefinitions,
  }) {
    final msg = IsoMessage._(fieldDefinitions);

    msg.mti = Mti.fromString(isoStr.substring(0, 4));

    final bitmap = isoStr.substring(4, 20);
    var fieldList = _bitmapToFieldList(bitmap, isSecondary: false);

    final hasSecondaryBitmap = fieldList.contains(1);
    if (hasSecondaryBitmap) {
      final secondaryBitmap = isoStr.substring(20, 36);
      fieldList += _bitmapToFieldList(secondaryBitmap, isSecondary: true);
    }
    _setFieldsFromIsoStr(msg, isoStr, fieldList, fieldDefinitions);

    return msg;
  }

  /// Crea un mensaje ISO8583 a partir de su representación 'empacada' en bytes.
  ///
  /// La representación [bytes] por lo general contendrá las partes del mensaje
  /// codificadas en distintos formatos binarios. Ahí, es donde entran las
  /// implementaciones de tipo [FieldPacker.unpack] para correctamente convertir
  /// los valores binarios de MTI, bitmap y campos a su representación en texto
  /// manejada internamente por la clase [IsoMessage].
  ///
  /// Por último, se debe proveer una definición de campos [fieldDefinitions]
  /// para la interpretación de los mismos de acuerdo a su especificación.
  factory IsoMessage.unpack(
    Uint8List bytes, {
    required Map<int, FieldDefinition> fieldDefinitions,
  }) {
    int cursor = 0;
    final msg = IsoMessage._(fieldDefinitions);

    final mtiLen = mtiPacker.packedLen(4);
    final mtiBytes = bytes.sublist(cursor, mtiLen);
    final mtiStr = mtiPacker.unpack(mtiBytes);
    msg.mti = Mti.fromString(mtiStr);
    cursor += mtiLen;

    final bitmapLen = bitmapPacker.packedLen(16);
    final bitmapBytes = bytes.sublist(cursor, cursor + bitmapLen);
    final bitmapStr = bitmapPacker.unpack(bitmapBytes);
    var fieldList = _bitmapToFieldList(bitmapStr, isSecondary: false);
    cursor += bitmapLen;

    final hasSecondaryBitmap = fieldList.contains(1);
    if (hasSecondaryBitmap) {
      final secondBitmapBytes = bytes.sublist(cursor, cursor + bitmapLen);
      final secondBitmapStr = bitmapPacker.unpack(secondBitmapBytes);
      fieldList += _bitmapToFieldList(secondBitmapStr, isSecondary: true);
      cursor += bitmapLen;
    }
    _setFieldsFromDataBytes(msg, bytes, cursor, fieldList, fieldDefinitions);

    return msg;
  }

  /// Obtiene el valor del campo mediante su número identificador.
  String? getField(int fieldNumber) {
    return _dataElements[fieldNumber];
  }

  /// Obtiene el valor de un campo en formato binario mediante su número.
  Uint8List getBinaryField(int fieldNumber) {
    final fieldValue = getField(fieldNumber);
    final bytes = strHexToBytes(fieldValue ?? "");

    return bytes;
  }

  /// Setea el valor del campo con identificador [field].
  ///
  /// Este llamado falla con [FormatException] si no se respeta la definición
  /// del campo (longitud o formato), o con [StateError] si dicho campo no tiene
  /// definición establecida.
  void setField(int fieldNumber, String value) {
    final fieldDefinition = _fieldDefinitions[fieldNumber];

    _assertDefinitionNotNull(fieldDefinition, fieldNumber);
    _assertValueLenInRange(fieldDefinition, fieldNumber, value);
    _assertValueMatchFormat(fieldDefinition, fieldNumber, value);

    if (fieldDefinition == null) return;

    if (fieldDefinition.isFixedLen) {
      if (fieldDefinition.fieldFormat == IsoFieldFormat.N ||
          fieldDefinition.fieldFormat == IsoFieldFormat.B) {
        _dataElements[fieldNumber] = value.padLeft(fieldDefinition.len, '0');
      } else {
        _dataElements[fieldNumber] = value.padRight(fieldDefinition.len, ' ');
      }
    } else {
      _dataElements[fieldNumber] = value;
    }
  }

  /// Setea el valor del campo binario [field] desde una lista de [bytes].
  ///
  /// Los valores binarios una vez seteados se almacenan como cadenas
  /// hexadecimales.
  ///
  /// Falla con [StateError] si se intenta setear con este método un campo que
  /// no es de tipo binario ([IsoFieldFormat.B]) o si el campo no tiene
  /// definición.
  void setBinaryField(int fieldNumber, Uint8List bytes) {
    final fieldDefinition = _fieldDefinitions[fieldNumber];

    _assertDefinitionNotNull(fieldDefinition, fieldNumber);
    _assertFieldIsBinary(fieldDefinition, fieldNumber);

    final value = bytesToHexStr(bytes);

    setField(fieldNumber, value);
  }

  /// Elimina un campo seteado en el mensaje de acuerdo a su [fieldNumber].
  ///
  /// En consecuencia, su valor es descartado y dicho campo ya no será incluido
  /// en ninguna representación del mensaje ISO.
  void removeField(int fieldNumber) {
    _dataElements.remove(fieldNumber);
  }

  /// Limpia el MTI y todos los campos seteados en el mensaje.
  void clear() {
    this.mti = null;
    for (final key in fields.keys) {
      removeField(key);
    }
  }

  /// Utilidad de debug que imprime en consola los campos seteados y su valor.
  void printFields() {
    for (final entry in fields.entries) {
      print("#${entry.key} => '${entry.value}'");
    }
  }

  Uint8List toAscii() {
    return AsciiCodec().encode(this.toString());
  }

  @override
  String toString() {
    return "$mti$_bitmap$_body";
  }

  Uint8List pack() {
    final packedMti = mtiPacker.pack(mti.toString());
    final mtiList = List<int>.from(packedMti);
    final packedBitmap = bitmapPacker.pack(_bitmap);
    final bitmapList = List<int>.from(packedBitmap);
    final dataElementsList = List<int>.from(_packedDataElements);

    final dataList = mtiList + bitmapList + dataElementsList;

    final bytes = Uint8List.fromList(dataList);
    return bytes;
  }

  String get _bitmap {
    var bitmap = "";

    // Solo evaluamos los bits del 65 al 128 si está definido el campo 1 (bitmap secundario)
    bitmap = _bitmapLoop(1, 64);
    if (_definedFieldNumbers.contains(1)) {
      bitmap += _bitmapLoop(65, 128);
    }

    return bitmap;
  }

  String _bitmapLoop(int start, int end) {
    var bitmap = "";
    var i = start;

    while (i <= end) {
      var val = 0;

      if (_definedFieldNumbers.contains(i)) val += 8;
      if (_definedFieldNumbers.contains(i + 1)) val += 4;
      if (_definedFieldNumbers.contains(i + 2)) val += 2;
      if (_definedFieldNumbers.contains(i + 3)) val += 1;

      final char = val.toRadixString(16).toUpperCase();
      bitmap += char;

      i += 4;
    }

    return bitmap;
  }

  /// Lista interna de campos definidos para armar el bitmap
  /// (incluye el campo 1 si debe haber bitmap secundario)
  List<int> get _definedFieldNumbers {
    final keysList = _dataElements.keys.toList();

    if (keysList.any((element) => element > 64)) {
      return [1, ...keysList];
    } else {
      return keysList;
    }
  }

  String get _body {
    var body = "";

    final sortedKeys = _dataElements.keys.toList()..sort();

    for (final key in sortedKeys) {
      final fieldDefinition = _fieldDefinitions[key];
      final elementValue = _dataElements[key];

      if (fieldDefinition == null) continue;
      if (elementValue == null) continue;

      if (fieldDefinition.isFixedLen) {
        body += elementValue;
      } else {
        final lenStr = elementValue.length
            .toString()
            .padLeft(fieldDefinition.fieldLenFormat.index, '0');
        body += lenStr + elementValue;
      }
    }

    return body;
  }

  static List<int> _bitmapToFieldList(String bitmap,
      {required bool isSecondary}) {
    final fields = List<int>.empty(growable: true);

    var fieldNumber = isSecondary ? 65 : 1;
    bitmap.split("").forEach((String char) {
      final decimal = int.parse(char, radix: 16);
      final binario = decimal.toRadixString(2).padLeft(4, '0');

      binario.split("").forEach((String bit) {
        if (bit == "1") fields.add(fieldNumber);

        fieldNumber++;
      });
    });

    return fields;
  }

  static void _setFieldsFromIsoStr(IsoMessage msg, String isoStr,
      List<int> fieldList, Map<int, FieldDefinition> fieldDefinitions) {
    final hasSecondaryBitmap = fieldList.contains(1);

    var fieldStart = hasSecondaryBitmap ? 36 : 20;
    for (final fieldNum in fieldList) {
      if (fieldNum <= 1) continue;

      final fieldDef = fieldDefinitions[fieldNum];
      _assertDefinitionNotNull(fieldDef, fieldNum);

      if (fieldDef == null) continue;

      var fieldEnd = fieldStart;

      if (fieldDef.isFixedLen) {
        fieldEnd += fieldDef.len;
      } else {
        final lenDigitsNumber = fieldDef.fieldLenFormat.index;
        final lenStr =
            isoStr.substring(fieldStart, fieldStart + lenDigitsNumber);
        final len = int.parse(lenStr);
        fieldStart += lenDigitsNumber;
        fieldEnd = fieldStart + len;
      }
      final fieldValue = isoStr.substring(fieldStart, fieldEnd);
      msg.setField(fieldNum, fieldValue);

      fieldStart = fieldEnd;
    }
  }

  static void _setFieldsFromDataBytes(
      IsoMessage msg,
      Uint8List bytes,
      int cursor,
      List<int> fieldList,
      Map<int, FieldDefinition> fieldDefinitions) {
    var fieldStart = cursor;
    for (final fieldNum in fieldList) {
      if (fieldNum <= 1) continue;

      final fieldDef = fieldDefinitions[fieldNum];
      _assertDefinitionNotNull(fieldDef, fieldNum);
      if (fieldDef == null) continue;

      final fieldPacker =
          fieldDef.customPacker ?? fieldPackers[fieldDef.fieldFormat];
      if (fieldPacker == null) continue;

      var fieldEnd = fieldStart;

      if (fieldDef.isFixedLen) {
        int len = fieldPacker.packedLen(fieldDef.len);
        fieldEnd += len;
      } else {
        int lenDigitsCount = lenPacker.packedLen(fieldDef.fieldLenFormat.index);
        final lenBytes = bytes.sublist(fieldStart, fieldStart + lenDigitsCount);
        String lenStr = lenPacker.unpack(lenBytes);
        final len = int.parse(lenStr);
        fieldStart += lenDigitsCount;
        fieldEnd = fieldStart + len;
      }
      final fieldBytes = bytes.sublist(fieldStart, fieldEnd);
      final fieldValue = fieldPacker.unpack(fieldBytes);
      msg.setField(fieldNum, fieldValue);

      fieldStart = fieldEnd;
      cursor = fieldEnd;
    }
  }

  Uint8List get _packedDataElements {
    List<int> bytes = [];

    final sortedKeys = _dataElements.keys.toList()..sort();

    for (final key in sortedKeys) {
      final fieldDef = _fieldDefinitions[key];
      if (fieldDef == null) continue;

      final fieldPacker =
          fieldDef.customPacker ?? fieldPackers[fieldDef.fieldFormat];

      if (fieldPacker == null) continue;

      if (fieldDef.isFixedLen) {
        bytes += fieldPacker.pack(_dataElements[key] ?? '');
      } else {
        final fieldBytes = fieldPacker.pack(_dataElements[key] ?? '');
        final fieldBytesAsList = List<int>.from(fieldBytes);

        final lenStr = fieldBytes.lengthInBytes
            .toString()
            .padLeft(fieldDef.fieldLenFormat.index, '0');
        final lenBytes = lenPacker.pack(lenStr);
        final lenBytesAsList = List<int>.from(lenBytes);

        bytes += lenBytesAsList + fieldBytesAsList;
      }
    }

    return Uint8List.fromList(bytes);
  }

  static void _assertDefinitionNotNull(
      FieldDefinition? fieldDefinition, int fieldNumber) {
    if (fieldDefinition == null) {
      throw StateError(
          "El campo #$fieldNumber referenciado no tiene definición asignada.");
    }
  }

  static void _assertValueLenInRange(
      FieldDefinition? fieldDefinition, int fieldNumber, dynamic value) {
    if (value.length > fieldDefinition?.len) {
      throw FormatException(
          "El valor para el campo #$fieldNumber es más largo de lo permitido " +
              "por la definición.");
    }
  }

  static void _assertValueMatchFormat(
      FieldDefinition? fieldDefinition, int fieldNumber, String value) {
    if (fieldDefinition != null &&
        !_valueHasMatchWithFormat(value, fieldDefinition.fieldFormat)) {
      throw FormatException("El valor: '$value' no concuerda con el formato " +
          "${fieldDefinition.fieldFormat} definido para el campo " +
          "#$fieldNumber.");
    }
  }

  static void _assertFieldIsBinary(
      FieldDefinition? fieldDefinition, int fieldNumber) {
    if (fieldDefinition?.fieldFormat != IsoFieldFormat.B) {
      throw StateError("El campo #$fieldNumber no es de formato binario.");
    }
  }

  /// *True* si el valor pasado concuerda con el formato de campo: [format].
  static bool _valueHasMatchWithFormat(String value, IsoFieldFormat format) {
    switch (format) {
      case IsoFieldFormat.A:
        return RegExp(r'^[a-zA-Z]+$').hasMatch(value);
      case IsoFieldFormat.N:
        return RegExp(r'^[0-9]+$').hasMatch(value);
      case IsoFieldFormat.S:
        return !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value);
      case IsoFieldFormat.AN:
        return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value);
      case IsoFieldFormat.AS:
        return !RegExp(r'^[0-9]+$').hasMatch(value);
      case IsoFieldFormat.NS:
      case IsoFieldFormat.Z:
        return !RegExp(r'^[a-zA-Z]+$').hasMatch(value);
      case IsoFieldFormat.XN:
        return RegExp(r'^[cdCD0-9][0-9]+$').hasMatch(value);
      case IsoFieldFormat.B:
        return RegExp(r'^[a-fA-F0-9]+$').hasMatch(value);
      case IsoFieldFormat.ANS:
        return true;
      default:
        return false;
    }
  }
}
