import 'dart:math';

class DailyAdvice {
  final String text;
  final String? translation;

  const DailyAdvice({required this.text, this.translation});
}

class AdviceService {
  static final List<DailyAdvice> _advices = [
    const DailyAdvice(
      text: "Тот, кто подчиняется порядку, не станет рабом.",
      translation: "Тәртіпке бағынған құл болмайды.",
    ),
    const DailyAdvice(
      text: "Без шлема ездить нельзя! Ваша безопасность — наш приоритет.",
      translation: "Дулығасыз жүруге болмайды! Сіздің қауіпсіздігіңіз — біздің басымдығымыз.",
    ),
    const DailyAdvice(
      text: "На пешеходном переходе нужно спешиться. Не торопитесь, успеем всё!",
      translation: "Жаяу жүргіншілер өтпесінде самокаттан түсу керек. Асықпаңыз, бәріне үлгереміз!",
    ),
    const DailyAdvice(
      text: "Соблюдайте дистанцию и скоростной режим. Правила созданы для всех.",
      translation: "Қашықтықты және жылдамдық режимін сақтаңыз. Ережелер бәріне ортақ.",
    ),
    const DailyAdvice(
      text: "Проверьте тормоза перед началом поездки. Это займет всего секунду.",
      translation: "Жүруді бастамас бұрын тежегішті тексеріңиз. Бұл небәрі бір секундты алады.",
    ),
  ];

  static DailyAdvice getDailyAdvice() {
    final now = DateTime.now();
    // Use day of the year as index to rotate daily
    final index = (now.day + now.month * 31) % _advices.length;
    return _advices[index];
  }
}
