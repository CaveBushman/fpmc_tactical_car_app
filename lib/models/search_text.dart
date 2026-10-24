/// Lower-case text without Czech/Slovak diacritics and with single spaces,
/// so a search for "zranen" finds "ZRANĚN".
String foldForSearch(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_plain[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _plain = {
  'á': 'a',
  'ä': 'a',
  'č': 'c',
  'ď': 'd',
  'é': 'e',
  'ě': 'e',
  'í': 'i',
  'ĺ': 'l',
  'ľ': 'l',
  'ň': 'n',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'ŕ': 'r',
  'ř': 'r',
  'š': 's',
  'ť': 't',
  'ú': 'u',
  'ů': 'u',
  'ü': 'u',
  'ý': 'y',
  'ž': 'z',
};
