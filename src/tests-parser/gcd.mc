~~ comments 
int gcd (int a, int b) {
  for ;a != b; {
    if (a > b) a = a - b;
    else b = b - a;
  }
  return a;
}