import "dart:typed_data";

import "../../utils/src/codecs.dart";

class TlvTag {
  final int tag;
  final Uint8List value;

  const TlvTag(this.tag, this.value);
}

/// Colección de tags EMV en formato BER-TLV.
class TlvPackage {
  final _elements = List<TlvTag>.empty(growable: true);

  void add(int tag, Uint8List value) {
    _elements.add(TlvTag(tag, value));
  }

  /// Retorna la lista de bytes que representan la data TLV.
  Uint8List pack() {
    List<int> intsList = List.empty(growable: true);

    for (final el in _elements) {
      int tag = el.tag;

      if (tag <= 0xff) {
        intsList.add(tag);
      } else {
        Uint8List tagBytes = intToUint8List(tag);
        intsList.addAll(tagBytes);
      }

      Uint8List lenBytes = intToBerTlvLen(el.value.length);
      intsList.addAll(lenBytes);

      intsList.addAll(el.value);
    }

    return Uint8List.fromList(intsList);
  }
}
