import 'package:flutter_test/flutter_test.dart';
import 'package:lelomuhle_bot/backtest_engine.dart';
import 'package:lelomuhle_bot/signal_engine.dart';

void main() {
  group('LELOMUHLE historical backtest', () {
    test('ignores an unfinished candle', () {
      final candles = List.generate(
        230,
        (i) => _candle(i, 2000 + i * 0.01),
      );
      candles.add(_candle(230, 9999, complete: false));

      final result = const BacktestEngine().run('XAUUSD', candles);

      // A steadily rising series does not meet the RSI upper bound.
      expect(result.trades, isEmpty);
      expect(result.unresolvedTrades, 0);
    });

    test('returns an empty result when there is insufficient history', () {
      final candles = List.generate(
        100,
        (i) => _candle(i, 2000 + i * 0.01),
      );

      final result = const BacktestEngine().run('XAUUSD', candles);

      expect(result.totalTrades, 0);
      expect(result.winRatePercent, 0);
      expect(result.netR, 0);
    });
  });
}

MarketCandle _candle(int index, double close, {bool complete = true}) =>
    MarketCandle(
      timeUtc: DateTime.utc(2026, 1, 1).add(Duration(minutes: 5 * index)),
      open: close - 0.02,
      high: close + 0.05,
      low: close - 0.05,
      close: close,
      isComplete: complete,
    );
