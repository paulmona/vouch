/// An E.164 number as people read it: `+12045550150` is `(204) 555-0150`.
/// Other countries show as stored.
String formatPhone(String e164) {
  final m = RegExp(r'^\+1(\d{3})(\d{3})(\d{4})$').firstMatch(e164);
  return m == null ? e164 : '(${m[1]}) ${m[2]}-${m[3]}';
}
