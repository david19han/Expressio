~~ TODO RegExp portion of stdlib which will include commonly used RegExps.
regexp alphaLower;
regexp alphaUpper;
regexp numeric;
regexp alphaNumeric
regexp digits;
alphaLower = lit 'a' | lit 'b' | lit 'c' | lit 'd' | lit 'e' | lit 'f' | lit 'g' | lit 'h' | lit 'i' | lit 'j' | lit 'k' | lit 'l' | lit 'm' | lit 'n' | lit 'o' | lit 'p' | lit 'q' | lit 'r' | lit 's' | lit 't' | lit 'u' | lit 'v' | lit 'w' | lit 'x' | lit 'y' | lit 'z';
alphaUpper = lit 'A' | lit 'B' | lit 'C' | lit 'D' | lit 'E' | lit 'F' | lit 'G' | lit 'H' | lit 'I' | lit 'J' | lit 'K' | lit 'L' | lit 'M' | lit 'N' | lit 'O' | lit 'P' | lit 'Q' | lit 'R' | lit 'S' | lit 'T' | lit 'U' | lit 'V' | lit 'W' | lit 'X' | lit 'Y' | lit 'Z';
numeric = lit '0' | lit '1' | lit '2' | lit '3' | lit '4' | lit '5' | lit '6' | lit '7' | lit '8' | lit '9';
alpha = alphaLower | alphaUpper;
alphaNumeric = alpha | numeric;
digits = numeric **;
