export class BadNumber extends Error {}

// E.164 for Canadian and US numbers, the only ones voip.ms reaches. Numbers it
// can't normalise are refused with a reason the app can show.
export function normalize(raw: string): string {
  let digits = (raw ?? "").replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) digits = digits.slice(1);
  if (digits.length !== 10 || digits[0] === "0" || digits[0] === "1") {
    throw new BadNumber("Only Canadian and US 10-digit numbers can be texted.");
  }
  return `+1${digits}`;
}
