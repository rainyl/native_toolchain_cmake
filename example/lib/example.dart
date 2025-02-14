import 'src/g/add.g.dart';

int calculate(int a, int b, {int times = 1}) {
  final result = math_add(a, b);
  return result * times;
}
