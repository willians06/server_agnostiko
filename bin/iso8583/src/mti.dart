/// Versión de ISO8583.
enum MtiVersion {
  Iso1987,
  Iso1993,
  Iso2003,
  Reserved3,
  Reserved4,
  Reserved5,
  Reserved6,
  Reserved7,
  NationalUse,
  PrivateUse,
}

/// Clase de mensaje bajo ISO8583 (ej. Financiero).
enum MtiClass {
  Reserved0,
  Authorization,
  Financial,
  FileAction,
  Reversal,
  Reconciliation,
  Administrative,
  FeeCollection,
  NetworkManagement,
  Reserved9
}

/// Función del mensaje ISO8583 (ej. Request).
enum MtiFunction {
  Request,
  RequestResponse,
  Advice,
  AdviceResponse,
  Notification,
  NotificationAck,
  Instruction,
  InstructionAck,
  Reserved8,
  Reserved9,
}

/// Origen del mensaje ISO8583 (ej. Acquirer).
enum MtiOrigin {
  Acquirer,
  AcquirerRepeat,
  Issuer,
  IssuerRepeat,
  Other,
  OtherRepeat,
  Reserved6,
  Reserved7,
  Reserved8,
  Reserved9,
}

/// Representa el "Message Type Indicator" (MTI) de un mensaje financiero bajo estándar ISO8583.
class Mti {
  final MtiVersion mtiVersion;
  final MtiClass mtiClass;
  final MtiFunction mtiFunction;
  final MtiOrigin mtiOrigin;

  Mti(this.mtiVersion, this.mtiClass, this.mtiFunction, this.mtiOrigin);

  /// Crea el "MTI" a partir de una cadena de texto de 4 caracteres (ej: "0200" o "0210)".
  ///
  /// Falla con [ArgumentError] si la longitud de la cadena es diferente de 4.
  factory Mti.fromString(String mtiString) {
    _assertMtiLen(mtiString);
    _assertMtiFormat(mtiString);

    int mtiVersionCode = int.parse(mtiString[0]);
    int mtiClassCode = int.parse(mtiString[1]);
    int mtiFunctionCode = int.parse(mtiString[2]);
    int mtiOriginCode = int.parse(mtiString[3]);

    return Mti(
      MtiVersion.values[mtiVersionCode],
      MtiClass.values[mtiClassCode],
      MtiFunction.values[mtiFunctionCode],
      MtiOrigin.values[mtiOriginCode],
    );
  }

  @override
  String toString() {
    return '${mtiVersion.index}${mtiClass.index}${mtiFunction.index}${mtiOrigin.index}';
  }

  static void _assertMtiLen(String mtiString) {
    if (mtiString.length != 4) {
      throw ArgumentError(
          "La cadena MTI debe tener exactamente 4 caracteres de longitud.");
    }
  }

  static void _assertMtiFormat(String mtiString) {
    if (!RegExp(r'^[0-9]+$').hasMatch(mtiString)) {
      throw ArgumentError(
          "La cadena MTI debe contener solo caracteres númericos.");
    }
  }
}
