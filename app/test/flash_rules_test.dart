import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/flash/rules.dart';

List<String> show(RuleRead r) => [for (final c in r.chips) '${c.label} ${c.arrow}'];

void main() {
  test('central bank decisions: topic, subject, direction', () {
    final rba = readHeadline('RBA RAISES CASH RATE TARGET BY 25BPS TO 4.85%, AS EXPECTED ...');
    expect(rba.topic, 'rates');
    expect(rba.subject, 'AUD');
    expect(readHeadline('BULLOCK: NO WAGE PRICE SPIRAL, RATES ON HOLD').subject, 'AUD');
    expect(rba.candidate, isTrue);
    expect(show(rba).first, 'AUD ▲');

    final fed = readHeadline('FED UNEXPECTEDLY CUTS RATES BY 50 BPS');
    expect(fed.score, greaterThan(readHeadline('FED CUTS RATES BY 25 BPS, AS EXPECTED').score));
    expect(show(fed), containsAll(['USD ▼', 'Gold ▲', 'Rupee ▲']));

    final rbi = readHeadline('RBI cuts repo rate by 25 bps to 5.25%');
    expect(show(rbi), ['Rates ▼', 'Indian stocks ▲', 'Rupee ▼']);

    // A hold has no direction.
    expect(readHeadline('ECB HOLDS RATES UNCHANGED').chips, isEmpty);
  });

  test('oil supply and war headlines', () {
    final hormuz = readHeadline("IRAN SAYS IT WILL CLOSE THE STRAIT OF HORMUZ TO US SHIPS");
    expect(hormuz.topic, anyOf('oil', 'war'));
    expect(show(hormuz), contains('Oil ▲'));
    expect(show(hormuz), contains('Rupee ▼'));

    final truce = readHeadline('Israel and Iran agree to ceasefire, mediators say | FJ');
    expect(show(truce), containsAll(['Gold ▼', 'Oil ▼', 'Indian stocks ▲']));
  });

  test('trade: India named moves Indian stocks', () {
    final r = readHeadline('US TO IMPOSE 50% TARIFFS ON INDIAN GOODS FROM DEC 1');
    expect(r.topic, 'trade');
    expect(show(r), containsAll(['Indian stocks ▼', 'Rupee ▼']));
    expect(r.score, greaterThanOrEqualTo(5));
  });

  test('noise and foreign earnings score low', () {
    expect(readHeadline('Follow us on X for even faster headlines!').candidate, isFalse);
    expect(readHeadline('LUFTHANSA Q3 EARNINGS: REV €12.24B (EST €12.12B)').candidate, isFalse);
    expect(readHeadline('Week ahead: Fed, BoE and payrolls preview').candidate, isFalse);
    expect(readHeadline('TCS Q3 EARNINGS: REVENUE BEATS ESTIMATES').candidate, isTrue);
  });

  test('data with a number against the forecast is a candidate', () {
    expect(readHeadline('US CPI 3.4% VS 3.1% EXPECTED').candidate, isTrue);
    expect(readHeadline('US CPI 3.4% VS 3.1% EXPECTED').topic, 'data');
  });

  test('the channels echo each other in different words and case', () {
    expect(
        sameNews('RBA RAISES CASH RATE TARGET BY 25BPS TO 4.85%, AS EXPECTED ...',
            'RBA raises cash rate target by 25bps to 4.85%, as expected| FJ'),
        isTrue);
    expect(
        sameNews('RBA GOVERNOR BULLOCK: NO WAGE PRICE SPIRAL EXPECTED ...',
            'RBA Governor Bullock: no wage price spiral expected| FJ'),
        isTrue);
    expect(
        sameNews('RBA GOVERNOR BULLOCK: NO WAGE PRICE SPIRAL EXPECTED',
            'RBA GOVERNOR BULLOCK: UNCERTAIN HOW HIGH RATES MUST RISE'),
        isFalse);
  });
}
