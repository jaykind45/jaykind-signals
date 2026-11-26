import 'package:flutter_test/flutter_test.dart';
import 'package:lelomuhle_bot/market_data_provider.dart';
import 'package:lelomuhle_bot/signal_engine.dart';

void main() {
  group('LELOMUHLE on-device signal engine', () {
    test('returns WAIT when there are too few completed candles', () {
      final candles = List.generate(100, (i) => _candle(i, 2000 + i * .1));
      final result = const SignalEngine().analyse('XAUUSD', candles);
      expect(result.signal, 'WAIT');
      expect(result.reason, contains('Not enough'));
    });

    test('does not use a still-forming candle', () {
      final candles = List.generate(220, (i) => _candle(i, 2000 + i * .01));
      candles.add(_candle(220, 9999, complete: false));
      final result = const SignalEngine().analyse('XAUUSD', candles);
      expect(result.candleTimeUtc, candles[219].timeUtc);
      expect(result.entry, closeTo(candles[219].close, 0.000001));
    });

    test('stale market data forces WAIT', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final candles = List.generate(230, (i) => _candle(i, 2000 + i * .01));
      final snapshot = MarketDataSnapshot(
        symbol: 'XAUUSD', candles: candles,
        receivedAtUtc: now.subtract(const Duration(minutes: 5)),
        bid: 2020, ask: 2020.2,
      );
      final result = const SignalService().evaluate(snapshot, nowUtc: now);
      expect(result.signal, 'WAIT');
      expect(result.reason, contains('stale'));
    });

    test('missing live bid/ask forces WAIT', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final candles = List.generate(230, (i) => _candle(i, 2000 + i * .01));
      final snapshot = MarketDataSnapshot(
        symbol: 'US30', candles: candles, receivedAtUtc: now,
      );
      final result = const SignalService().evaluate(snapshot, nowUtc: now);
      expect(result.signal, 'WAIT');
      expect(result.reason, contains('bid/ask'));
    });
  });
}

MarketCandle _candle(int index, double close, {bool complete = true}) => MarketCandle(
  timeUtc: DateTime.utc(2026, 1, 1).add(Duration(minutes: 5 * index)),
  open: close - .02, high: close + .05, low: close - .05,
  close: close, isComplete: complete,
);
