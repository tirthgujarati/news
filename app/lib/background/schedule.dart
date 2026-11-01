/// When the app checks for new editions in the background.
///
/// The news task runs at 7:30 AM, 1:30 PM and 8:30 PM IST and takes up to
/// about 20 minutes, so the app checks 30 minutes after each run. If the new
/// edition isn't there yet, it retries every 15 minutes, up to an hour.
library;

const ist = Duration(hours: 5, minutes: 30);

/// (hour, minute) in IST.
const checkTimesIst = [(8, 0), (14, 0), (21, 0)];

const retryEvery = Duration(minutes: 15);
const maxRetries = 4;

/// The next fixed check time after [now], as a UTC time.
DateTime nextCheckUtc(DateTime now) {
  final nowUtc = now.toUtc();
  final nowIst = nowUtc.add(ist);
  for (var dayOffset = 0; dayOffset <= 1; dayOffset++) {
    for (final (h, m) in checkTimesIst) {
      final candidate =
          DateTime.utc(nowIst.year, nowIst.month, nowIst.day + dayOffset, h, m)
              .subtract(ist);
      if (candidate.isAfter(nowUtc)) return candidate;
    }
  }
  throw StateError('unreachable: there is always a check within a day');
}
