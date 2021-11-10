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
final _router = shelf_router.Router()..get('/keyinit/<iso>', _keyInitHandler);

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
  final crcValue = calculateCRC32(AsciiCodec().encode(cipheredTK.toHexStr()));
  if (crcRequest.toHexStr() != crcValue.toHexStr()) {
    isoResponse.setField(39, "73"); // Error en CRC
    isoResponse.setField(63, tokenER() + tokenEXError("03"));
    return Response.ok(isoResponse.pack().toHexStr());
  }
  print("CRC32 OK!");

  final privKey = await parseKeyFromFile<RSAPrivateKey>('private.pem');
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
