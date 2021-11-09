import "field_packer.dart";

/// Formatos de datos permitidos por el estándar ISO8583.
///
/// El estándar define formatos de datos como "A" para textos con solo
/// caracteres alfábeticos, "N" para solo caracteres númericos o combinaciones
/// como "ANS" para caracteres alfanúmericos + especiales.
///
/// Las posibles combinaciones permisibles en la librería se encuentran
/// enumeradas aquí.
///
/// El formato XN es un formato númerico especial del estándar de 1987 de ISO
/// que permite agregar signo a valores númericos con signo.
///
/// Por otro lado, el formato "B" de "Binario" se maneja como una cadena de
/// caracteres hexadecimales que representan una serie de bytes.
enum IsoFieldFormat {
  A,
  N,
  S,
  AN,
  AS,
  NS,
  ANS,
  B,
  XN,
  Z,
}

/// Posibles longitudes de datos de un campo ISO8583.
///
/// De acuerdo con el estándar, se permiten campos con longitud fija, o campos
/// con longitud variable. [IsoFieldLen.FIXED] representa campos de longitud fija.
///
/// Respecto a campos de longitud variable, la cantidad de letras "L" antes de
/// la palabra "VAR" indica el número de dígitos para representar la longitud
/// del campo al armar la cadena del mensaje ISO.
enum IsoFieldLen {
  FIXED,
  LVAR,
  LLVAR,
  LLLVAR,
  LLLLVAR,
}

/// Definición de formato de datos permisible para un campo ISO8583.
class FieldDefinition {
  /// Formato de datos permitido (ej. [IsoFieldFormat.AN] para Alfanúmerico).
  final IsoFieldFormat fieldFormat;

  /// Longitud fija o máxima, si es de longitud fija o variable respectivamente.
  final int len;

  /// Formato de longitud (ej. [IsoFieldLen.LLVAR] en campos de hasta 2 dígitos).
  final IsoFieldLen fieldLenFormat;

  /// Objeto con algoritmos específicos para hacer pack/unpack de este campo.
  ///
  /// Por defecto, los campos se empacan y desempacan hacia/desde su versión en
  /// bytes utilizando objetos de tipo [FieldPacker] definidos para cada formato
  /// de [IsoFieldFormat]. Sin embargo, cuando esta propiedad [customPacker] se
  /// encuentra definida se utiliza en lugar de la versión por defecto para cada
  /// formato.
  final FieldPacker? customPacker;

  /// Indica si el campo es de longitud de datos fija.
  bool get isFixedLen {
    return this.fieldLenFormat == IsoFieldLen.FIXED;
  }

  /// Indica si el campo es de longitud de datos variable.
  bool get isVariableLen {
    return this.fieldLenFormat != IsoFieldLen.FIXED;
  }

  FieldDefinition._(this.fieldFormat, this.len, this.fieldLenFormat,
      {this.customPacker}) {
    _assertValidLen(this.len);
  }

  /// Crea una definición de campo ISO8583 con longitud de datos fija.
  ///
  /// [customPacker] permite definir una objeto de tipo [FieldPacker] que
  /// implemente las funciones necesarias para hacer pack/unpack de este
  /// campo en específico a la hora de enviar/recibir el mensaje ISO.
  ///
  /// Este método falla con [ArgumentError] si la longitud [len] es <= 0.
  factory FieldDefinition.fixed(IsoFieldFormat fieldFormat, int len,
      {FieldPacker? customPacker}) {
    return FieldDefinition._(fieldFormat, len, IsoFieldLen.FIXED,
        customPacker: customPacker);
  }

  /// Crea una definición de campo ISO8583 con longitud de datos variable.
  ///
  /// El formato de longitud de tipo [IsoFieldLen] se define automáticamente
  /// a partir del número de dígitos de [maxLen], a menos que, se provea
  /// el argumento [fieldLenFormat] para definir dicho número de dígitos.
  ///
  /// [customPacker] permite definir una objeto de tipo [FieldPacker] que
  /// implemente las funciones necesarias para hacer pack/unpack de este
  /// campo en específico a la hora de enviar/recibir el mensaje ISO.
  ///
  /// Este método falla con [ArgumentError] si la longitud [maxLen] es <= 0.
  factory FieldDefinition.variable(IsoFieldFormat fieldFormat, int maxLen,
      {IsoFieldLen? fieldLenFormat, FieldPacker? customPacker}) {
    if (fieldLenFormat != null) {
      return FieldDefinition._(fieldFormat, maxLen, fieldLenFormat,
          customPacker: customPacker);
    } else if (maxLen >= 1 && maxLen < 10) {
      return FieldDefinition._(fieldFormat, maxLen, IsoFieldLen.LVAR,
          customPacker: customPacker);
    } else if (maxLen >= 10 && maxLen < 100) {
      return FieldDefinition._(fieldFormat, maxLen, IsoFieldLen.LLVAR,
          customPacker: customPacker);
    } else if (maxLen >= 100 && maxLen < 1000) {
      return FieldDefinition._(fieldFormat, maxLen, IsoFieldLen.LLLVAR,
          customPacker: customPacker);
    } else if (maxLen >= 1000) {
      return FieldDefinition._(fieldFormat, maxLen, IsoFieldLen.LLLLVAR,
          customPacker: customPacker);
    } else {
      return FieldDefinition._(fieldFormat, maxLen, IsoFieldLen.FIXED,
          customPacker: customPacker);
    }
  }

  static void _assertValidLen(int len) {
    if (len <= 0) {
      throw ArgumentError("La longitud de campo ISO no puede ser <= 0.");
    }
  }
}

/// Definición estándar de campos ISO8583 utilizada por defecto en la librería.
final Map<int, FieldDefinition> standardFieldDefinitions = {
  2: FieldDefinition.variable(IsoFieldFormat.N, 19),
  3: FieldDefinition.fixed(IsoFieldFormat.N, 6),
  4: FieldDefinition.fixed(IsoFieldFormat.N, 12),
  5: FieldDefinition.fixed(IsoFieldFormat.N, 12),
  6: FieldDefinition.fixed(IsoFieldFormat.N, 12),
  7: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  8: FieldDefinition.fixed(IsoFieldFormat.N, 8),
  9: FieldDefinition.fixed(IsoFieldFormat.N, 8),
  10: FieldDefinition.fixed(IsoFieldFormat.N, 8),
  11: FieldDefinition.fixed(IsoFieldFormat.N, 6),
  12: FieldDefinition.fixed(IsoFieldFormat.N, 6),
  13: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  14: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  15: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  16: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  17: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  18: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  19: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  20: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  21: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  22: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  23: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  24: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  25: FieldDefinition.fixed(IsoFieldFormat.N, 2),
  26: FieldDefinition.fixed(IsoFieldFormat.N, 2),
  27: FieldDefinition.fixed(IsoFieldFormat.N, 1),
  28: FieldDefinition.fixed(IsoFieldFormat.N, 8),
  29: FieldDefinition.fixed(IsoFieldFormat.N, 8),
  30: FieldDefinition.fixed(IsoFieldFormat.N, 8),
  31: FieldDefinition.fixed(IsoFieldFormat.N, 8),
  32: FieldDefinition.variable(IsoFieldFormat.N, 11),
  33: FieldDefinition.variable(IsoFieldFormat.N, 11),
  34: FieldDefinition.variable(IsoFieldFormat.N, 28),
  35: FieldDefinition.variable(IsoFieldFormat.Z, 37),
  36: FieldDefinition.variable(IsoFieldFormat.Z, 104),
  37: FieldDefinition.fixed(IsoFieldFormat.AN, 12),
  38: FieldDefinition.fixed(IsoFieldFormat.AN, 6),
  39: FieldDefinition.fixed(IsoFieldFormat.AN, 2),
  40: FieldDefinition.fixed(IsoFieldFormat.AN, 3),
  41: FieldDefinition.fixed(IsoFieldFormat.ANS, 8),
  42: FieldDefinition.fixed(IsoFieldFormat.ANS, 15),
  43: FieldDefinition.fixed(IsoFieldFormat.ANS, 40),
  44: FieldDefinition.variable(IsoFieldFormat.AN, 25),
  45: FieldDefinition.variable(IsoFieldFormat.AN, 76),
  46: FieldDefinition.variable(IsoFieldFormat.AN, 999),
  47: FieldDefinition.variable(IsoFieldFormat.AN, 999),
  48: FieldDefinition.variable(IsoFieldFormat.AN, 999),
  49: FieldDefinition.fixed(IsoFieldFormat.AN, 3),
  50: FieldDefinition.fixed(IsoFieldFormat.AN, 3),
  51: FieldDefinition.fixed(IsoFieldFormat.AN, 3),
  52: FieldDefinition.fixed(IsoFieldFormat.B, 16),
  53: FieldDefinition.fixed(IsoFieldFormat.N, 16),
  54: FieldDefinition.variable(IsoFieldFormat.AN, 120),
  55: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  56: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  57: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  58: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  59: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  60: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  61: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  62: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  63: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  64: FieldDefinition.fixed(IsoFieldFormat.B, 16),
  65: FieldDefinition.fixed(IsoFieldFormat.B, 16),
  66: FieldDefinition.fixed(IsoFieldFormat.N, 1),
  67: FieldDefinition.fixed(IsoFieldFormat.N, 2),
  68: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  69: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  70: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  71: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  72: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  73: FieldDefinition.fixed(IsoFieldFormat.N, 6),
  74: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  75: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  76: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  77: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  78: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  79: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  80: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  81: FieldDefinition.fixed(IsoFieldFormat.N, 10),
  82: FieldDefinition.fixed(IsoFieldFormat.N, 12),
  83: FieldDefinition.fixed(IsoFieldFormat.N, 12),
  84: FieldDefinition.fixed(IsoFieldFormat.N, 12),
  85: FieldDefinition.fixed(IsoFieldFormat.N, 12),
  86: FieldDefinition.fixed(IsoFieldFormat.N, 15),
  87: FieldDefinition.fixed(IsoFieldFormat.N, 15),
  88: FieldDefinition.fixed(IsoFieldFormat.N, 15),
  89: FieldDefinition.fixed(IsoFieldFormat.N, 15),
  90: FieldDefinition.fixed(IsoFieldFormat.N, 42),
  91: FieldDefinition.fixed(IsoFieldFormat.AN, 1),
  92: FieldDefinition.fixed(IsoFieldFormat.N, 2),
  93: FieldDefinition.fixed(IsoFieldFormat.N, 5),
  94: FieldDefinition.fixed(IsoFieldFormat.AN, 7),
  95: FieldDefinition.fixed(IsoFieldFormat.AN, 42),
  96: FieldDefinition.fixed(IsoFieldFormat.AN, 8),
  97: FieldDefinition.fixed(IsoFieldFormat.N, 16),
  98: FieldDefinition.fixed(IsoFieldFormat.ANS, 25),
  99: FieldDefinition.variable(IsoFieldFormat.N, 11),
  100: FieldDefinition.variable(IsoFieldFormat.N, 11),
  101: FieldDefinition.variable(IsoFieldFormat.ANS, 99),
  102: FieldDefinition.variable(IsoFieldFormat.ANS, 28),
  103: FieldDefinition.variable(IsoFieldFormat.ANS, 28),
  104: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  105: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  106: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  107: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  108: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  109: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  110: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  111: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  112: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  113: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  114: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  115: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  116: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  117: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  118: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  119: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  120: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  121: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  122: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  123: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  124: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  125: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  126: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  127: FieldDefinition.variable(IsoFieldFormat.ANS, 999),
  128: FieldDefinition.fixed(IsoFieldFormat.B, 16),
};
