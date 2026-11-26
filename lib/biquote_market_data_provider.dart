
/// Read-only adapter for Biquote's public REST endpoints.
/// Biquote is an independent reference feed, not the user's broker.
/// No orders are placed and no prices are fabricated.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'market_data_provider.dart';
import 'signal_engine.dart';

class BiquoteMarketDataProvider implements MarketDataProvider {
  BiquoteMarketDataProvider({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://biquote.io/api';
  static const double _maximumQuoteAgeSeconds = 120;

  @override
  String get providerId => 'biquote_public_reference_feed';

  @override
  Future<MarketDataSnapshot> fetchMarketData(
    String symbol, {
    int m5Limit = 288,
    int m15Limit = 192,
    int h1Limit = 168,
  }) async {
    final normalized = symbol.trim().toUpperCase();

    if (normalized != 'XAUUSD' && normalized != 'US30') {
      throw ArgumentError.value(
        symbol,
        'symbol',
        'Only XAUUSD and US30 are enabled.',
      );
    }

    final safeM5Limit = m5Limit.clamp(50, 288).toInt();
    final safeM15Limit = m15Limit.clamp(50, 192).toInt();
    final safeH1Limit = h1Limit.clamp(50, 168).toInt();

    final responses = await Future.wait([
      _fetchCandles(normalized, '5m', safeM5Limit),
      _fetchCandles(normalized, '15m', safeM15Limit),
      _fetchCandles(normalized, '1h', safeH1Limit),
      _fetchQuote(normalized),
    ]);

    final candlesM5 = responses[0] as List<MarketCandle>;
    final candlesM15 = responses[1] as List<MarketCandle>;
    final candlesH1 = responses[2] as List<MarketCandle>;
    final quoteJson = responses[3] as Map<String, dynamic>;

    final bid = _number(quoteJson['bid']);
    final ask = _number(quoteJson['ask']);
    final quoteAgeSeconds = _number(quoteJson['quoteAgeSeconds']);

    if (bid == null ||
        ask == null ||
        !bid.isFinite ||
        !ask.isFinite ||
        bid <= 0 ||
        ask < bid) {
      throw const FormatException(
        'Live quote is missing a valid bid or ask.',
      );
    }

    if (quoteAgeSeconds == null ||
        !quoteAgeSeconds.isFinite ||
        quoteAgeSeconds < 0 ||
        quoteAgeSeconds > _maximumQuoteAgeSeconds ||
        quoteJson['stale'] == true ||
        quoteJson['marketState'] == 'closed') {
      throw Exception(
        'The $normalized market feed is stale or closed.',
      );
    }

    final receivedAtUtc = DateTime.now().toUtc().subtract(
      Duration(
        milliseconds: (quoteAgeSeconds * 1000).round(),
      ),
    );

    return MarketDataSnapshot(
      symbol: normalized,
      candlesM5: candlesM5,
      candlesM15: candlesM15,
      candlesH1: candlesH1,
      receivedAtUtc: receivedAtUtc,
      bid: bid,
      ask: ask,
      providerName:
          'Biquote reference feed (${quoteJson['source'] ?? 'source not specified'})',
    );
  }

  Future<List<MarketCandle>> _fetchCandles(
    String symbol,
    String interval,
    int limit,
  ) async {
    final uri = Uri.parse('$_baseUrl/$symbol/ohlc').replace(
      queryParameters: {
        'interval': interval,
        'limit': '$limit',
      },
    );

    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        '$interval candle feed returned HTTP '
        '${response.statusCode} for $symbol.',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Invalid $interval candle response for $symbol.',
      );
    }

    final rawBars = decoded['bars'];

    if (rawBars is! List) {
      throw FormatException(
        '$interval candle response did not contain a bars list.',
      );
    }

    final candles = <MarketCandle>[];

    for (final raw in rawBars) {
      if (raw is! Map) continue;

      final time = DateTime.tryParse(
        raw['openTime']?.toString() ?? '',
      );

      final open = _number(raw['open']);
      final high = _number(raw['high']);
      final low = _number(raw['low']);
      final close = _number(raw['close']);

      if (time == null ||
          open == null ||
          high == null ||
          low == null ||
          close == null) {
        continue;
      }

      if (!open.isFinite ||
          !high.isFinite ||
          !low.isFinite ||
          !close.isFinite ||
          open <= 0 ||
          high <= 0 ||
          low <= 0 ||
          close <= 0 ||
          high < low ||
          high < open ||
          high < close ||
          low > open ||
          low > close) {
        continue;
      }

      candles.add(
        MarketCandle(
          timeUtc: time.toUtc(),
          open: open,
          high: high,
          low: low,
          close: close,
          isComplete: raw['isOpen'] != true,
        ),
      );
    }

    candles.sort(
      (a, b) => a.timeUtc.compareTo(b.timeUtc),
    );

    if (candles.isEmpty) {
      throw FormatException(
        'No valid $interval candles were returned for $symbol.',
      );
    }

    return List.unmodifiable(candles);
  }

  Future<Map<String, dynamic>> _fetchQuote(String symbol) async {
    final uri = Uri.parse('$_baseUrl/$symbol').replace(
      queryParameters: {'allowStale': 'false'},
    );

    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        'Latest quote endpoint returned HTTP '
        '${response.statusCode} for $symbol.',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid latest quote response.',
      );
    }

    return decoded;
  }

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  void close() => _client.close();
}
