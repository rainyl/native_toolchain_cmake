import 'package:add/add.dart';
import 'package:test/test.dart';

void main() {
  test('calculate', () {
    expect(calculate(7, 7, times: 3), 42);
  });
}
