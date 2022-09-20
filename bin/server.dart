// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'iso8583/iso8583.dart';
import 'utils/utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shelf_static/shelf_static.dart' as shelf_static;
import 'package:encrypt/encrypt.dart';
import 'package:encrypt/encrypt_io.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:dart_des/dart_des.dart';

Future main() async {
  // If the "PORT" environment variable is set, listen to it. Otherwise, 8080.
  // https://cloud.google.com/run/docs/reference/container-contract#port
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  // See https://pub.dev/documentation/shelf/latest/shelf/Cascade-class.html
  final cascade = Cascade()
      // First, serve files from the 'public' directory
      .add(_staticHandler)
      // If a corresponding file is not found, send requests to a `Router`
      .add(_router);

  // See https://pub.dev/documentation/shelf/latest/shelf_io/serve.html
  final server = await shelf_io.serve(
    // See https://pub.dev/documentation/shelf/latest/shelf/logRequests.html
    logRequests()
        // See https://pub.dev/documentation/shelf/latest/shelf/MiddlewareExtensions/addHandler.html
        .addHandler(cascade.handler),
    InternetAddress.anyIPv4, // Allows external connections
    port,
  );

  print('Serving at http://${server.address.host}:${server.port}');
}

// Serve files from the file system.
final _staticHandler =
    shelf_static.createStaticHandler('public', defaultDocument: 'index.html');

// Router instance to handler requests.
final _router = shelf_router.Router()
  ..get('/sale/<iso>', _saleHandler)
  ..get('/keyinit/<iso>', _keyInitHandler)
  ..get('/token/<serialNumber>', _tokenHandler);

final isoSaleDefinitions = {
  2: FieldDefinition.variable(IsoFieldFormat.N, 19),
  3: FieldDefinition.fixed(IsoFieldFormat.N, 6),
  4: FieldDefinition.fixed(IsoFieldFormat.N, 12),
  11: FieldDefinition.fixed(IsoFieldFormat.N, 6),
  12: FieldDefinition.fixed(IsoFieldFormat.N, 6),
  13: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  14: FieldDefinition.fixed(IsoFieldFormat.N, 4),
  22: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  23: FieldDefinition.fixed(IsoFieldFormat.N, 3),
  35: FieldDefinition.variable(IsoFieldFormat.NS, 37),
  37: FieldDefinition.fixed(IsoFieldFormat.ANS, 12),
  39: FieldDefinition.fixed(IsoFieldFormat.AN, 2),
  41: FieldDefinition.fixed(IsoFieldFormat.ANS, 8),
  48: FieldDefinition.variable(IsoFieldFormat.ANS, 27,
      fieldLenFormat: IsoFieldLen.LLLVAR),
  55: FieldDefinition.variable(IsoFieldFormat.B, 999),
  57: FieldDefinition.variable(
    IsoFieldFormat.ANS,
    15,
    fieldLenFormat: IsoFieldLen.LLLVAR,
  ),
  60: FieldDefinition.variable(
    IsoFieldFormat.ANS,
    2,
    fieldLenFormat: IsoFieldLen.LLLVAR,
  ),
  63: FieldDefinition.variable(
    IsoFieldFormat.ANS,
    999,
    fieldLenFormat: IsoFieldLen.LLLVAR,
  ),
};

final List<String> _registeredTerminals = [
  // Willians
  "9210183926", // Newpos 9210
  "PB05D97A60016", // Sunmi P2
  "0821380883", // PAX A920
  "N77201526624", // N910
  "NA8900168013", // N910 Pro
  "J97600001997", // SP930
  "B77800204314", // SP830
  "Q28810270001", // ME60
  "Q77B00856345", // ME30SU
  "U17400000905", // U1000
  // Yura
  "9220075125", // Newpos 9220
  "N78402348085", // N910 A7
  "N77401557306", // N910 A5
  "Q77B00856353", // ME30SU
  "0000U18451005068", // U1000
  "1850005928", // A920 PRO
  "Q29500022344", // ME60
  // Jose Di Pietro
  "9210183925", // New9210 Debug
  "9210183924", // New9210 Prod
  "0821188450", // A920 Debug
  "0820844168", // A920 Prod
  "N78402348103", // N910 Debug
  "N78402348112", // N910 Prod
];

Future<Response> _tokenHandler(Request request, String serialNumber) async {
  if (!_registeredTerminals.contains(serialNumber)) {
    return Response.badRequest(body: "invalid ID");
  }

  final privateKey =
      await parseKeyFromFile<RSAPrivateKey>('./keys/private2.pem');
  final tokenVersion =
      Uint8List.fromList([0x01]); // el primer byte indica la versión

  final nowTimestamp = DateTime.now().millisecondsSinceEpoch;
  final hour = Duration(hours: 48).inMilliseconds;
  final expTimestamp = nowTimestamp + hour;
  print("Exp Int: '$expTimestamp'");
  final expBase16 = expTimestamp.toRadixString(16).padLeft(12, '0');
  final expBytes = expBase16.toHexBytes();

  final serialNumberBytes = AsciiCodec().encode(serialNumber);

  String str = "";
  for (int byte in serialNumberBytes) {
    final s = byte.toRadixString(16).padLeft(2, '0');
    str += "0x$s,";
  }
  print(str);

  str = "";
  for (String val in serialNumber.split('')) {
    str += "'$val',";
  }
  print(str);

  final payload =
      Uint8List.fromList(tokenVersion + expBytes + serialNumberBytes);
  print("Payload: ${payload.toHexStr()}");

  final signer =
      Signer(RSASigner(RSASignDigest.SHA256, privateKey: privateKey));
  final signature = signer.signBytes(payload).bytes;
  final token = Uint8List.fromList(tokenVersion + signature + expBytes);
  print("Token: '${token.toHexStr()}'");

  return Response.ok(token);
}

Future<Response> _saleHandler(Request request, String iso) async {
  final isoResponse = IsoMessage.withFields(isoSaleDefinitions);
  isoResponse.mti = Mti.fromString("0210");

  final isoBytes = iso.toHexBytes();
  final isoRequest = IsoMessage.unpack(
    isoBytes,
    fieldDefinitions: isoSaleDefinitions,
  );

  String pan;

  // si la transacción es digitada, el PAN viene en el campo 2
  final field2 = isoRequest.getField(2);
  // si la transacción es de banda, el PAN viene en el track 2 del campo 35
  final field35 = isoRequest.getField(35);
  // si la transacción es de chip y encriptada, el track 2 viene en el campo 63
  final field63 = isoRequest.getField(63);

  if (field2 != null && field2.isNotEmpty) {
    pan = field2;
  } else if (field35 != null && field35.isNotEmpty) {
    final track2 = field35.toUpperCase();

    int separatorIndex;
    if (track2.contains("D")) {
      separatorIndex = track2.indexOf("D");
    } else if (track2.contains("=")) {
      separatorIndex = track2.indexOf("=");
    } else {
      return _rejectSale(isoResponse,
          "Problema con separador de track2."); // Rechazado, no se pudo extraer el PAN
    }
    pan = track2.substring(0, separatorIndex);
  } else if (field63 != null && field63.isNotEmpty) {
    final tokenESIndex = field63.indexOf("! ES");
    if (tokenESIndex < 0) {
      return _rejectSale(isoResponse,
          "Token ES no encontrado en campo 63"); // Rechazado, no se pudo extraer el PAN
    }
    final tokenES = field63.substring(tokenESIndex, tokenESIndex + 70);
    if (tokenES.length != 70) {
      return _rejectSale(isoResponse,
          "Token ES de longitud inválida."); // Rechazado, no se pudo extraer el PAN
    }
    bool isCiphered = tokenES[50] == "5";
    if (isCiphered) {
      final tokenEZIndex = field63.indexOf("! EZ");
      final tokenEZ = field63.substring(tokenEZIndex, tokenEZIndex + 108);
      final ksn = tokenEZ.substring(10, 30).toHexBytes();
      print("KSN: ${ksn.toHexStr()}");
      final cipheredData = tokenEZ.substring(48, 96).toHexBytes();

      final key = _deriveDukptSessionKey(bdk, ksn);
      final des = DES3(
        key: key.toList(),
        mode: DESMode.ECB,
        paddingType: DESPaddingType.None,
      );
      final decrypted = Uint8List.fromList(des.decrypt(cipheredData));
      final decryptedStr = decrypted.toHexStr().toUpperCase();
      print("DECRYPTED TRACK 2 + CVV: $decryptedStr");

      int separatorIndex;
      if (decryptedStr.contains("D")) {
        separatorIndex = decryptedStr.indexOf("D");
      } else {
        return _rejectSale(isoResponse,
            "El Track desencriptado no contiene el caracter 'D'"); // Rechazado, no se pudo extraer el PAN
      }
      pan = decryptedStr.substring(0, separatorIndex);
    } else {
      return _rejectSale(isoResponse,
          "El campo 63 no viene cifrado"); // Rechazado, campo 63 debe venir cifrado
    }
  } else {
    return _rejectSale(isoResponse,
        "No se pudo extraer el PAN del campo 35 o 63"); // Rechazado, no se pudo extraer el PAN
  }

  print("PAN: $pan");
  if (pan[0] == "4") {
    // Para probar, se rechazan los PAN que empiezan con '4'
    // (por lo general, VISA)
    return _rejectSale(isoResponse, "El PAN empieza por '4'");
  } else {
    return _approveSale(isoResponse);
  }
}

Response _approveSale(IsoMessage isoResponse) {
  isoResponse.setField(39, "00"); // OK
  return Response.ok(isoResponse.pack().toHexStr());
}

Response _rejectSale(IsoMessage isoResponse, String errorMessage) {
  print("Error: $errorMessage");
  isoResponse.setField(39, "01"); // Rechazado, no se pudo extraer el PAN
  return Response.ok(isoResponse.pack().toHexStr());
}

Uint8List _deriveDukptSessionKey(Uint8List bdk, Uint8List ksn) {
  assert(bdk.length == 16);
  assert(ksn.length == 10);

  final ipek = _createIPEK(bdk, ksn);
  return _createDataKeyHex(ipek, ksn);
}

Uint8List _createIPEK(Uint8List bdk, Uint8List ksn) {
  int bdkLen = 16;
  int ksnLen = 10;
  assert(bdk.length == bdkLen);
  assert(ksn.length == ksnLen);

  final halfBDK = bdk.sublist(0, 8);
  final key = Uint8List.fromList(bdk + halfBDK);

  final ksnMask = "FFFFFFFFFFFFFFE00000".toHexBytes();
  var maskedKSN = Uint8List(ksnLen);
  for (int i = 0; i < ksnLen; i++) {
    maskedKSN[i] = ksnMask[i] & ksn[i];
  }
  maskedKSN = maskedKSN.sublist(0, 8); // los primeros 8 bytes

  final ksnDES = DES3(
    key: key.toList(),
    mode: DESMode.ECB,
    paddingType: DESPaddingType.None,
  );
  final cipher1 = Uint8List.fromList(ksnDES.encrypt(maskedKSN.toList()));

  final bdkMask = "C0C0C0C000000000C0C0C0C000000000".toHexBytes();
  final maskedBDK = Uint8List(bdkLen);
  for (int i = 0; i < bdkLen; i++) {
    maskedBDK[i] = bdkMask[i] ^ bdk[i];
  }
  final halfMaskedBDK = maskedBDK.sublist(0, 8);
  final key2 = Uint8List.fromList(maskedBDK + halfMaskedBDK);
  final bdkDES = DES3(
    key: key2.toList(),
    mode: DESMode.ECB,
    paddingType: DESPaddingType.None,
  );
  final cipher2 = Uint8List.fromList(bdkDES.encrypt(maskedKSN.toList()));

  final ipek = Uint8List.fromList(cipher1 + cipher2);
  return ipek;
}

Uint8List _createDataKeyHex(Uint8List ipek, Uint8List ksn) {
  final derivedKey = _deriveKeyHex(ipek, ksn);
  final variantMask = "0000000000FF00000000000000FF0000".toHexBytes();
  final maskedKey = Uint8List(16);
  for (int i = 0; i < 16; i++) {
    maskedKey[i] = variantMask[i] ^ derivedKey[i];
  }

  final halfKey = maskedKey.sublist(0, 8);
  final expandedKey = Uint8List.fromList(maskedKey + halfKey);
  final des = DES3(
    key: expandedKey.toList(),
    mode: DESMode.ECB,
    paddingType: DESPaddingType.None,
  );
  final left = des.encrypt(maskedKey.sublist(0, 8));
  final right = des.encrypt(maskedKey.sublist(8));
  return Uint8List.fromList(left + right);
}

Uint8List _deriveKeyHex(Uint8List ipek, Uint8List ksn) {
  final ksnMask = "FFFFFFFFFFFFFFE00000".toHexBytes();
  final ksnBottom = ksn.sublist(2); // extraemos los últimos 8 bytes
  var baseKSN = Uint8List(8);
  for (int i = 0; i < 8; i++) {
    baseKSN[i] = ksnMask[i] & ksnBottom[i];
  }

  // los últimos 3 bytes (que contienen el contador)
  final ksnInt = int.parse(ksn.sublist(7).toHexStr(), radix: 16);
  final counter = ksnInt & 0x1FFFFF;

  var curKey = ipek;
  for (var shiftReg = 0x100000; shiftReg > 0; shiftReg >>= 1) {
    if ((shiftReg & counter) > 0) {
      var tmpKSN = baseKSN.sublist(0, 5).toList(growable: true);
      final byte5 = baseKSN[5];
      final byte6 = baseKSN[6];
      final byte7 = baseKSN[7];
      var tmpLong = (byte5 << 16) + (byte6 << 8) + byte7;
      tmpLong |= shiftReg;
      tmpKSN.add(tmpLong >> 16);
      tmpKSN.add(255 & (tmpLong >> 8));
      tmpKSN.add(255 & tmpLong);

      baseKSN = Uint8List.fromList(tmpKSN); // remember the updated value

      curKey = _generateKey(curKey, Uint8List.fromList(tmpKSN));
    }
  }
  return curKey;
}

Uint8List _createPINKeyHex(Uint8List ipek, Uint8List ksn) {
  final derivedKey = _deriveKeyHex(ipek, ksn); // derive DUKPT basis key
  final variantMask =
      '00000000000000FF00000000000000FF'.toHexBytes(); // PIN variant
  final result = Uint8List(16);
  for (int i = 0; i < 16; i++) {
    result[i] = variantMask[i] ^ derivedKey[i];
  }
  return result;
}

Uint8List _createMACKeyHex(Uint8List ipek, Uint8List ksn) {
  final derivedKey = _deriveKeyHex(ipek, ksn); // derive DUKPT basis key
  final variantMask =
      '000000000000FF00000000000000FF00'.toHexBytes(); // MAC variant
  final result = Uint8List(16);
  for (int i = 0; i < 16; i++) {
    result[i] = variantMask[i] ^ derivedKey[i];
  }
  return result;
}

Uint8List _generateKey(Uint8List key, Uint8List ksn) {
  final mask = 'C0C0C0C000000000C0C0C0C000000000'.toHexBytes();
  final maskedKey = Uint8List(16);
  for (int i = 0; i < 16; i++) {
    maskedKey[i] = mask[i] ^ key[i];
  }

  final left = _encryptRegister(maskedKey, ksn);
  final right = _encryptRegister(key, ksn);

  return Uint8List.fromList(left + right); // binary
}

Uint8List _encryptRegister(Uint8List key, Uint8List reg) {
  final bottom8 = key.sublist(key.length - 8); // bottom 8 bytes
  final top8 = key.sublist(0, 8); // top 8 bytes
  final bottom8xorKSN = Uint8List(8);
  for (int i = 0; i < 8; i++) {
    bottom8xorKSN[i] = bottom8[i] ^ reg[i];
  }

  final des = DES(
    key: top8.toList(),
    mode: DESMode.ECB,
    paddingType: DESPaddingType.None,
  );
  final encrypted = des.encrypt(bottom8xorKSN);

  final result = Uint8List(8);
  for (int i = 0; i < 8; i++) {
    result[i] = bottom8[i] ^ encrypted[i];
  }
  return result;
}

final bdk = "00112233445566778899AABBCCDDEEFF".toHexBytes();
Future<Response> _keyInitHandler(Request request, String iso) async {
  final isoResponse = IsoMessage.withFields(isoSaleDefinitions);
  isoResponse.mti = Mti.fromString("0210");

  final isoBytes = iso.toHexBytes();
  final isoRequest = IsoMessage.unpack(
    isoBytes,
    fieldDefinitions: isoSaleDefinitions,
  );
  final field63 = isoRequest.getField(63);
  if (field63 == null) {
    return Response.internalServerError(body: "Campo 63 no encontrado.");
  }
  final tokenEWIndex = field63.indexOf("! EW");
  final tokenEW = field63.substring(tokenEWIndex, tokenEWIndex + 548);
  final cipheredTK = tokenEW.substring(10, 522).toHexBytes();
  final tkKCV = tokenEW.substring(522, 528).toHexBytes();
  final crcRequest = tokenEW.substring(540, 548).toHexBytes();

  final cipheredTKStr = cipheredTK.toHexStr().toUpperCase();
  final crcValue = calculateCRC32(AsciiCodec().encode(cipheredTKStr));
  if (crcRequest.toHexStr() != crcValue.toHexStr()) {
    isoResponse.setField(39, "73"); // Error en CRC
    isoResponse.setField(63, tokenER() + tokenEXError("03"));
    return Response.ok(isoResponse.pack().toHexStr());
  }
  print("CRC32 OK!");

  final privKey = await parseKeyFromFile<RSAPrivateKey>('./keys/private.pem');
  final encrypter = Encrypter(RSA(privateKey: privKey));
  final decrypted = encrypter.decryptBytes(Encrypted(cipheredTK));
  final transportKey = Uint8List.fromList(decrypted);

  final tkDES = DES3(
    key: transportKey.toList(),
    mode: DESMode.ECB,
    paddingType: DESPaddingType.None,
  );
  final kcvInts = tkDES.encrypt(List.filled(8, 0x00)).sublist(0, 3);
  final kcv = Uint8List.fromList(kcvInts);
  if (kcv.toHexStr() != tkKCV.toHexStr()) {
    isoResponse.setField(39, "72"); // Error Inicializando llaves
    isoResponse.setField(63, tokenER() + tokenEXError("01"));
    return Response.ok(isoResponse.pack().toHexStr());
  }
  print("KCV OK!");

  final k0 = "FDB5C138D31DDCAA6C5DC76827EF487E".toHexBytes();
  final ksn = "0102012345678AE00000".toHexBytes();
  final k0DES = DES3(
    key: k0.toList(),
    mode: DESMode.ECB,
    paddingType: DESPaddingType.None,
  );
  final k0KCVInts = k0DES.encrypt(List.filled(8, 0x00)).sublist(0, 3);
  final k0KCV = Uint8List.fromList(k0KCVInts);
  final k0Ciphered = Uint8List.fromList(tkDES.encrypt(k0.toList()));

  isoResponse.setField(39, "00"); // OK
  isoResponse.setField(
    63,
    tokenER() + tokenEX(k0Ciphered: k0Ciphered, ksn: ksn, k0KCV: k0KCV),
  );
  return Response.ok(isoResponse.pack().toHexStr());
}

String tokenER({
  bool suggestKeyInit = false,
  bool requireKeyInit = false,
  bool shouldUpdateBIN = false,
}) {
  return "! ER00002 " + // Header
      (requireKeyInit ? "2" : (suggestKeyInit ? "1" : "0")) +
      (shouldUpdateBIN ? "1" : "0");
}

String tokenEX({
  required Uint8List k0Ciphered,
  required Uint8List ksn,
  required Uint8List k0KCV,
}) {
  assert(k0Ciphered.length == 8);
  assert(ksn.length == 10);
  assert(k0KCV.length == 3);

  final k0CipheredStr = k0Ciphered.toHexStr();
  final crcValue = calculateCRC32(AsciiCodec().encode(k0CipheredStr));
  return "! EX00068 " + // Header
          k0CipheredStr + // Llave nueva cifrada con llave de transporte (TK)
          ksn.toHexStr() + // KSN Inicial de llave nueva
          k0KCV.toHexStr() + // Key Check Value de nueva llave
          "00" + // Estatus de generación de llave: OK
          crcValue.toHexStr() // Verificación CRC32 de llave nueva cifrada
      ;
}

String tokenEXError(String errorCode) {
  assert(errorCode.length == 2);
  return "! EX00068 " + // Header
      Uint8List(16).toHexStr() +
      Uint8List(10).toHexStr() +
      Uint8List(3).toHexStr() +
      errorCode + // Estatus de generación de llave
      Uint8List(4).toHexStr();
}
