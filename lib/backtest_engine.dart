import 'signal_engine.dart';

class BacktestTrade {
  const BacktestTrade({
    required this.direction,
    required this.entryTimeUtc,
    required this.exitTimeUtc,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.exitPrice,
    required this.outcome,
    required this.resultR,
  });

  final String direction;
  final DateTime entryTimeUtc;
  final DateTime exitTimeUtc;
  final double entry;
  final double stopLoss;
  final double takeProfit;
  final double exitPrice;
  /// WIN, LOSS, or AMBIGUOUS_LOSS (both levels touched; stop counted first).
  final String outcome;
  final double resultR;
}

class BacktestResult {
  const BacktestResult({
    required this.trades,
    required this.unresolvedTrades,
  });

  final List<BacktestTrade> trades;
  /// Signals whose positions had neither stop nor target reached by the end.
  final int unresolvedTrades;

  int get wins => trades.where((t) => t.resultR > 0).length;
  int get losses => trades.where((t) => t.resultR < 0).length;
  int get ambiguousLosses =>
      trades.where((t) => t.outcome == 'AMBIGUOUS_LOSS').length;
  int get totalTrades => trades.length;
  double get winRatePercent =>
      totalTrades == 0 ? 0 : wins * 100 / totalTrades;
  double get netR => trades.fold(0, (sum, trade) => sum + trade.resultR);
  double get averageR => totalTrades == 0 ? 0 : netR / totalTrades;
}

class BacktestEngine {
  const BacktestEngine({this.signalEngine = const SignalEngine()});

  final SignalEngine signalEngine;

  BacktestResult run(String symbol, List<MarketCandle> input) {
    final candles = input.where((c) => c.isComplete).toList()
      ..sort((a, b) => a.timeUtc.compareTo(b.timeUtc));

    final trades = <BacktestTrade>[];
    var unresolvedTrades = 0;
    var index = SignalEngine.minimumCandles - 1;

    // A signal is calculated only from candles up to and including index.
    while (index < candles.length - 1) {
      final history = candles.sublist(0, index + 1);
      final signal = signalEngine.analyse(symbol, history);

      if (!signal.isActionable ||
          signal.entry == null ||
          signal.stopLoss == null ||
          signal.takeProfit == null) {
        index++;
        continue;
      }

      final isBuy = signal.signal == 'BUY';
      final entry = signal.entry!;
      final stop = signal.stopLoss!;
      final target = signal.takeProfit!;
      var resolved = false;

      // Start checking only AFTER the signal candle has closed.
      for (var future = index + 1; future < candles.length; future++) {
        final candle = candles[future];
        final stopTouched = isBuy
            ? candle.low <= stop
            : candle.high >= stop;
        final targetTouched = isBuy
            ? candle.high >= target
            : candle.low <= target;

        if (!stopTouched && !targetTouched) continue;

        // Conservative rule: if both are touched in one OHLC candle,
        // assume the stop was hit first.
        final ambiguous = stopTouched && targetTouched;
        final isWin = targetTouched && !stopTouched;
        trades.add(BacktestTrade(
          direction: signal.signal,
          entryTimeUtc: signal.candleTimeUtc ?? candles[index].timeUtc,
          exitTimeUtc: candle.timeUtc,
          entry: entry,
          stopLoss: stop,
          takeProfit: target,
          exitPrice: isWin ? target : stop,
          outcome: ambiguous
              ? 'AMBIGUOUS_LOSS'
              : isWin
                  ? 'WIN'
                  : 'LOSS',
          resultR: isWin ? (signal.riskReward ?? 2.0) : -1.0,
        ));
        index = future;
        resolved = true;
        break;
      }

      if (!resolved) {
        unresolvedTrades++;
        // An unresolved position remains open at the end of this dataset.
        break;
      }
    }

    return BacktestResult(
      trades: List.unmodifiable(trades),
      unresolvedTrades: unresolvedTrades,
    );
  }
}
