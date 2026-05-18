import 'dart:math';

void main() {
  double lat = 43.238949;
  double lng = 76.889709;
  int z = 15;
  int x = ((lng + 180.0) / 360.0 * (1 << z)).floor();
  int y = ((1.0 - log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * (1 << z)).floor();
  print("https://a.tile.openstreetmap.org/$z/$x/$y.png");
}
