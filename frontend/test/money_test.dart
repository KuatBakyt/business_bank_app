import 'package:flutter_test/flutter_test.dart';
import 'package:business_bank/core/models.dart';

void main() {
  test('Money keeps exact cents, including balances above JS double precision',
      () {
    expect(Money.input('12 345,67'), '12345.67');
    expect(Money.format('2450000.00'), '2 450 000 ₸');
    expect(Money.format('900719925474099.99'), '900 719 925 474 099,99 ₸');
    expect(Money.cents('0.01') + Money.cents('0.02'), BigInt.from(3));
    expect(() => Money.input('1.001'), throwsFormatException);
  });
}
