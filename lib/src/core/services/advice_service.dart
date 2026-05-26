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
      translation:
          "Дулығасыз жүруге болмайды! Сіздің қауіпсіздігіңіз — біздің басымдығымыз.",
    ),
    const DailyAdvice(
      text:
          "На пешеходном переходе нужно спешиться. Не торопитесь, успеем всё!",
      translation:
          "Жаяу жүргіншілер өтпесінде самокаттан түсу керек. Асықпаңыз, бәріне үлгереміз!",
    ),
    const DailyAdvice(
      text:
          "Соблюдайте дистанцию и скоростной режим. Правила созданы для всех.",
      translation:
          "Қашықтықты және жылдамдық режимін сақтаңыз. Ережелер бәріне ортақ.",
    ),
    const DailyAdvice(
      text:
          "Проверьте тормоза перед началом поездки. Это займет всего секунду.",
      translation:
          "Жүруді бастамас бұрын тежегішті тексеріңиз. Бұл небәрі бір секундты алады.",
    ),
    const DailyAdvice(
      text:
          "Работайте эффективно, но не забывайте о балансе. Здоровье — главный актив.",
      translation:
          "Тиімді жұмыс істесіз, бірақ тепе-теңдікті ұмытпаңыз. Денсаулық — ең басты капитал.",
    ),
    const DailyAdvice(
      text: "Сотрудничество ведет к успеху. Поддерживайте команду.",
      translation: "Ынтымақ сәттілікке әкеледі. Командалық жұмысты сақтаңыз.",
    ),
    const DailyAdvice(
      text: "Обучение — ключ к развитию. Учитесь новому каждый день.",
      translation: "Оқыту — дамудың кілті. Күн сайын жаңаны үйреніңіз.",
    ),
    const DailyAdvice(
      text: "Будьте ответственны за свои действия. Вы ответственный сотрудник.",
      translation:
          "Өз әрекеттеріңіз үшін жауапты болыңыз. Сіз жауапты қызметкерсіз.",
    ),
    const DailyAdvice(
      text: "Уважайте коллегу и его время. Честность — основа доверия.",
      translation:
          "Жұмпарыңыздың уақытын және сыйлаңыз. Адалдық — сенімнің негізі.",
    ),
    const DailyAdvice(
      text: "Дисциплина — ключ к успеху. Следуйте правилам компании.",
      translation: "Тәртіп — сәттіліктің кілті. Компания ережелерін сақтаңыз.",
    ),
  ];

  static DailyAdvice getDailyAdvice() {
    final now = DateTime.now();
    final index = (now.day + now.month * 31) % _advices.length;
    return _advices[index];
  }
}
