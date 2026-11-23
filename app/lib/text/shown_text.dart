/// Text a server passes on from an agent, made safe to show.
///
/// The server refuses hidden characters (server/src/text.ts), but the phone
/// does not rely on that: a bidi override, zero-width space or line break
/// can reorder or hide what the owner reads before approving. Each such
/// character is shown as a visible `[U+XXXX]` instead, so odd text looks odd
/// rather than being silently cleaned up. Display only: the shown digest is
/// computed over the server's values, unchanged.
abstract final class ShownText {
  /// Marked wherever they appear: control, format, surrogate, unassigned,
  /// private use, line and paragraph separators, letters that render as
  /// nothing, the null notehead (U+1D159) and the object replacement
  /// character (U+FFFC). A private-use character draws whatever a font puts
  /// there.
  static final _hidden = RegExp(
    r'[\p{Cc}\p{Cf}\p{Cs}\p{Cn}\p{Co}\p{Zl}\p{Zp}\u115F\u1160\u2800\u3164\uFFA0\uFFFC\u{1D159}]',
    unicode: true,
  );
  static final _hiddenBarNewline = RegExp(
    r'[^\P{Cc}\n]|[\p{Cf}\p{Cs}\p{Cn}\p{Co}\p{Zl}\p{Zp}\u115F\u1160\u2800\u3164\uFFA0\uFFFC\u{1D159}]',
    unicode: true,
  );

  /// A host is plain ASCII (internationalised names come as xn--), so any
  /// other character, a lookalike letter included, is marked.
  static final _notHostAscii = RegExp(r'[^\x21-\x7E]', unicode: true);

  /// Characters that draw nothing on their own: ignorables, combining
  /// marks, spaces, private use, white space, the musical null notehead
  /// (U+1D159) and the object replacement character (U+FFFC). A value made
  /// only of these is blank.
  static final _invisible = RegExp(
    r'[\p{Default_Ignorable_Code_Point}\p{M}\p{Z}\p{Co}\s\u{1D159}\uFFFC]',
    unicode: true,
  );

  static const blank = '[blank]';

  /// Agent name, login title, contact name, alert title: one line.
  static String oneLine(String s) => _show(s, _hidden);

  /// An alert body: line breaks kept, everything else hidden is marked.
  static String lines(String s) => _show(s, _hiddenBarNewline);

  /// The site a login is for.
  static String host(String s) => _show(s, _notHostAscii);

  static String _show(String s, RegExp odd) {
    if (s.replaceAll(_invisible, '').isEmpty) return blank;
    return s.replaceAllMapped(odd, (m) => _mark(m[0]!));
  }

  static String _mark(String c) => c.runes
      .map((r) => '[U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}]')
      .join();
}
