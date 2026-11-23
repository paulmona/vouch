import { isIPv4, isIPv6 } from "node:net";

// Text from an agent that the owner reads on the phone. Control, format (bidi overrides,
// zero-width) and line-separator characters can hide or reorder what is shown, and SQLite
// cuts a value at a NUL. An unassigned code point may be drawn as nothing at all. The last
// group is letters and symbols that render as nothing: the Hangul fillers, the blank Braille
// pattern, the null notehead and the object replacement character.
const HIDDEN = /[\p{Cc}\p{Cf}\p{Cs}\p{Cn}\p{Zl}\p{Zp}ᅟᅠ⠀ㅤﾠ\u{1D159}\uFFFC]/u;
const HIDDEN_BAR_NEWLINE = /[^\P{Cc}\n]|[\p{Cf}\p{Cs}\p{Cn}\p{Zl}\p{Zp}ᅟᅠ⠀ㅤﾠ\u{1D159}\uFFFC]/u;

// Marks, variation selectors and joiners are fine beside a letter (an accent, an emoji) but
// show nothing on their own. Private-use characters are allowed in a value, since login titles
// do carry them, but what they look like depends on the phone's fonts.
const NOTHING_TO_SEE = /[\p{Default_Ignorable_Code_Point}\p{M}\p{Z}\p{Co}\s]/gu;
const visible = (s: string): boolean => s.replace(NOTHING_TO_SEE, "") !== "";

export const oneLine = (s: string): boolean => visible(s) && !HIDDEN.test(s);
export const lines = (s: string): boolean => visible(s) && !HIDDEN_BAR_NEWLINE.test(s);

const LABEL = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/i;

// A DNS name (internationalised names in their xn-- form) or an IP address. No scheme, port or
// path, and no IPv6 zone: node accepts any text after the %.
export const isHost = (s: string): boolean =>
  isIPv4(s) || (isIPv6(s) && !s.includes("%")) || (s.length <= 253 && s.split(".").every((l) => LABEL.test(l)));
