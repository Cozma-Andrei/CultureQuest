class OpeningHoursParser {
  static const _days = {'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7};

  static bool isCurrentlyOpen(String? openingHours) {
    if (openingHours == null || openingHours.isEmpty) return true;
    final s = openingHours.toLowerCase().trim();

    if (s.contains('24/7') || s.contains('always open')) return true;
    if (s.contains('event days') || s.contains('check programme') ||
        s.contains('performances') || s.contains('box office')) return true;

    final now = DateTime.now();
    final currentMin = now.hour * 60 + now.minute;
    final weekday = now.weekday; // 1=Mon … 7=Sun

    // Handle comma-separated segments, e.g. "Mon-Thu 08:00-00:00, Fri-Sat 08:00-02:00"
    for (final segment in s.split(',')) {
      if (_segmentCoversNow(segment.trim(), weekday, currentMin)) return true;
    }
    return false;
  }

  static bool _segmentCoversNow(String seg, int weekday, int currentMin) {
    // Extract first time range HH:MM-HH:MM
    final timeRe = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})');
    final tm = timeRe.firstMatch(seg);
    if (tm == null) return true; // can't parse time - assume open

    final openMin  = int.parse(tm.group(1)!) * 60 + int.parse(tm.group(2)!);
    final closeMin = int.parse(tm.group(3)!) * 60 + int.parse(tm.group(4)!);

    // Handle midnight cross-over (e.g. 22:00-02:00)
    final inTime = closeMin > openMin
        ? currentMin >= openMin && currentMin < closeMin
        : currentMin >= openMin || currentMin < closeMin;

    if (!inTime) return false;

    // Determine which days this segment covers
    if (seg.contains('daily') || seg.contains('mon-sun') || seg.contains('every day')) {
      return true;
    }

    // Day range like "tue-sun" or "mon-fri"
    final dayRe = RegExp(r'(mon|tue|wed|thu|fri|sat|sun)\s*-\s*(mon|tue|wed|thu|fri|sat|sun)');
    final dm = dayRe.firstMatch(seg);
    if (dm != null) {
      final start = _days[dm.group(1)]!;
      final end   = _days[dm.group(2)]!;
      return start <= end
          ? weekday >= start && weekday <= end
          : weekday >= start || weekday <= end;
    }

    // Single day like "sun 09:00-23:00"
    for (final entry in _days.entries) {
      if (seg.contains(entry.key)) return weekday == entry.value;
    }

    return true; // day pattern unrecognised - assume open
  }

  static bool isWeekend() {
    final d = DateTime.now().weekday;
    return d == DateTime.saturday || d == DateTime.sunday;
  }
}
