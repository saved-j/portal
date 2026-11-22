// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a ru locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'ru';

  static String m0(count) => "Выбрано: ${count}";

  static String m1(name) => "«${name}» добавлен в локальные прокси";

  static String m2(name) => "«${name}» уже есть в локальных прокси";

  static String m3(count, skipped) =>
      "Будет добавлено: ${count}, пропущено (уже есть): ${skipped}";

  static String m4(detail) => "Не удалось очистить данные: ${detail}";

  static String m5(code) =>
      "Windows отказалась запускать FlClashCore.exe (ошибка ${code}). Политики контроля приложений, такие как Smart App Control или AppLocker, блокируют неподписанные программы; разрешите FlClashX в этой политике или отключите её и повторите попытку.";

  static String m6(name) =>
      "Приложение два раза подряд не смогло завершить запуск. Чтобы разорвать цикл, профиль ${name} снят с выбора, а автоматическая настройка пропущена. Вы можете выбрать его снова в любой момент.";

  static String m7(count, label) =>
      "${Intl.plural(count, one: 'Отброшено ${label} правило SUB-RULE: пользовательские профили не поддерживают подправила', few: 'Отброшено ${label} правила SUB-RULE: пользовательские профили не поддерживают подправила', many: 'Отброшено ${label} правил SUB-RULE: пользовательские профили не поддерживают подправила', other: 'Отброшено ${label} правила SUB-RULE: пользовательские профили не поддерживают подправила')}";

  static String m8(message) =>
      "Ядро не может разобрать этот прокси: ${message}";

  static String m9(proxy, target) =>
      "${proxy} подключается через ${target}, а ${target} снова ведёт к ${proxy}, поэтому подключение зацикливается";

  static String m10(name) =>
      "Имя ${name} уже занято другим прокси или группой прокси";

  static String m11(path) =>
      "Группы прокси ссылаются друг на друга по кругу: ${path}";

  static String m12(name) =>
      "Резервом для пустой группы может быть только прокси, а ${name} не существует или является группой прокси";

  static String m13(name, message) =>
      "${name}: недопустимое регулярное выражение: ${message}";

  static String m14(name) => "Прокси для подключения ${name} не существует";

  static String m15(names) => "Эти провайдеры прокси не существуют: ${names}";

  static String m16(names) => "Эти прокси или политики не существуют: ${names}";

  static String m17(name) =>
      "${name} — встроенное имя политики, его нельзя использовать";

  static String m18(count) =>
      "Проблем: ${count}, применение профиля может завершиться ошибкой";

  static String m19(count) =>
      "${Intl.plural(count, one: '${count} день назад', few: '${count} дня назад', many: '${count} дней назад', other: '${count} дня назад')}";

  static String m20(count) => "${count} дн. назад";

  static String m21(label) => "Удалить выбранные элементы (${label})?";

  static String m22(label) => "Удалить «${label}»?";

  static String m23(label) => "Сведения: ${label}";

  static String m24(name) =>
      "Подключение через ${name} ведёт обратно к прокси, который его использует, поэтому соединение остановлено";

  static String m25(label) => "Поле «${label}» не может быть пустым";

  static String m26(reason) => "Не удалось скачать подписку: ${reason}";

  static String m27(label) => "«${label}» уже существует";

  static String m28(value) => "Истекает: ${value}";

  static String m29(value) => "до ${value}";

  static String m30(address) =>
      "Внешний контроллер позволяет управлять ядром по адресу ${address}.";

  static String m31(count) => "Ошибок: ${count}";

  static String m32(label, message) => "${label}: ${message}";

  static String m33(name) => "${name}: уже последняя версия";

  static String m34(name) => "${name}: обновлено";

  static String m35(count) =>
      "${Intl.plural(count, one: '${count} группа', few: '${count} группы', many: '${count} групп', other: '${count} группы')}";

  static String m36(count) => "Тайм-аут: ${count}";

  static String m37(action) =>
      "Уже используется для «${action}». При сохранении будет перенесено сюда.";

  static String m38(modifiers) =>
      "Добавьте хотя бы одну из клавиш: ${modifiers}";

  static String m39(count) =>
      "${Intl.plural(count, one: '${count} час назад', few: '${count} часа назад', many: '${count} часов назад', other: '${count} часа назад')}";

  static String m40(count) => "${count} ч назад";

  static String m41(target) => "${target} — недопустимая политика";

  static String m42(proxyName) => "${proxyName} — недопустимый прокси";

  static String m43(providerName) =>
      "${providerName} — недопустимый провайдер прокси";

  static String m44(ruleSet) => "${ruleSet} — недопустимый набор правил";

  static String m45(subRule) => "${subRule} — недопустимый SUB_RULE";

  static String m46(count) =>
      "${Intl.plural(count, one: '${count} элемент', few: '${count} элемента', many: '${count} элементов', other: '${count} элемента')}";

  static String m47(line, message) => "Строка ${line}: ${message}";

  static String m48(appName) =>
      "1. Откройте Системные настройки → Конфиденциальность и безопасность\n2. Выберите «Службы геолокации»\n3. Найдите в списке ${appName} и включите его\n\nПосле этого вернитесь в приложение.";

  static String m49(label, max) => "«${label}» — не более ${max} символов";

  static String m50(size) => "Освобождено ${size}";

  static String m51(count) =>
      "${Intl.plural(count, one: '${count} минуту назад', few: '${count} минуты назад', many: '${count} минут назад', other: '${count} минуты назад')}";

  static String m52(count) => "${count} мин назад";

  static String m53(count) =>
      "${Intl.plural(count, one: '${count} месяц назад', few: '${count} месяца назад', many: '${count} месяцев назад', other: '${count} месяца назад')}";

  static String m54(count) => "${count} мес. назад";

  static String m55(code) =>
      "Сервер запретил доступ (HTTP ${code}). Возможно, ссылка устарела или учётные данные неверны";

  static String m56(code) => "Сервер отклонил запрос (HTTP ${code})";

  static String m57(code) =>
      "По этому адресу ничего не найдено (HTTP ${code}). Проверьте правильность URL";

  static String m58(detail) => "Сетевой запрос не выполнен: ${detail}";

  static String m59(code) =>
      "На сервере произошла ошибка (HTTP ${code}). Повторите попытку позже";

  static String m60(label) => "${label}: пока пусто";

  static String m61(label, min, max) =>
      "Значение «${label}» должно быть от ${min} до ${max}";

  static String m62(label) => "Значение «${label}» должно быть числом";

  static String m63(label) =>
      "Значение «${label}» должно быть от 1024 до 49151";

  static String m64(port) => "Порт ${port}";

  static String m65(reason) => "Этот режим недоступен: ${reason}";

  static String m66(reason) => "Оба режима недоступны: ${reason}";

  static String m67(reason) => "Не удалось открыть портал: ${reason}";

  static String m68(count) => "Неудачных попыток подряд: ${count}";

  static String m69(reason) => "Не удалось переключить портал: ${reason}";

  static String m70(name) => "Подписка «${name}» добавлена";

  static String m71(days) =>
      "${Intl.plural(days, one: '${days} день', few: '${days} дня', many: '${days} дней', other: '${days} дня')}";

  static String m72(hours) =>
      "${Intl.plural(hours, one: '${hours} час', few: '${hours} часа', many: '${hours} часов', other: '${hours} часа')}";

  static String m73(total) => "осталось из ${total}";

  static String m74(minutes) =>
      "${Intl.plural(minutes, one: '${minutes} минута', few: '${minutes} минуты', many: '${minutes} минут', other: '${minutes} минуты')}";

  static String m75(date) => "до ${date}";

  static String m76(label, profiles) =>
      "«${label}» ещё используется профилями: ${profiles}. После удаления они будут работать неправильно. Удалить?";

  static String m77(count, label) =>
      "${Intl.plural(count, other: '${label} прокси')}";

  static String m78(name, count) => "${name} и другие (${count} прокси)";

  static String m79(removed) =>
      "Будут удалены прокси: ${removed}. Строка с изменённым именем считается новым прокси, а пользовательские профили, ссылающиеся на удалённые, пометят их как отсутствующие. Применить?";

  static String m80(removed, added) =>
      "Будут удалены прокси: ${removed}. Будут добавлены: ${added}. Строка с изменённым именем считается новым прокси, а пользовательские профили, ссылающиеся на удалённые, пометят их как отсутствующие. Применить?";

  static String m81(name) =>
      "${name} выбрана целью MATCH. Сначала выберите другую цель, потом выключайте или удаляйте";

  static String m82(name) =>
      "${name} выбрана целью добавленных правил. Сначала смените им цель, потом выключайте или удаляйте";

  static String m83(name) => "${name} нет в профиле";

  static String m84(name) => "Имя ${name} уже занято в профиле";

  static String m85(name) =>
      "${name} берёт узлы из провайдера, такие звенья пока не поддерживаются";

  static String m86(name) =>
      "В ${name} есть узлы, которые не подключаются через другое звено, например direct";

  static String m87(name) =>
      "Фильтр группы ${name} использует синтаксис, который приложение пока не читает";

  static String m88(label) =>
      "На «${label}» ещё ссылаются правила, группы прокси, прокси для подключения, DNS или NTP этого профиля, после удаления эти ссылки перестанут работать. Удалить?";

  static String m89(count, label) =>
      "${Intl.plural(count, one: '${label} группа прокси', few: '${label} группы прокси', many: '${label} групп прокси', other: '${label} группы прокси')}";

  static String m90(count, label) =>
      "${Intl.plural(count, one: '${label} правило', few: '${label} правила', many: '${label} правил', other: '${label} правила')}";

  static String m91(appName) => "${appName} (Безопасный режим)";

  static String m92(count) =>
      "${Intl.plural(count, one: '${count} секунда', few: '${count} секунды', many: '${count} секунд', other: '${count} секунды')}";

  static String m93(count) => "Действуют: ${count}";

  static String m94(count) =>
      "${Intl.plural(count, one: '${count} проблема', few: '${count} проблемы', many: '${count} проблем', other: '${count} проблемы')}";

  static String m95(count) =>
      "${Intl.plural(count, one: '${count} настройка', few: '${count} настройки', many: '${count} настроек', other: '${count} настройки')}";

  static String m96(link) => "Не удалось прочитать прокси из ${link}";

  static String m97(label) => "«${label}» — только одно значение";

  static String m98(value) => "Сортировка: ${value}";

  static String m99(value) => "${value} КБ/с";

  static String m100(days) =>
      "Ваша подписка истекает через ${Intl.plural(days, one: '${days} день', few: '${days} дня', many: '${days} дней', other: '${days} дня')}";

  static String m101(value) => "Трафик: ${value}";

  static String m102(value) => "Пик ${value}";

  static String m103(value) => "Всего ${value}";

  static String m104(transport) => "Заголовки ${transport}";

  static String m105(index, total) => "${index} из ${total}";

  static String m106(time) =>
      "Обновление не удалось. Подписка продолжит работать в автономном режиме, следующая попытка в ${time}.";

  static String m107(label) => "Значение «${label}» должно быть URL";

  static String m108(appName) =>
      "Вы не дали ${appName} разрешение на подключение VPN";

  static String m109(count) =>
      "${Intl.plural(count, one: '${count} год назад', few: '${count} года назад', many: '${count} лет назад', other: '${count} года назад')}";

  static String m110(count) =>
      "${Intl.plural(count, one: '${count} г. назад', few: '${count} г. назад', many: '${count} лет назад', other: '${count} г. назад')}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("О программе"),
    "aboutBuiltOn": MessageLookupByLibrary.simpleMessage("На чём построено"),
    "aboutChat": MessageLookupByLibrary.simpleMessage("💬 Чат"),
    "aboutContributors": MessageLookupByLibrary.simpleMessage("Контрибуторы"),
    "aboutCores": MessageLookupByLibrary.simpleMessage("Ядра"),
    "aboutPortal": MessageLookupByLibrary.simpleMessage("Портал"),
    "aboutPortalNetworkCore": MessageLookupByLibrary.simpleMessage(
      "ядро сети порталов",
    ),
    "aboutSite": MessageLookupByLibrary.simpleMessage("🌐 Сайт"),
    "aboutSubscribe": MessageLookupByLibrary.simpleMessage(
      "💳 Оформить подписку",
    ),
    "aboutTelegramSupport": MessageLookupByLibrary.simpleMessage(
      "📱 Поддержка в Telegram",
    ),
    "aboutVkSupport": MessageLookupByLibrary.simpleMessage("📱 Поддержка в VK"),
    "accessControl": MessageLookupByLibrary.simpleMessage("Контроль доступа"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Через VPN проходят только выбранные приложения",
    ),
    "accessControlAllow": MessageLookupByLibrary.simpleMessage("Разрешить"),
    "accessControlDeny": MessageLookupByLibrary.simpleMessage("Запретить"),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "Контроль доступа определяет, какие приложения идут через портал.",
    ),
    "accessControlDisabledDesc": MessageLookupByLibrary.simpleMessage(
      "Контроль доступа приложений отключён",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Выбранные приложения исключаются из VPN",
    ),
    "accessControlSelectedCount": m0,
    "accessControlSettings": MessageLookupByLibrary.simpleMessage(
      "Настройки контроля доступа",
    ),
    "account": MessageLookupByLibrary.simpleMessage("Аккаунт"),
    "action": MessageLookupByLibrary.simpleMessage("Действие"),
    "actionDelayTest": MessageLookupByLibrary.simpleMessage(
      "Проверить все задержки",
    ),
    "actionDirectMode": MessageLookupByLibrary.simpleMessage("Прямой режим"),
    "actionGlobalMode": MessageLookupByLibrary.simpleMessage(
      "Глобальный режим",
    ),
    "actionMode": MessageLookupByLibrary.simpleMessage("Переключить режим"),
    "actionProxy": MessageLookupByLibrary.simpleMessage("Системный прокси"),
    "actionRuleMode": MessageLookupByLibrary.simpleMessage("Режим правил"),
    "actionStart": MessageLookupByLibrary.simpleMessage("Старт/Стоп"),
    "actionTun": MessageLookupByLibrary.simpleMessage("TUN"),
    "actionUpdateProfiles": MessageLookupByLibrary.simpleMessage(
      "Обновить профили",
    ),
    "actionView": MessageLookupByLibrary.simpleMessage("Показать/Скрыть"),
    "add": MessageLookupByLibrary.simpleMessage("Добавить"),
    "addCustomProxy": MessageLookupByLibrary.simpleMessage("Добавить прокси"),
    "addFilters": MessageLookupByLibrary.simpleMessage("Добавить фильтры"),
    "addNodes": MessageLookupByLibrary.simpleMessage("Добавить узлы"),
    "addOverrideEntry": MessageLookupByLibrary.simpleMessage(
      "Добавить параметр",
    ),
    "addProfile": MessageLookupByLibrary.simpleMessage("Добавить профиль"),
    "addProfileFromClipboard": MessageLookupByLibrary.simpleMessage(
      "Добавить профиль из буфера",
    ),
    "addProxyChain": MessageLookupByLibrary.simpleMessage("Добавить цепочку"),
    "addProxyChainHop": MessageLookupByLibrary.simpleMessage("Добавить звено"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Добавить группу прокси",
    ),
    "addRule": MessageLookupByLibrary.simpleMessage("Добавить правило"),
    "addSettingEntry": MessageLookupByLibrary.simpleMessage(
      "Добавить параметр",
    ),
    "addSsid": MessageLookupByLibrary.simpleMessage("Добавить SSID"),
    "addToLocalProxies": MessageLookupByLibrary.simpleMessage(
      "Добавить в локальные прокси",
    ),
    "addedRules": MessageLookupByLibrary.simpleMessage("Добавленные правила"),
    "addedToLocalProxies": m1,
    "additionalParameters": MessageLookupByLibrary.simpleMessage(
      "Дополнительные параметры",
    ),
    "additionalPrefix": MessageLookupByLibrary.simpleMessage("Префикс имени"),
    "additionalSuffix": MessageLookupByLibrary.simpleMessage("Суффикс имени"),
    "address": MessageLookupByLibrary.simpleMessage("Адрес"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("Адрес сервера WebDAV"),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "Введите корректный адрес WebDAV",
    ),
    "advancedConfig": MessageLookupByLibrary.simpleMessage(
      "Расширенная конфигурация",
    ),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Расширенная конфигурация включает сеть, DNS, добавленные правила и скрипты.",
    ),
    "ageEncryptedProfile": MessageLookupByLibrary.simpleMessage(
      "Зашифрованный профиль",
    ),
    "ageSecretKey": MessageLookupByLibrary.simpleMessage("Секретный ключ age"),
    "ageSecretKeyRequiredTip": MessageLookupByLibrary.simpleMessage(
      "Подписка зашифрована с помощью age, для расшифровки нужен секретный ключ age",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("Я согласен"),
    "allReferencedProxies": MessageLookupByLibrary.simpleMessage(
      "Все используемые прокси",
    ),
    "allReferencedProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Все используемые провайдеры прокси",
    ),
    "allowBypass": MessageLookupByLibrary.simpleMessage(
      "Разрешить приложениям обходить VPN",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("Разрешить LAN"),
    "allowedIps": MessageLookupByLibrary.simpleMessage("Разрешённые IP"),
    "alreadyInLocalProxies": m2,
    "announcement": MessageLookupByLibrary.simpleMessage("Объявление"),
    "answers": MessageLookupByLibrary.simpleMessage("Ответы"),
    "app": MessageLookupByLibrary.simpleMessage("Приложение"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage(
      "Контроль доступа приложений",
    ),
    "appProxiesEmpty": MessageLookupByLibrary.simpleMessage(
      "Нет локальных прокси",
    ),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage(
      "Добавлять системный DNS",
    ),
    "applied": MessageLookupByLibrary.simpleMessage("Применено"),
    "applyNow": MessageLookupByLibrary.simpleMessage("Применить сейчас"),
    "authentication": MessageLookupByLibrary.simpleMessage("Аутентификация"),
    "authenticationDesc": MessageLookupByLibrary.simpleMessage(
      "Аутентификация требует логин и пароль для локального порта прокси.",
    ),
    "authenticationSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Пока включена аутентификация, системный прокси не применяется.",
    ),
    "authorize": MessageLookupByLibrary.simpleMessage("Разрешить"),
    "authorized": MessageLookupByLibrary.simpleMessage("Разрешено"),
    "auto": MessageLookupByLibrary.simpleMessage("Авто"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage(
      "Автопроверка обновлений",
    ),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage(
      "Автозакрытие соединений",
    ),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Автозакрытие соединений обрывает открытые соединения при смене прокси.",
    ),
    "autoInclude": MessageLookupByLibrary.simpleMessage(
      "Автоматическое включение",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("Автозапуск"),
    "autoPingAsInSubscription": MessageLookupByLibrary.simpleMessage(
      "Как в подписке",
    ),
    "autoPingDefault": MessageLookupByLibrary.simpleMessage("По умолчанию"),
    "autoPingExplainedBody": MessageLookupByLibrary.simpleMessage(
      "Прочтите это внимательно.\n\nВ отличие от других приложений, наше замеряет реальную задержку через тоннель, а не просто даёт вам красивые цифры.\n\nДело в том, что пинг (задержка) — это просто скорость отклика сервера, не отражающая ПРОПУСКНУЮ СПОСОБНОСТЬ. Сервер может откликаться быстро, но иметь неприлично узкий канал с низкой пропускной способностью: пинг красивый, а скорости нет.\n\nПоэтому не стоит брезговать серверами, у которых не самая красивая задержка, — пробуйте и их.",
    ),
    "autoPingExplainedTitle": MessageLookupByLibrary.simpleMessage(
      "Автозамер задержки включён",
    ),
    "autoPingHoldHint": MessageLookupByLibrary.simpleMessage(
      "Удерживайте палец на сервере, чтобы проверить пинг именно его, прямо сейчас.",
    ),
    "autoPingOff": MessageLookupByLibrary.simpleMessage("Выключен"),
    "autoPingPeriod": MessageLookupByLibrary.simpleMessage(
      "Интервал автопинга",
    ),
    "autoPingPeriodNote": MessageLookupByLibrary.simpleMessage(
      "Чем короче интервал, тем больше расход батареи: каждый сервер опрашивается в каждом периоде.",
    ),
    "autoRun": MessageLookupByLibrary.simpleMessage("Автовключение"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage(
      "Автовключение открывает портал при запуске приложения.",
    ),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage(
      "Автонастройка системного DNS",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("Автообновление"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления",
    ),
    "back": MessageLookupByLibrary.simpleMessage("Назад"),
    "backgroundBlur": MessageLookupByLibrary.simpleMessage("Размытие фона"),
    "backup": MessageLookupByLibrary.simpleMessage("Резервное копирование"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование и восстановление",
    ),
    "backupFromNewerVersion": MessageLookupByLibrary.simpleMessage(
      "Резервная копия создана более новой версией приложения. Обновите приложение перед восстановлением",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage(
      "Резервная копия создана",
    ),
    "basicInfo": MessageLookupByLibrary.simpleMessage("Основная информация"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("Базовые политики"),
    "batchAdd": MessageLookupByLibrary.simpleMessage("Массовое добавление"),
    "batchImport": MessageLookupByLibrary.simpleMessage("Массовый импорт"),
    "batchLinkInputTip": MessageLookupByLibrary.simpleMessage(
      "По одной ссылке на строку",
    ),
    "batchListInputTip": MessageLookupByLibrary.simpleMessage(
      "По одному значению на строку или через запятую",
    ),
    "batchMapInputTip": MessageLookupByLibrary.simpleMessage(
      "По одной записи на строку: ключ, пробел, значение",
    ),
    "batchPreviewTip": m3,
    "batchUrlInputTip": MessageLookupByLibrary.simpleMessage(
      "По одному URL на строку",
    ),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "Игнорирование оптимизации батареи позволяет приложению работать в фоне.",
    ),
    "beta": MessageLookupByLibrary.simpleMessage("Beta"),
    "bind": MessageLookupByLibrary.simpleMessage("Привязать"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage(
      "Режим чёрного списка",
    ),
    "blockConnection": MessageLookupByLibrary.simpleMessage(
      "Заблокировать соединение",
    ),
    "brightness": MessageLookupByLibrary.simpleMessage("Яркость"),
    "buyPlan": MessageLookupByLibrary.simpleMessage("Продлить подписку"),
    "buyTraffic": MessageLookupByLibrary.simpleMessage("Докупить трафик"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("Исключённые домены"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Исключённые домены действуют только при включённом системном прокси.",
    ),
    "bypassPrivateRoute": MessageLookupByLibrary.simpleMessage(
      "Обходить частные адреса",
    ),
    "bypassPrivateRouteDesc": MessageLookupByLibrary.simpleMessage(
      "При обходе частных адресов адреса LAN, loopback и multicast идут в обход TUN.",
    ),
    "cache": MessageLookupByLibrary.simpleMessage("Кэш"),
    "cacheAlgorithm": MessageLookupByLibrary.simpleMessage("Алгоритм кэша"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "Кэш повреждён. Очистить его?",
    ),
    "cacheMaxSize": MessageLookupByLibrary.simpleMessage("Размер кэша"),
    "cameraPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешите доступ к камере в системных настройках, чтобы сканировать QR-коды, или выберите изображение QR-кода из галереи.",
    ),
    "cameraPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Требуется доступ к камере",
    ),
    "cameraUnavailable": MessageLookupByLibrary.simpleMessage(
      "Камера недоступна",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Отмена"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("Снять выделение"),
    "cannotSave": MessageLookupByLibrary.simpleMessage("Не удалось сохранить"),
    "changeProxyFailedTip": MessageLookupByLibrary.simpleMessage(
      "Не удалось переключить портал, возвращён предыдущий выбор",
    ),
    "changeServer": MessageLookupByLibrary.simpleMessage("Сменить портал"),
    "changelogBreaking": MessageLookupByLibrary.simpleMessage(
      "Важные изменения",
    ),
    "changelogFeatures": MessageLookupByLibrary.simpleMessage("Новые функции"),
    "changelogFixes": MessageLookupByLibrary.simpleMessage("Исправления"),
    "changelogPerformance": MessageLookupByLibrary.simpleMessage(
      "Производительность",
    ),
    "changelogReverts": MessageLookupByLibrary.simpleMessage("Откаты"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("Проверить обновления"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage(
      "Установлена последняя версия",
    ),
    "cipher": MessageLookupByLibrary.simpleMessage("Шифр"),
    "clearData": MessageLookupByLibrary.simpleMessage("Очистить данные"),
    "clearDataAndExitTip": MessageLookupByLibrary.simpleMessage(
      "Все профили, настройки и локальные данные будут удалены, после чего приложение закроется. Откройте его снова, чтобы начать заново.",
    ),
    "clearDataFailed": m4,
    "clearDnsCache": MessageLookupByLibrary.simpleMessage("Очистить кэш DNS"),
    "clearDnsCacheFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось очистить кэш DNS",
    ),
    "clearSearch": MessageLookupByLibrary.simpleMessage("Очистить поиск"),
    "clientFingerprint": MessageLookupByLibrary.simpleMessage(
      "Отпечаток клиента",
    ),
    "clipboardExport": MessageLookupByLibrary.simpleMessage(
      "Экспорт в буфер обмена",
    ),
    "clipboardImport": MessageLookupByLibrary.simpleMessage(
      "Импорт из буфера обмена",
    ),
    "clipboardWriteFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось скопировать в буфер обмена. Возможно, выделение слишком велико",
    ),
    "close": MessageLookupByLibrary.simpleMessage("Закрыть"),
    "closeConnections": MessageLookupByLibrary.simpleMessage(
      "Закрыть соединения",
    ),
    "closePortal": MessageLookupByLibrary.simpleMessage("Закрыть портал"),
    "color": MessageLookupByLibrary.simpleMessage("Цвет"),
    "colorStyle": MessageLookupByLibrary.simpleMessage("Стиль палитры"),
    "compact": MessageLookupByLibrary.simpleMessage("Компактный"),
    "confirm": MessageLookupByLibrary.simpleMessage("Подтвердить"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage(
      "Удалить все данные?",
    ),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Удалить эту группу прокси?",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage(
      "Закрыть это окно?",
    ),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage(
      "Принудительно уронить ядро?",
    ),
    "congestionControl": MessageLookupByLibrary.simpleMessage(
      "Управление перегрузкой",
    ),
    "congestionController": MessageLookupByLibrary.simpleMessage(
      "Управление перегрузкой TCP",
    ),
    "congestionControllerDesc": MessageLookupByLibrary.simpleMessage(
      "Управление перегрузкой TCP действует только со стеком mips.",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("Подключено"),
    "connecting": MessageLookupByLibrary.simpleMessage("Подключение…"),
    "connection": MessageLookupByLibrary.simpleMessage("Соединение"),
    "connectionStats": MessageLookupByLibrary.simpleMessage(
      "Статистика подключений",
    ),
    "connectionStatsDesc": MessageLookupByLibrary.simpleMessage(
      "Подключения, запросы и DNS-запросы",
    ),
    "connections": MessageLookupByLibrary.simpleMessage("Соединения"),
    "connectionsNotReset": MessageLookupByLibrary.simpleMessage(
      "Выбор применён, существующие подключения не сброшены",
    ),
    "connectivity": MessageLookupByLibrary.simpleMessage("Подключение: "),
    "content": MessageLookupByLibrary.simpleMessage("Содержимое"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Содержимое не может быть пустым",
    ),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage(
      "Глобальные добавленные правила",
    ),
    "copy": MessageLookupByLibrary.simpleMessage("Копировать"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage(
      "Копировать переменные окружения",
    ),
    "copyLink": MessageLookupByLibrary.simpleMessage("Копировать ссылку"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("Скопировано"),
    "core": MessageLookupByLibrary.simpleMessage("Ядро"),
    "coreBlockedByPolicyTip": m5,
    "coreBlockedBySmartAppControlTip": MessageLookupByLibrary.simpleMessage(
      "Smart App Control в Windows заблокировал неподписанный FlClashCore.exe. Откройте Безопасность Windows → Управление приложениями и браузером → Параметры Smart App Control, выберите «Выкл.» и снова запустите FlClashX. Повторно включить Smart App Control без переустановки Windows нельзя.",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("Статус ядра"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("Обнаружен сбой"),
    "crashDetectedTip": m6,
    "crashTest": MessageLookupByLibrary.simpleMessage("Тест сбоя"),
    "create": MessageLookupByLibrary.simpleMessage("Создать"),
    "creationTime": MessageLookupByLibrary.simpleMessage("Время создания"),
    "currentOutboundDesc": MessageLookupByLibrary.simpleMessage(
      "Здесь кнопка запуска, эту карточку нельзя убрать",
    ),
    "custom": MessageLookupByLibrary.simpleMessage("Вручную"),
    "customColor": MessageLookupByLibrary.simpleMessage("Свой цвет"),
    "customImportDroppedSubRules": m7,
    "customIssueCoreRejected": m8,
    "customIssueDialerLoop": m9,
    "customIssueDuplicateName": m10,
    "customIssueEmptyName": MessageLookupByLibrary.simpleMessage(
      "Имя не задано",
    ),
    "customIssueGroupLoop": m11,
    "customIssueInvalidEmptyFallback": m12,
    "customIssueInvalidFilter": m13,
    "customIssueMissingDialer": m14,
    "customIssueMissingProviders": m15,
    "customIssueMissingProxies": m16,
    "customIssueNoProxySource": MessageLookupByLibrary.simpleMessage(
      "Не выбраны ни прокси, ни провайдеры прокси, поэтому ядро отклонит эту группу",
    ),
    "customIssueReservedName": m17,
    "customIssuesSummary": m18,
    "customProfile": MessageLookupByLibrary.simpleMessage("Пользовательский"),
    "customProfileResources": MessageLookupByLibrary.simpleMessage(
      "Ресурсы пользовательских профилей",
    ),
    "customProfileResourcesDesc": MessageLookupByLibrary.simpleMessage(
      "Ресурсы пользовательских профилей — это прокси, провайдеры правил, фильтры и наборы значков, которые вы сами добавляете для пользовательских профилей.",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("Вырезать"),
    "dark": MessageLookupByLibrary.simpleMessage("Тёмная"),
    "dashboard": MessageLookupByLibrary.simpleMessage("Панель"),
    "dashboardAddableSection": MessageLookupByLibrary.simpleMessage(
      "Можно добавить",
    ),
    "databaseWriteFailedTip": MessageLookupByLibrary.simpleMessage(
      "Не удалось сохранить изменение, оно отменено",
    ),
    "daysAgo": m19,
    "daysAgoShort": m20,
    "defaultSelected": MessageLookupByLibrary.simpleMessage(
      "Выбор по умолчанию",
    ),
    "defaultText": MessageLookupByLibrary.simpleMessage("По умолчанию"),
    "definitionNotMap": MessageLookupByLibrary.simpleMessage(
      "Конфигурация должна быть YAML-словарём с полями name и type",
    ),
    "delay": MessageLookupByLibrary.simpleMessage("Задержка"),
    "delayFailed": MessageLookupByLibrary.simpleMessage("Сбой"),
    "delayTest": MessageLookupByLibrary.simpleMessage("Тест задержки"),
    "testShort": MessageLookupByLibrary.simpleMessage("Тест"),
    "delayTestAll": MessageLookupByLibrary.simpleMessage(
      "Проверить задержку всех узлов",
    ),
    "delayTestTimeout": MessageLookupByLibrary.simpleMessage(
      "Тайм-аут теста задержки",
    ),
    "delete": MessageLookupByLibrary.simpleMessage("Удалить"),
    "deleteMultipTip": m21,
    "deleteTip": m22,
    "desc": MessageLookupByLibrary.simpleMessage(
      "Бесплатный клиент с открытым исходным кодом, построенный на FLClashX.",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("Назначение"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage(
      "GeoIP назначения",
    ),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage(
      "ASN IP назначения",
    ),
    "details": m23,
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "Использует сторонний API — ipinfo.io",
    ),
    "developerMode": MessageLookupByLibrary.simpleMessage("Режим разработчика"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "Режим разработчика включён.",
    ),
    "deviceIdNotSent": MessageLookupByLibrary.simpleMessage(
      "Подписка требует HWID, но приложение его не отправило. Включите отправку HWID в настройках профиля.",
    ),
    "deviceIdUnsupported": MessageLookupByLibrary.simpleMessage(
      "Подписка требует HWID, но эта платформа не может его предоставить.",
    ),
    "deviceIdUnsupportedTitle": MessageLookupByLibrary.simpleMessage(
      "HWID не поддерживается",
    ),
    "deviceLimitReached": MessageLookupByLibrary.simpleMessage(
      "Достигнут лимит устройств",
    ),
    "dialerProxy": MessageLookupByLibrary.simpleMessage(
      "Прокси для подключения",
    ),
    "dialerProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Прокси для подключения — исходящий прокси, через который идёт обращение к NTP-серверу.",
    ),
    "dialerProxyLoopStopped": m24,
    "direct": MessageLookupByLibrary.simpleMessage("Прямой"),
    "disableIcmpForwarding": MessageLookupByLibrary.simpleMessage(
      "Отключить пересылку ICMP",
    ),
    "disableIcmpForwardingDesc": MessageLookupByLibrary.simpleMessage(
      "При отключённой пересылке ICMP TUN сам отвечает на ping, поэтому ping больше не показывает реальную задержку.",
    ),
    "disableKeepAlive": MessageLookupByLibrary.simpleMessage(
      "Отключить TCP keep-alive",
    ),
    "disableUDP": MessageLookupByLibrary.simpleMessage("Отключить UDP"),
    "disabled": MessageLookupByLibrary.simpleMessage("Выключено"),
    "discardChanges": MessageLookupByLibrary.simpleMessage(
      "Отменить изменения?",
    ),
    "disclaimer": MessageLookupByLibrary.simpleMessage(
      "Отказ от ответственности",
    ),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "Portal — бесплатный клиент с открытым исходным кодом, собранный на базе FlClashX с ядром Prizrak. Ниже коротко о том, что он делает, чего не делает и какие данные собирает. Нажимая «Согласен», вы принимаете эти условия.",
    ),
    "disclaimerLicenseContent": MessageLookupByLibrary.simpleMessage(
      "Исходный код открыт и распространяется по лицензии GPL-3.0. Ядра (prizrak-core, x-ray) и другие сторонние компоненты имеют собственные лицензии. За изменённые или распространяемые третьими лицами сборки авторы не отвечают.",
    ),
    "disclaimerLicenseTitle": MessageLookupByLibrary.simpleMessage("Лицензия"),
    "disclaimerPrivacyContent": MessageLookupByLibrary.simpleMessage(
      "Для поиска ошибок программа собирает технические данные через Google Firebase: отчёты о сбоях, версию программы и системы, модель устройства и обезличенную статистику использования функций.\n\nАдреса подписок, содержимое конфигураций, серверы, посещённые сайты, подключения, трафик и журналы не собираются и никуда не отправляются. Они остаются только на вашем устройстве.",
    ),
    "disclaimerPrivacyTitle": MessageLookupByLibrary.simpleMessage("Данные"),
    "disclaimerResponsibilityContent": MessageLookupByLibrary.simpleMessage(
      "Законность использования программы в вашей стране вы оцениваете сами и сами отвечаете за свои действия с ней.\n\nПрограмма предоставляется «как есть», без каких-либо гарантий. Разработчики не несут ответственности за ущерб от её использования или невозможности использования, а также за сторонние подписки, конфигурации и ссылки.",
    ),
    "disclaimerResponsibilityTitle": MessageLookupByLibrary.simpleMessage(
      "Ответственность",
    ),
    "disclaimerSoftwareContent": MessageLookupByLibrary.simpleMessage(
      "Portal — это приложение, которое заворачивает ваши подключения через сторонние локации (сервера).\n\nСамих локаций (серверов) приложение Portal НЕ СОДЕРЖИТ. Для того, чтобы всё заработало, нужна ПОДПИСКА.\n\nPortal поддерживает разные типы подписок, но сами эти подписки — отдельная услуга, получаемая у нас либо третьих лиц самостоятельно. Вопросы законности, безопасности и качества подписок к ПРИЛОЖЕНИЮ отношения не имеют, а потому решаются по месту приобретения услуги.",
    ),
    "disclaimerSoftwareTitle": MessageLookupByLibrary.simpleMessage(
      "Что это и чего здесь нет",
    ),
    "disconnected": MessageLookupByLibrary.simpleMessage("Отключено"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "Доступна новая версия",
    ),
    "dnsCacheCleared": MessageLookupByLibrary.simpleMessage("Кэш DNS очищен"),
    "dnsHijackDesc": MessageLookupByLibrary.simpleMessage(
      "Без этого параметра TUN перехватывает все DNS-запросы на порт 53 (any:53).",
    ),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("Перехват DNS"),
    "dnsMode": MessageLookupByLibrary.simpleMessage("Режим DNS"),
    "dnsOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "Добавленные здесь параметры заменяют DNS всех профилей из URL и файлов; остальные остаются такими, как в профиле. DNS пользовательского профиля задаётся в его содержимом.",
    ),
    "dnsQueries": MessageLookupByLibrary.simpleMessage("DNS-запросы"),
    "docked": MessageLookupByLibrary.simpleMessage("Закреплённая"),
    "domain": MessageLookupByLibrary.simpleMessage("Домен"),
    "done": MessageLookupByLibrary.simpleMessage("Готово"),
    "download": MessageLookupByLibrary.simpleMessage("Загрузка"),
    "downloadBandwidth": MessageLookupByLibrary.simpleMessage(
      "Скорость загрузки",
    ),
    "downloadTooLarge": MessageLookupByLibrary.simpleMessage(
      "Файл слишком большой для загрузки",
    ),
    "duration": MessageLookupByLibrary.simpleMessage("Длительность"),
    "edit": MessageLookupByLibrary.simpleMessage("Редактировать"),
    "editDashboard": MessageLookupByLibrary.simpleMessage("Изменить панель"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage(
      "Редактировать глобальные правила",
    ),
    "editProxy": MessageLookupByLibrary.simpleMessage("Редактировать прокси"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Редактировать группу прокси",
    ),
    "editRule": MessageLookupByLibrary.simpleMessage("Редактировать правило"),
    "editSsid": MessageLookupByLibrary.simpleMessage("Изменить SSID"),
    "editorUnavailable": MessageLookupByLibrary.simpleMessage(
      "Редактор недоступен",
    ),
    "elapsed": MessageLookupByLibrary.simpleMessage("Заняло"),
    "emptyFallback": MessageLookupByLibrary.simpleMessage(
      "Резерв для пустой группы",
    ),
    "emptyTip": m25,
    "en": MessageLookupByLibrary.simpleMessage("Английский"),
    "enabled": MessageLookupByLibrary.simpleMessage("Включено"),
    "engineFormatStale": MessageLookupByLibrary.simpleMessage(
      "Подписка не обновилась, портал продолжит работать на сохранённых правилах.",
    ),
    "engineFormatUnusable": m26,
    "error": MessageLookupByLibrary.simpleMessage("Ошибка"),
    "errorDetails": MessageLookupByLibrary.simpleMessage("Подробности ошибки"),
    "es": MessageLookupByLibrary.simpleMessage("Испанский"),
    "exclude": MessageLookupByLibrary.simpleMessage("Скрыть из недавних задач"),
    "excludeDstPort": MessageLookupByLibrary.simpleMessage(
      "Исключённые порты назначения",
    ),
    "excludeDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "Трафик на исключённые порты назначения идёт в обход TUN.",
    ),
    "excludeFilter": MessageLookupByLibrary.simpleMessage("Фильтр исключения"),
    "excludeInterface": MessageLookupByLibrary.simpleMessage(
      "Исключённые интерфейсы",
    ),
    "excludeInterfaceDesc": MessageLookupByLibrary.simpleMessage(
      "Трафик с исключённых интерфейсов, например с docker0, идёт в обход TUN.",
    ),
    "excludeSrcPort": MessageLookupByLibrary.simpleMessage(
      "Исключённые исходные порты",
    ),
    "excludeSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "Трафик с исключённых исходных портов идёт в обход TUN.",
    ),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("Исключённые SSID"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "При подключении к Wi-Fi с исключённым SSID состояние работы приложения переключается автоматически.",
    ),
    "excludeUid": MessageLookupByLibrary.simpleMessage(
      "Исключённые ID пользователей",
    ),
    "excludeUidDesc": MessageLookupByLibrary.simpleMessage(
      "Трафик процессов исключённых ID пользователей идёт в обход TUN.",
    ),
    "existsTip": m27,
    "exit": MessageLookupByLibrary.simpleMessage("Выход"),
    "exitFullScreen": MessageLookupByLibrary.simpleMessage(
      "Выйти из полноэкранного режима",
    ),
    "exitNodes": MessageLookupByLibrary.simpleMessage("Выходные узлы"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("Ожидаемый статус"),
    "expireTime": MessageLookupByLibrary.simpleMessage("Срок действия"),
    "expiresLine": m28,
    "expiresUntil": m29,
    "exportFile": MessageLookupByLibrary.simpleMessage("Экспорт файла"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("Экспорт логов"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("Экспорт выполнен"),
    "extend": MessageLookupByLibrary.simpleMessage("Расширение"),
    "extendMode": MessageLookupByLibrary.simpleMessage("Режим расширения"),
    "extendScript": MessageLookupByLibrary.simpleMessage("Скрипт расширения"),
    "externalController": MessageLookupByLibrary.simpleMessage(
      "Внешний контроллер",
    ),
    "externalControllerDesc": m30,
    "externalControllerSecret": MessageLookupByLibrary.simpleMessage(
      "Секрет внешнего контроллера",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("Внешняя ссылка"),
    "extraLarge": MessageLookupByLibrary.simpleMessage("Очень крупный"),
    "fade": MessageLookupByLibrary.simpleMessage("Растворение"),
    "failedCount": m31,
    "failedItem": m32,
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Фильтр Fake-IP"),
    "fakeipFilterMode": MessageLookupByLibrary.simpleMessage(
      "Режим фильтра Fake-IP",
    ),
    "fakeipFilterModeDesc": MessageLookupByLibrary.simpleMessage(
      "blacklist: совпавшие домены не получают Fake-IP; whitelist: Fake-IP получают только они; rule: по правилам.",
    ),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Диапазон Fake-IP"),
    "fakeipRange6": MessageLookupByLibrary.simpleMessage(
      "Диапазон Fake-IP (IPv6)",
    ),
    "fakeipTtl": MessageLookupByLibrary.simpleMessage("TTL Fake-IP"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Фильтр fallback"),
    "file": MessageLookupByLibrary.simpleMessage("Файл"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "Файл изменён. Сохранить изменения?",
    ),
    "filter": MessageLookupByLibrary.simpleMessage("Фильтр"),
    "filterExpiryDate": MessageLookupByLibrary.simpleMessage("Дата окончания"),
    "filterHongKong": MessageLookupByLibrary.simpleMessage("Гонконг"),
    "filterJapan": MessageLookupByLibrary.simpleMessage("Япония"),
    "filterRemainingTraffic": MessageLookupByLibrary.simpleMessage(
      "Остаток трафика",
    ),
    "filterSingapore": MessageLookupByLibrary.simpleMessage("Сингапур"),
    "filterSouthKorea": MessageLookupByLibrary.simpleMessage("Южная Корея"),
    "filterTaiwan": MessageLookupByLibrary.simpleMessage("Тайвань"),
    "filterTrafficReset": MessageLookupByLibrary.simpleMessage("Сброс трафика"),
    "filterUnitedKingdom": MessageLookupByLibrary.simpleMessage(
      "Великобритания",
    ),
    "filterUnitedStates": MessageLookupByLibrary.simpleMessage("США"),
    "filterWebsiteNotices": MessageLookupByLibrary.simpleMessage(
      "Сайты и уведомления",
    ),
    "filters": MessageLookupByLibrary.simpleMessage("Фильтры"),
    "filtersHint": MessageLookupByLibrary.simpleMessage(
      "Перетащите, чтобы изменить порядок. Выключите, чтобы скрыть.",
    ),
    "filtersTitle": MessageLookupByLibrary.simpleMessage("Фильтры"),
    "findProcessAlways": MessageLookupByLibrary.simpleMessage("Всегда"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("Поиск процесса"),
    "findProcessStrict": MessageLookupByLibrary.simpleMessage(
      "Когда нужно правилам",
    ),
    "floating": MessageLookupByLibrary.simpleMessage("Плавающая"),
    "foldAllGroups": MessageLookupByLibrary.simpleMessage(
      "Свернуть все группы",
    ),
    "followProfile": MessageLookupByLibrary.simpleMessage("Как в профиле"),
    "followSystem": MessageLookupByLibrary.simpleMessage("Как в системе"),
    "fontFamily": MessageLookupByLibrary.simpleMessage("Шрифт"),
    "fontSize": MessageLookupByLibrary.simpleMessage("Размер"),
    "forceDnsMapping": MessageLookupByLibrary.simpleMessage(
      "Принудительно для DNS-сопоставлений",
    ),
    "forceDnsMappingDesc": MessageLookupByLibrary.simpleMessage(
      "«Принудительно для DNS-сопоставлений» анализирует и те соединения, домен которых уже известен из DNS.",
    ),
    "forceDomain": MessageLookupByLibrary.simpleMessage(
      "Принудительные домены",
    ),
    "forceDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Принудительные домены тоже анализируются; остальные соединения с доменом не затрагиваются.",
    ),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Принудительно перезапустить ядро?",
    ),
    "forkAuthor": MessageLookupByLibrary.simpleMessage("Автор форка"),
    "fr": MessageLookupByLibrary.simpleMessage("Французский"),
    "general": MessageLookupByLibrary.simpleMessage("Общие"),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geo"),
    "geoSkipped": m33,
    "geoUpdated": m34,
    "geodataLoader": MessageLookupByLibrary.simpleMessage(
      "Geo: экономия памяти",
    ),
    "getSubscriptionHere": MessageLookupByLibrary.simpleMessage(
      "Оформить подписку можно здесь",
    ),
    "global": MessageLookupByLibrary.simpleMessage("Простой портал"),
    "go": MessageLookupByLibrary.simpleMessage("Перейти"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Скачать"),
    "goToConfigureAddedRules": MessageLookupByLibrary.simpleMessage(
      "Перейти к настройке добавленных правил",
    ),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage(
      "Перейти к настройке скрипта",
    ),
    "grid": MessageLookupByLibrary.simpleMessage("Сетка"),
    "groupCount": m35,
    "groupCountUnit": MessageLookupByLibrary.simpleMessage("групп"),
    "groupTimeoutCount": m36,
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Сохранить изменения как черновик?",
    ),
    "hashByInUser": MessageLookupByLibrary.simpleMessage(
      "Хешировать по пользователю входящего подключения",
    ),
    "healthCheck": MessageLookupByLibrary.simpleMessage("Проверка состояния"),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Служба Helper недоступна, поэтому TUN-режим включить нельзя. Переустановите Portal.",
    ),
    "hex": MessageLookupByLibrary.simpleMessage("Hex"),
    "hideFromList": MessageLookupByLibrary.simpleMessage("Скрыть из списка"),
    "hideIp": MessageLookupByLibrary.simpleMessage("Скрыть IP"),
    "hideIpDesc": MessageLookupByLibrary.simpleMessage(
      "Убирает исходящий IP с главной и из проверки сервисов.",
    ),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Скрыть пароль"),
    "hideTimeoutProxies": MessageLookupByLibrary.simpleMessage(
      "Скрывать прокси с таймаутом",
    ),
    "hideTimeoutProxiesDesc": MessageLookupByLibrary.simpleMessage(
      "Не показывать прокси, у которых последний тест задержки завершился таймаутом",
    ),
    "hopInterval": MessageLookupByLibrary.simpleMessage("Интервал перескока"),
    "host": MessageLookupByLibrary.simpleMessage("Хост"),
    "hostname": MessageLookupByLibrary.simpleMessage("Имя хоста"),
    "hotkeyConflictWith": m37,
    "hotkeyDesc": MessageLookupByLibrary.simpleMessage(
      "Глобальные горячие клавиши работают, даже когда окно скрыто. Нажмите на действие, чтобы записать сочетание клавиш.",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("Горячие клавиши"),
    "hotkeyNeedsModifier": m38,
    "hotkeyNotSet": MessageLookupByLibrary.simpleMessage("Не задано"),
    "hotkeyUnavailable": MessageLookupByLibrary.simpleMessage(
      "Не зарегистрировано: сочетание может быть занято другим приложением",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("ч"),
    "hoursAgo": m39,
    "hoursAgoShort": m40,
    "hue": MessageLookupByLibrary.simpleMessage("Оттенок"),
    "icon": MessageLookupByLibrary.simpleMessage("Значок"),
    "iconSets": MessageLookupByLibrary.simpleMessage("Наборы значков"),
    "iconSetsEmptyTip": MessageLookupByLibrary.simpleMessage(
      "Наборов значков пока нет. Добавьте их в разделе «Ресурсы пользовательских профилей → Наборы значков»",
    ),
    "iconStyle": MessageLookupByLibrary.simpleMessage("Стиль значков"),
    "iconStyleFilled": MessageLookupByLibrary.simpleMessage("С подложкой"),
    "iconStyleHidden": MessageLookupByLibrary.simpleMessage("Скрыто"),
    "iconStylePlain": MessageLookupByLibrary.simpleMessage("Без подложки"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("URL значка"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Игнорировать оптимизацию батареи",
    ),
    "import": MessageLookupByLibrary.simpleMessage("Импорт"),
    "importConfigInvalid": MessageLookupByLibrary.simpleMessage(
      "Этот файл не является конфигурацией, которую можно импортировать",
    ),
    "importConfigReplaceTip": MessageLookupByLibrary.simpleMessage(
      "Импорт заменит текущие группы прокси, правила и настройки этого профиля",
    ),
    "importFile": MessageLookupByLibrary.simpleMessage("Импорт из файла"),
    "importFromLink": MessageLookupByLibrary.simpleMessage("Импорт по ссылке"),
    "importUrl": MessageLookupByLibrary.simpleMessage("Импорт по URL"),
    "inPortal": MessageLookupByLibrary.simpleMessage("В портале"),
    "inbound": MessageLookupByLibrary.simpleMessage("Входящие"),
    "includeInterface": MessageLookupByLibrary.simpleMessage(
      "Включённые интерфейсы",
    ),
    "includeInterfaceDesc": MessageLookupByLibrary.simpleMessage(
      "Через TUN идёт только трафик с включённых интерфейсов, а исключённые интерфейсы больше не действуют.",
    ),
    "includeUid": MessageLookupByLibrary.simpleMessage(
      "Включённые ID пользователей",
    ),
    "includeUidDesc": MessageLookupByLibrary.simpleMessage(
      "Через TUN идёт только трафик процессов включённых ID пользователей.",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("Бессрочно"),
    "init": MessageLookupByLibrary.simpleMessage("Инициализация"),
    "initFailed": MessageLookupByLibrary.simpleMessage("Не удалось запустить"),
    "initFailedTip": MessageLookupByLibrary.simpleMessage(
      "При запуске FlClashX произошла ошибка, и работа не может быть продолжена. Скопируйте подробности, чтобы сообщить о проблеме. Если ошибка повторяется, очистка данных обычно позволяет снова запустить приложение.",
    ),
    "initiator": MessageLookupByLibrary.simpleMessage("Инициатор"),
    "initiatorShort": MessageLookupByLibrary.simpleMessage("Откуда"),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage(
      "Введите название группы прокси",
    ),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage(
      "Введите содержимое правила",
    ),
    "insertSubscriptionLink": MessageLookupByLibrary.simpleMessage(
      "Вставьте свою ссылку подписки",
    ),
    "installedAppsPermissionDeniedMessage":
        MessageLookupByLibrary.simpleMessage(
          "Разрешение на список приложений отклонено, поэтому установленные приложения недоступны. Предоставьте его вручную в системных настройках.",
        ),
    "installedAppsPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "Эта система не выдаёт список установленных приложений без разрешения. Предоставьте его, чтобы настроить прокси для отдельных приложений.",
    ),
    "installedAppsPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Требуется разрешение на список приложений",
    ),
    "installedFonts": MessageLookupByLibrary.simpleMessage(
      "Установленные шрифты",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage("Умный выбор"),
    "interfaceName": MessageLookupByLibrary.simpleMessage("Имя интерфейса"),
    "interfaceNameDesc": MessageLookupByLibrary.simpleMessage(
      "Имя интерфейса задаёт сетевой интерфейс для исходящих соединений.",
    ),
    "interfaceNameMode": MessageLookupByLibrary.simpleMessage(
      "Исходящий интерфейс",
    ),
    "interfaceNameModeClear": MessageLookupByLibrary.simpleMessage(
      "Не задавать",
    ),
    "interfaceNameModeCustom": MessageLookupByLibrary.simpleMessage("Вручную"),
    "interfaceNameModeFollow": MessageLookupByLibrary.simpleMessage(
      "Как в конфигурации",
    ),
    "intranetIP": MessageLookupByLibrary.simpleMessage("Внутренний IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage(
      "Недопустимый файл резервной копии",
    ),
    "invalidCidrContent": MessageLookupByLibrary.simpleMessage(
      "Введите диапазон IP в формате CIDR, например 192.168.0.0/16",
    ),
    "invalidDscpContent": MessageLookupByLibrary.simpleMessage(
      "Метка DSCP не может превышать 63",
    ),
    "invalidHostContent": MessageLookupByLibrary.simpleMessage(
      "Введите домен или IP-адрес",
    ),
    "invalidIconSet": MessageLookupByLibrary.simpleMessage(
      "Это не набор значков",
    ),
    "invalidLinkTip": MessageLookupByLibrary.simpleMessage(
      "Это не ссылка на подписку и не ссылка на прокси",
    ),
    "invalidListenContent": MessageLookupByLibrary.simpleMessage(
      "Введите адрес и порт, например 0.0.0.0:1053",
    ),
    "invalidNetworkContent": MessageLookupByLibrary.simpleMessage(
      "Поддерживаются только tcp и udp",
    ),
    "invalidPolicy": m41,
    "invalidPortRangeContent": MessageLookupByLibrary.simpleMessage(
      "Введите порт или диапазон, например 443 или 8000-9000",
    ),
    "invalidProfileQrcode": MessageLookupByLibrary.simpleMessage(
      "Этот QR-код не содержит ссылку на профиль",
    ),
    "invalidProxy": m42,
    "invalidProxyProvider": m43,
    "invalidRangeContent": MessageLookupByLibrary.simpleMessage(
      "Введите числа или диапазоны, например 80 или 8000-9000, через /",
    ),
    "invalidRuleSet": m44,
    "invalidSubRule": m45,
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP-адрес"),
    "ipAsn": MessageLookupByLibrary.simpleMessage("ASN"),
    "ipFlagAbuser": MessageLookupByLibrary.simpleMessage("Злоупотребления"),
    "ipFlagProxy": MessageLookupByLibrary.simpleMessage("Прокси"),
    "ipFlagTor": MessageLookupByLibrary.simpleMessage("Tor"),
    "ipFlagVpn": MessageLookupByLibrary.simpleMessage("VPN"),
    "ipFlags": MessageLookupByLibrary.simpleMessage("Метки"),
    "ipOrganization": MessageLookupByLibrary.simpleMessage("Организация"),
    "ipQualityFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось определить тип IP",
    ),
    "ipQualityGood": MessageLookupByLibrary.simpleMessage("Хороший"),
    "ipQualityLevel": MessageLookupByLibrary.simpleMessage("Уровень"),
    "ipQualityNormal": MessageLookupByLibrary.simpleMessage("Обычный"),
    "ipQualityRetry": MessageLookupByLibrary.simpleMessage("Проверить снова"),
    "ipQualityRisky": MessageLookupByLibrary.simpleMessage("Подозрительный"),
    "ipQualitySources": MessageLookupByLibrary.simpleMessage("Источники"),
    "ipSourceIpMismatch": MessageLookupByLibrary.simpleMessage(
      "Другой исходящий IP",
    ),
    "ipSourceNoType": MessageLookupByLibrary.simpleMessage("Тип не определён"),
    "ipSourceRateLimited": MessageLookupByLibrary.simpleMessage(
      "Лимит запросов",
    ),
    "ipType": MessageLookupByLibrary.simpleMessage("Тип"),
    "ipTypeBusiness": MessageLookupByLibrary.simpleMessage("Бизнес"),
    "ipTypeHosting": MessageLookupByLibrary.simpleMessage("Дата-центр"),
    "ipTypeMobile": MessageLookupByLibrary.simpleMessage("Мобильная сеть"),
    "ipTypeResidential": MessageLookupByLibrary.simpleMessage("Домашний"),
    "ipVersion": MessageLookupByLibrary.simpleMessage("Версия IP"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "IPv6-трафик идёт через прокси, только когда IPv6 включён.",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "При включённом IPv6 VPN принимает входящий IPv6.",
    ),
    "ipv6Timeout": MessageLookupByLibrary.simpleMessage("Тайм-аут IPv6 (мс)"),
    "itemsCount": m46,
    "ja": MessageLookupByLibrary.simpleMessage("Японский"),
    "justNow": MessageLookupByLibrary.simpleMessage("Только что"),
    "keepAliveIdle": MessageLookupByLibrary.simpleMessage(
      "Простой до TCP keep-alive",
    ),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "Интервал TCP keep-alive",
    ),
    "key": MessageLookupByLibrary.simpleMessage("Ключ"),
    "ko": MessageLookupByLibrary.simpleMessage("Корейский"),
    "label": MessageLookupByLibrary.simpleMessage("Метка"),
    "language": MessageLookupByLibrary.simpleMessage("Язык"),
    "large": MessageLookupByLibrary.simpleMessage("Крупный"),
    "lastUpdated": MessageLookupByLibrary.simpleMessage("Последнее обновление"),
    "launchInterrupted": MessageLookupByLibrary.simpleMessage(
      "Запуск не завершён",
    ),
    "launchInterruptedTip": MessageLookupByLibrary.simpleMessage(
      "В прошлый раз приложение неожиданно завершилось во время запуска. Автоматическая настройка для этого запуска пропущена; вы можете запустить её вручную.",
    ),
    "layout": MessageLookupByLibrary.simpleMessage("Макет"),
    "light": MessageLookupByLibrary.simpleMessage("Светлая"),
    "lineIssueTip": m47,
    "lineWrap": MessageLookupByLibrary.simpleMessage("Перенос строк"),
    "link": MessageLookupByLibrary.simpleMessage("Ссылка"),
    "liquidGlass": MessageLookupByLibrary.simpleMessage("Жидкое стекло"),
    "liquidGlassReduced": MessageLookupByLibrary.simpleMessage(
      "Стекло упрощено насовсем: устройство не успевает.",
    ),
    "list": MessageLookupByLibrary.simpleMessage("Список"),
    "listen": MessageLookupByLibrary.simpleMessage("Адрес прослушивания"),
    "listenRoutingMark": MessageLookupByLibrary.simpleMessage(
      "Метка маршрутизации",
    ),
    "listenRoutingMarkDesc": MessageLookupByLibrary.simpleMessage(
      "Метка маршрутизации действует только в Linux.",
    ),
    "liveConnections": MessageLookupByLibrary.simpleMessage(
      "Активные соединения",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Загрузка…"),
    "local": MessageLookupByLibrary.simpleMessage("Локально"),
    "localImage": MessageLookupByLibrary.simpleMessage("Локальное изображение"),
    "localNetworkDeniedTip": MessageLookupByLibrary.simpleMessage(
      "Доступ к локальной сети запрещён: используется стек gvisor, локальная сеть недоступна.",
    ),
    "localProxies": MessageLookupByLibrary.simpleMessage("Локальные прокси"),
    "locationPermission": MessageLookupByLibrary.simpleMessage(
      "Разрешение на геолокацию",
    ),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "Разрешение на геолокацию отклонено, поэтому невозможно получить имя текущей сети Wi-Fi. Включите разрешение на геолокацию вручную в системных настройках.",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "По требованию системы для получения имени сети Wi-Fi необходимо разрешение на геолокацию. На Android выберите «Разрешить всегда», иначе имя сети Wi-Fi нельзя получить, пока приложение в фоне.",
    ),
    "locationPermissionGuide": m48,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Требуется разрешение на геолокацию",
    ),
    "logLevel": MessageLookupByLibrary.simpleMessage("Уровень логов"),
    "logcat": MessageLookupByLibrary.simpleMessage("Захват логов"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage(
      "Если захват логов выключен, раздел логов скрыт.",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("Логи"),
    "logsAndDiagnostics": MessageLookupByLibrary.simpleMessage(
      "Логи и диагностика",
    ),
    "logsTest": MessageLookupByLibrary.simpleMessage("Тест логов"),
    "loopback": MessageLookupByLibrary.simpleMessage(
      "Снятие ограничения loopback для UWP",
    ),
    "loose": MessageLookupByLibrary.simpleMessage("Свободный"),
    "managedByProvider": MessageLookupByLibrary.simpleMessage(
      "Управляет провайдер",
    ),
    "managedByProviderTip": MessageLookupByLibrary.simpleMessage(
      "Это значение приходит из подписки. Если изменить его самому, обновления подписки перестанут его трогать. Вернуть настройку провайдера можно правой кнопкой или долгим нажатием по строке.",
    ),
    "managedByYou": MessageLookupByLibrary.simpleMessage("Управляете вы"),
    "managedSettingsHint": MessageLookupByLibrary.simpleMessage(
      "Приглушённые параметры с закрытым замком задаёт подписка. Нажмите на параметр, чтобы изменить его самому.",
    ),
    "managedSettingsOwnedHint": MessageLookupByLibrary.simpleMessage(
      "Открытым замком отмечены параметры, которые вы забрали себе; вернуть настройку провайдера можно правой кнопкой или долгим нажатием.",
    ),
    "matchCase": MessageLookupByLibrary.simpleMessage("Учитывать регистр"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage(
      "Сопоставлять IP источника",
    ),
    "matchTarget": MessageLookupByLibrary.simpleMessage("MATCH-TARGET"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage(
      "Макс. число ошибок",
    ),
    "maxLengthTip": m49,
    "maximize": MessageLookupByLibrary.simpleMessage("Развернуть"),
    "memoryAppResident": MessageLookupByLibrary.simpleMessage(
      "Резидентная память",
    ),
    "memoryAppShared": MessageLookupByLibrary.simpleMessage(
      "Приложение и общая",
    ),
    "memoryCoreHeapIdle": MessageLookupByLibrary.simpleMessage(
      "Свободная куча",
    ),
    "memoryCoreHeapInuse": MessageLookupByLibrary.simpleMessage(
      "Используемая куча",
    ),
    "memoryCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "Ядро не запущено",
    ),
    "memoryCoreRuntime": MessageLookupByLibrary.simpleMessage(
      "Накладные расходы среды",
    ),
    "memoryCoreStack": MessageLookupByLibrary.simpleMessage("Стеки горутин"),
    "memoryEstimateDesc": MessageLookupByLibrary.simpleMessage(
      "Оценка по резидентной памяти процессов; может отличаться от данных системы.",
    ),
    "memoryEstimateSharedDesc": MessageLookupByLibrary.simpleMessage(
      "Ядро работает в процессе приложения. Его доля оценивается по статистике среды выполнения, остальное относится к приложению и общей памяти.",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("Память"),
    "memoryInfoDesc": MessageLookupByLibrary.simpleMessage(
      "Память приложения и ядра",
    ),
    "memoryReleased": MessageLookupByLibrary.simpleMessage(
      "Память освобождена",
    ),
    "memoryReleasedSize": m50,
    "menuBarMode": MessageLookupByLibrary.simpleMessage(
      "Прикрепить к строке меню",
    ),
    "menuBarModeDesc": MessageLookupByLibrary.simpleMessage(
      "Приложение живёт в строке меню: окно открывается по клику на иконку, значка в Dock нет. Зелёная кнопка окна тоже прикрепляет.",
    ),
    "messageTest": MessageLookupByLibrary.simpleMessage("Тест сообщения"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("Это сообщение."),
    "minimize": MessageLookupByLibrary.simpleMessage("Свернуть"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage(
      "Сворачивать при выходе",
    ),
    "minutes": MessageLookupByLibrary.simpleMessage("мин"),
    "minutesAgo": m51,
    "minutesAgoShort": m52,
    "mixedPort": MessageLookupByLibrary.simpleMessage("Смешанный порт"),
    "mode": MessageLookupByLibrary.simpleMessage("Режим"),
    "monochromeIcon": MessageLookupByLibrary.simpleMessage(
      "Монохромный значок",
    ),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("Монохром"),
    "monthsAgo": m53,
    "monthsAgoShort": m54,
    "more": MessageLookupByLibrary.simpleMessage("Ещё"),
    "name": MessageLookupByLibrary.simpleMessage("Название"),
    "navigationBarStyle": MessageLookupByLibrary.simpleMessage("Нижняя панель"),
    "network": MessageLookupByLibrary.simpleMessage("Сеть"),
    "networkAccessDeniedError": m55,
    "networkBadResponseError": m56,
    "networkCancelledError": MessageLookupByLibrary.simpleMessage(
      "Запрос отменён",
    ),
    "networkConnectionError": MessageLookupByLibrary.simpleMessage(
      "Не удалось подключиться к серверу. Проверьте подключение к сети или настройки прокси",
    ),
    "networkHostLookupError": MessageLookupByLibrary.simpleMessage(
      "Не удалось определить адрес сервера. Проверьте правильность URL и работу DNS",
    ),
    "networkName": MessageLookupByLibrary.simpleMessage("Имя сети"),
    "networkNotFoundError": m57,
    "networkRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "Слишком много запросов (HTTP 429). Подождите немного и повторите попытку",
    ),
    "networkRequestFailed": m58,
    "networkSecret": MessageLookupByLibrary.simpleMessage("Секрет сети"),
    "networkServerError": m59,
    "networkSpeed": MessageLookupByLibrary.simpleMessage("Скорость сети"),
    "networkTakeover": MessageLookupByLibrary.simpleMessage("Перехват трафика"),
    "networkTimeoutError": MessageLookupByLibrary.simpleMessage(
      "Время ожидания запроса истекло. Проверьте сеть или прокси и повторите попытку",
    ),
    "networkTlsError": MessageLookupByLibrary.simpleMessage(
      "Не удалось установить защищённое соединение. Сертификат сервера может быть недействителен, или соединение перехватывается",
    ),
    "networkType": MessageLookupByLibrary.simpleMessage("Тип сети"),
    "newProxyChain": MessageLookupByLibrary.simpleMessage("Новая цепочка"),
    "nextMatch": MessageLookupByLibrary.simpleMessage("Следующее совпадение"),
    "no": MessageLookupByLibrary.simpleMessage("Нет"),
    "noData": MessageLookupByLibrary.simpleMessage("Нет данных"),
    "noInfo": MessageLookupByLibrary.simpleMessage("Нет информации"),
    "noLogsToday": MessageLookupByLibrary.simpleMessage("За сегодня логов нет"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("Нет сети"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("Приложения без сети"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage(
      "Не резолвить имя хоста",
    ),
    "noSearchResults": MessageLookupByLibrary.simpleMessage(
      "Ничего не найдено",
    ),
    "nodes": MessageLookupByLibrary.simpleMessage("Узлы"),
    "nonTextProviderFile": MessageLookupByLibrary.simpleMessage(
      "Этот внешний ресурс не является текстовым файлом",
    ),
    "none": MessageLookupByLibrary.simpleMessage("Нет"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "В этой группе порталов нельзя выбрать вручную",
    ),
    "ntpInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал синхронизации (минуты)",
    ),
    "ntpStatusDesc": MessageLookupByLibrary.simpleMessage(
      "NTP берёт время с NTP-сервера, а не из системных часов.",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Добавьте подписку, чтобы начать",
    ),
    "nullTip": m60,
    "numberRangeTip": m61,
    "numberTip": m62,
    "obfs": MessageLookupByLibrary.simpleMessage("Обфускация"),
    "obfsHost": MessageLookupByLibrary.simpleMessage("Хост обфускации"),
    "obfsMode": MessageLookupByLibrary.simpleMessage("Режим обфускации"),
    "obfsParam": MessageLookupByLibrary.simpleMessage("Параметр обфускации"),
    "obfsPassword": MessageLookupByLibrary.simpleMessage("Пароль обфускации"),
    "onDemand": MessageLookupByLibrary.simpleMessage("По условию"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "«По условию» приостанавливает прокси в исключённых сетях Wi-Fi.",
    ),
    "oneline": MessageLookupByLibrary.simpleMessage("Однострочный"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "Учитывать только трафик прокси",
    ),
    "openLogsFolder": MessageLookupByLibrary.simpleMessage(
      "Открыть папку с логами",
    ),
    "openPortal": MessageLookupByLibrary.simpleMessage("Открыть портал"),
    "openVpnSettings": MessageLookupByLibrary.simpleMessage(
      "Открыть настройки VPN",
    ),
    "optional": MessageLookupByLibrary.simpleMessage("Необязательно"),
    "options": MessageLookupByLibrary.simpleMessage("Опции"),
    "originalRepository": MessageLookupByLibrary.simpleMessage(
      "Оригинальный репозиторий",
    ),
    "other": MessageLookupByLibrary.simpleMessage("Другое"),
    "outbound": MessageLookupByLibrary.simpleMessage("Исходящие"),
    "outboundExit": MessageLookupByLibrary.simpleMessage("Выход"),
    "outboundIp": MessageLookupByLibrary.simpleMessage("Исходящий IP"),
    "outboundMode": MessageLookupByLibrary.simpleMessage(
      "Режим исходящего трафика",
    ),
    "overrideDestination": MessageLookupByLibrary.simpleMessage(
      "Подменять адрес назначения",
    ),
    "overrideDestinationDesc": MessageLookupByLibrary.simpleMessage(
      "«Подменять адрес назначения» подключается к обнаруженному домену вместо исходного адреса.",
    ),
    "overrideEntries": MessageLookupByLibrary.simpleMessage(
      "Переопределяемые параметры",
    ),
    "parsePureIp": MessageLookupByLibrary.simpleMessage(
      "Анализировать соединения по IP",
    ),
    "parsePureIpDesc": MessageLookupByLibrary.simpleMessage(
      "«Анализировать соединения по IP» разбирает соединения, у которых известен только IP-адрес.",
    ),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "paste": MessageLookupByLibrary.simpleMessage("Вставить"),
    "peers": MessageLookupByLibrary.simpleMessage("Пиры"),
    "pickFromAlbum": MessageLookupByLibrary.simpleMessage("Выбрать из галереи"),
    "pinWindow": MessageLookupByLibrary.simpleMessage(
      "Закрепить поверх всех окон",
    ),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "Привяжите WebDAV",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "Введите название скрипта",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "Загрузите корректный QR-код",
    ),
    "plugin": MessageLookupByLibrary.simpleMessage("Плагин"),
    "pluginCipher": MessageLookupByLibrary.simpleMessage("Шифр плагина"),
    "pluginHost": MessageLookupByLibrary.simpleMessage("Хост плагина"),
    "pluginMode": MessageLookupByLibrary.simpleMessage("Режим плагина"),
    "pluginPassword": MessageLookupByLibrary.simpleMessage("Пароль плагина"),
    "pluginPath": MessageLookupByLibrary.simpleMessage("Путь плагина"),
    "pluginUsername": MessageLookupByLibrary.simpleMessage(
      "Имя пользователя плагина",
    ),
    "port": MessageLookupByLibrary.simpleMessage("Порт"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage(
      "Введите другой порт",
    ),
    "portHopping": MessageLookupByLibrary.simpleMessage("Перескок портов"),
    "portTip": m63,
    "portValue": m64,
    "portalBypassFilter": MessageLookupByLibrary.simpleMessage(
      "Напрямую, мимо портала",
    ),
    "portalModeUnavailable": m65,
    "portalModesUnavailable": m66,
    "portalNoNodes": MessageLookupByLibrary.simpleMessage(
      "эта подписка не содержит серверов для простого портала",
    ),
    "portalNoRules": MessageLookupByLibrary.simpleMessage(
      "эта подписка не содержит правил для сети порталов",
    ),
    "portalOff": MessageLookupByLibrary.simpleMessage("Портал погашен"),
    "portalRestoreFilter": MessageLookupByLibrary.simpleMessage(
      "Вернуть в портал",
    ),
    "portalStartFailed": m67,
    "portalStrikes": m68,
    "portalSwitchFailed": m69,
    "ports": MessageLookupByLibrary.simpleMessage("Порты"),
    "preChannelTip": MessageLookupByLibrary.simpleMessage(
      "Это предварительная версия, она стоит отдельным приложением и не видит профили FlClashX. Чтобы перенести их, сделайте резервную копию в FlClashX в разделе «Резервное копирование и восстановление» и восстановите её здесь, или добавьте подписки заново по ссылке.",
    ),
    "preChannelTipTitle": MessageLookupByLibrary.simpleMessage("FlClashX Pre"),
    "preSharedKey": MessageLookupByLibrary.simpleMessage("Общий ключ"),
    "preferred": MessageLookupByLibrary.simpleMessage("Предпочтительный"),
    "prerequisites": MessageLookupByLibrary.simpleMessage(
      "Предварительные условия",
    ),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage(
      "Нажмите сочетание клавиш",
    ),
    "preview": MessageLookupByLibrary.simpleMessage("Предпросмотр"),
    "previousMatch": MessageLookupByLibrary.simpleMessage(
      "Предыдущее совпадение",
    ),
    "privateKey": MessageLookupByLibrary.simpleMessage("Закрытый ключ"),
    "privateKeyPassphrase": MessageLookupByLibrary.simpleMessage(
      "Пароль закрытого ключа",
    ),
    "process": MessageLookupByLibrary.simpleMessage("Процесс"),
    "profile": MessageLookupByLibrary.simpleMessage("Подписка"),
    "profileAddedTip": m70,
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage("Введите корректный интервал"),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("Введите интервал автообновления"),
    "profileDaysFigure": m71,
    "profileDetails": MessageLookupByLibrary.simpleMessage("Подробнее"),
    "profileExpired": MessageLookupByLibrary.simpleMessage("Истекла"),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "Подписка изменена. Отключить автообновление?",
    ),
    "profileHoursFigure": m72,
    "profileLeftOfTotal": m73,
    "profileMinutesFigure": m74,
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Введите название подписки",
    ),
    "profileNoExpiry": MessageLookupByLibrary.simpleMessage("Бессрочно"),
    "profileSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "Действует только для этого профиля; не добавленные параметры используют значения по умолчанию.",
    ),
    "profileTrafficUnlimited": MessageLookupByLibrary.simpleMessage("Безлимит"),
    "profileTunSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "Действует только для этого профиля и имеет приоритет над переопределяемыми параметрами TUN в настройках сети.",
    ),
    "profileTypeCustom": MessageLookupByLibrary.simpleMessage("Свой"),
    "profileTypeFile": MessageLookupByLibrary.simpleMessage("Файл"),
    "profileTypeSubscription": MessageLookupByLibrary.simpleMessage("Подписка"),
    "profileUntil": m75,
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Введите корректный URL подписки",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Введите URL подписки",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("Подписки"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("Сортировка профилей"),
    "project": MessageLookupByLibrary.simpleMessage("Проект"),
    "protocol": MessageLookupByLibrary.simpleMessage("Протокол"),
    "protocolParam": MessageLookupByLibrary.simpleMessage("Параметр протокола"),
    "protocolVersion": MessageLookupByLibrary.simpleMessage("Версия протокола"),
    "providerInUse": m76,
    "providerReplacedTip": MessageLookupByLibrary.simpleMessage(
      "Этот провайдер был заменён, пока вы его редактировали. Откройте его снова, чтобы изменить текущий.",
    ),
    "providerUrlTip": MessageLookupByLibrary.simpleMessage(
      "Поддерживаются только удалённые ресурсы",
    ),
    "providers": MessageLookupByLibrary.simpleMessage("Внешние ресурсы"),
    "proxies": MessageLookupByLibrary.simpleMessage("Порталы"),
    "proxiesCount": m77,
    "proxiesProfileLabel": m78,
    "proxiesRemovedTip": m79,
    "proxiesReplacedTip": m80,
    "proxyChain": MessageLookupByLibrary.simpleMessage("Цепочка"),
    "proxyChainDevice": MessageLookupByLibrary.simpleMessage("Устройство"),
    "proxyChainEntry": MessageLookupByLibrary.simpleMessage("Вход"),
    "proxyChainExit": MessageLookupByLibrary.simpleMessage("Выход"),
    "proxyChainHopsDesc": MessageLookupByLibrary.simpleMessage(
      "Устройство подключается ко входу, а в интернет трафик выходит через выход.",
    ),
    "proxyChainIncomplete": MessageLookupByLibrary.simpleMessage(
      "Укажите имя и выберите все звенья",
    ),
    "proxyChainInternet": MessageLookupByLibrary.simpleMessage("Интернет"),
    "proxyChainIsMatchTarget": m81,
    "proxyChainIsRuleTarget": m82,
    "proxyChainMiddle": MessageLookupByLibrary.simpleMessage("Середина"),
    "proxyChainMissingHop": m83,
    "proxyChainNameTaken": m84,
    "proxyChainProviderHop": m85,
    "proxyChainRepeatedHop": MessageLookupByLibrary.simpleMessage(
      "Одно звено выбрано дважды",
    ),
    "proxyChainUnchainableHop": m86,
    "proxyChainUnreadableFilter": m87,
    "proxyChains": MessageLookupByLibrary.simpleMessage("Цепочка прокси"),
    "proxyChainsDesc": MessageLookupByLibrary.simpleMessage(
      "Трафик проходит звенья по порядку, сайты видят только выход. Цепочки хранятся на этом устройстве и пока не попадают в резервную копию.",
    ),
    "proxyChainsTitle": MessageLookupByLibrary.simpleMessage("Цепочки"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("Группа прокси"),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage(
      "Группа прокси пуста",
    ),
    "proxyGroupInUse": m88,
    "proxyGroupsAfterStart": MessageLookupByLibrary.simpleMessage(
      "Группы появятся здесь после запуска ядра",
    ),
    "proxyGroupsCount": m89,
    "proxyProviders": MessageLookupByLibrary.simpleMessage("Провайдеры прокси"),
    "proxyType": MessageLookupByLibrary.simpleMessage("Тип прокси"),
    "pruneCache": MessageLookupByLibrary.simpleMessage("Очистить кэш"),
    "publicKey": MessageLookupByLibrary.simpleMessage("Открытый ключ"),
    "pureBlack": MessageLookupByLibrary.simpleMessage("Чисто чёрный"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("Чисто чёрный режим"),
    "qrcode": MessageLookupByLibrary.simpleMessage("QR-код"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "Сканируйте QR-код, чтобы получить подписку",
    ),
    "qrcodeTooLongTip": MessageLookupByLibrary.simpleMessage(
      "Ссылка слишком длинная для QR-кода. Используйте «Копировать ссылку».",
    ),
    "quickActions": MessageLookupByLibrary.simpleMessage("Быстрые действия"),
    "quickEdit": MessageLookupByLibrary.simpleMessage("Быстрое редактирование"),
    "recentRequests": MessageLookupByLibrary.simpleMessage("Последние запросы"),
    "recommendedIcons": MessageLookupByLibrary.simpleMessage("Рекомендуемые"),
    "recordType": MessageLookupByLibrary.simpleMessage("Тип записи"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Порт Redir"),
    "redo": MessageLookupByLibrary.simpleMessage("Повторить"),
    "regex": MessageLookupByLibrary.simpleMessage("Регулярное выражение"),
    "releaseMemory": MessageLookupByLibrary.simpleMessage("Освободить память"),
    "releaseMemoryFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось освободить память",
    ),
    "remote": MessageLookupByLibrary.simpleMessage("Удалённо"),
    "remoteDestination": MessageLookupByLibrary.simpleMessage(
      "Удалённое назначение",
    ),
    "remoteDnsResolve": MessageLookupByLibrary.simpleMessage(
      "Удалённое разрешение DNS",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Убрать"),
    "rename": MessageLookupByLibrary.simpleMessage("Переименовать"),
    "renew": MessageLookupByLibrary.simpleMessage("Продлить"),
    "replace": MessageLookupByLibrary.simpleMessage("Заменить"),
    "replaceAll": MessageLookupByLibrary.simpleMessage("Заменить все"),
    "request": MessageLookupByLibrary.simpleMessage("Запрос"),
    "requestHeaders": MessageLookupByLibrary.simpleMessage("Заголовки запроса"),
    "requests": MessageLookupByLibrary.simpleMessage("Запросы"),
    "requestsAndUpdates": MessageLookupByLibrary.simpleMessage(
      "Запросы и обновления",
    ),
    "required": MessageLookupByLibrary.simpleMessage("Обязательно"),
    "reset": MessageLookupByLibrary.simpleMessage("Сброс"),
    "resetApp": MessageLookupByLibrary.simpleMessage("Сброс приложения"),
    "resetAppTip": MessageLookupByLibrary.simpleMessage(
      "Будут удалены все подписки, настройки и рабочая папка приложения, после чего приложение закроется. Продолжить?",
    ),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "На этой странице есть изменения. Сбросить их?",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage("Выполнить сброс?"),
    "resourceUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления",
    ),
    "resourceUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления должен быть больше 0",
    ),
    "resources": MessageLookupByLibrary.simpleMessage("Ресурсы"),
    "respectRules": MessageLookupByLibrary.simpleMessage("Соблюдать правила"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "«Соблюдать правила» направляет DNS-соединения по правилам; нужен Proxy Server Nameserver.",
    ),
    "responseCode": MessageLookupByLibrary.simpleMessage("Код ответа"),
    "restart": MessageLookupByLibrary.simpleMessage("Перезапустить"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Перезапустить ядро?",
    ),
    "restore": MessageLookupByLibrary.simpleMessage("Восстановить"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage(
      "Восстановить все данные",
    ),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage(
      "Восстановить только профили",
    ),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage(
      "Стратегия восстановления",
    ),
    "restoreStrategyCompatible": MessageLookupByLibrary.simpleMessage(
      "Совместимость",
    ),
    "restoreStrategyOverride": MessageLookupByLibrary.simpleMessage(
      "Перезапись",
    ),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage(
      "Восстановление выполнено",
    ),
    "result": MessageLookupByLibrary.simpleMessage("Результат"),
    "retry": MessageLookupByLibrary.simpleMessage("Повторить"),
    "returnAllToProvider": MessageLookupByLibrary.simpleMessage(
      "Вернуть настройки провайдера",
    ),
    "returnAllToProviderTip": MessageLookupByLibrary.simpleMessage(
      "Все параметры, которые вы меняли сами, снова будут браться из подписки.",
    ),
    "returnToProvider": MessageLookupByLibrary.simpleMessage(
      "Вернуть настройку провайдера",
    ),
    "routeAddress": MessageLookupByLibrary.simpleMessage("Адреса маршрутов"),
    "routeExcludeAddress": MessageLookupByLibrary.simpleMessage(
      "Исключённые адреса маршрутов",
    ),
    "routingMark": MessageLookupByLibrary.simpleMessage("Метка маршрутизации"),
    "ru": MessageLookupByLibrary.simpleMessage("Русский"),
    "rule": MessageLookupByLibrary.simpleMessage("Правило"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило AND",
    ),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить полный домен",
    ),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ключевое слово в домене",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по регулярному выражению домена",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить суффикс домена",
    ),
    "ruleActionDomainWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставление по маске; поддерживаются только * и ?",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить метку DSCP (только для входящих tproxy UDP)",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон портов назначения",
    ),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить код страны IP-адреса",
    ),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить домены из Geosite",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить имя входящего подключения",
    ),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить входящий порт",
    ),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить тип входящего подключения",
    ),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить имя пользователя входящего подключения; несколько имён разделяются /",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ASN, которой принадлежит IP",
    ),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон IP-адресов; IP-CIDR6 — просто псевдоним",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон IP-адресов",
    ),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон суффиксов IP",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставляет все запросы, условия не нужны",
    ),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить TCP или UDP",
    ),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило NOT",
    ),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило OR",
    ),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по имени процесса; на Android соответствует имени пакета",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по регулярному выражению имени процесса; на Android соответствует имени пакета",
    ),
    "ruleActionProcessNameWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по маске имени процесса; поддерживаются только * и ?",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по полному пути процесса",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по регулярному выражению пути процесса",
    ),
    "ruleActionProcessPathWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по маске пути процесса; поддерживаются только * и ?",
    ),
    "ruleActionRematchNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить имя повторного сопоставления; несколько имён разделяются /",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "Ссылка на набор правил; требуется настроить rule-providers",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить код страны IP источника",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ASN IP источника",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон IP-адресов источника",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон суффиксов IP источника",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон портов источника",
    ),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "Переход к подправилу; обратите внимание на скобки",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить Linux USER ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("Правило пусто"),
    "ruleListInvalid": MessageLookupByLibrary.simpleMessage(
      "Правила должны быть YAML-списком, по одному правилу в элементе, например - DOMAIN,example.com,DIRECT",
    ),
    "rulePresetBittorrentDirect": MessageLookupByLibrary.simpleMessage(
      "BitTorrent напрямую",
    ),
    "rulePresetBlockDot": MessageLookupByLibrary.simpleMessage(
      "Блокировать DNS over TLS",
    ),
    "rulePresetBlockLoopback": MessageLookupByLibrary.simpleMessage(
      "Защита от петли прокси",
    ),
    "rulePresetBlockQuic": MessageLookupByLibrary.simpleMessage(
      "Блокировать QUIC",
    ),
    "rulePresetBlockStun": MessageLookupByLibrary.simpleMessage(
      "Блокировать STUN",
    ),
    "rulePresetLanDirect": MessageLookupByLibrary.simpleMessage(
      "Локальная сеть напрямую",
    ),
    "rulePresetSystemServicesDirect": MessageLookupByLibrary.simpleMessage(
      "Apple и Microsoft напрямую",
    ),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("Провайдеры правил"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("Набор правил"),
    "ruleSetEmptyTip": MessageLookupByLibrary.simpleMessage(
      "В наборе правил нет пригодных записей",
    ),
    "ruleSetInvalidTip": MessageLookupByLibrary.simpleMessage(
      "Не удаётся прочитать этот файл mrs",
    ),
    "ruleSetMixedTip": MessageLookupByLibrary.simpleMessage(
      "Набор правил смешивает домены и диапазоны IP, поэтому его тип не определить",
    ),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("Цель правила"),
    "ruleTextInvalid": MessageLookupByLibrary.simpleMessage(
      "Правило должно начинаться с поддерживаемого типа, например DOMAIN,example.com,DIRECT",
    ),
    "rules": MessageLookupByLibrary.simpleMessage("Сеть порталов"),
    "rulesCount": m90,
    "runtimeConfig": MessageLookupByLibrary.simpleMessage(
      "Рабочая конфигурация",
    ),
    "safeModeAppTitle": m91,
    "saturation": MessageLookupByLibrary.simpleMessage("Насыщенность"),
    "save": MessageLookupByLibrary.simpleMessage("Сохранить"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("Сохранить изменения?"),
    "script": MessageLookupByLibrary.simpleMessage("Скрипт"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "Режим скрипта: переписывает весь профиль скриптом расширения",
    ),
    "scrollToSelected": MessageLookupByLibrary.simpleMessage(
      "Прокрутить к выбранному",
    ),
    "search": MessageLookupByLibrary.simpleMessage("Поиск"),
    "seconds": MessageLookupByLibrary.simpleMessage("с"),
    "secondsCount": m92,
    "secretKey": MessageLookupByLibrary.simpleMessage("Ключ"),
    "sectionsInEffect": m93,
    "select": MessageLookupByLibrary.simpleMessage("Выбрать"),
    "selectAll": MessageLookupByLibrary.simpleMessage("Выбрать всё"),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage(
      "Выберите набор правил",
    ),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage(
      "Выберите стратегию распределения",
    ),
    "send": MessageLookupByLibrary.simpleMessage("Отправить"),
    "sendDeviceHeaders": MessageLookupByLibrary.simpleMessage(
      "Отправлять HWID",
    ),
    "sendFromPhone": MessageLookupByLibrary.simpleMessage(
      "Отправить с телефона",
    ),
    "sendFromPhoneConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "Импортировать ссылку с телефона?",
    ),
    "sendFromPhoneNoNetwork": MessageLookupByLibrary.simpleMessage(
      "Это устройство не подключено к локальной сети",
    ),
    "sendFromPhonePageHint": MessageLookupByLibrary.simpleMessage(
      "Ссылка на подписку или ссылка на портал",
    ),
    "sendFromPhonePageSent": MessageLookupByLibrary.simpleMessage(
      "Отправлено. Подтвердите импорт на другом устройстве.",
    ),
    "sendFromPhonePageTitle": MessageLookupByLibrary.simpleMessage(
      "Отправить ссылку в FlClashX",
    ),
    "sendFromPhonePermissionDenied": MessageLookupByLibrary.simpleMessage(
      "Чтобы получить ссылку с телефона, FlClashX нужно разрешение «Устройства поблизости» для доступа к локальной сети. Включите его в настройках приложения.",
    ),
    "sendFromPhoneTip": MessageLookupByLibrary.simpleMessage(
      "Отсканируйте код камерой телефона и вставьте ссылку на открывшейся странице. Оба устройства должны быть в одной сети. Если страница не открывается на Android 17 и новее, дайте браузеру на телефоне разрешение «Устройства поблизости».",
    ),
    "server": MessageLookupByLibrary.simpleMessage("Портал"),
    "serviceAbnormalCount": m94,
    "serviceAllAvailable": MessageLookupByLibrary.simpleMessage("Все доступны"),
    "serviceAvailable": MessageLookupByLibrary.simpleMessage("Доступен"),
    "serviceBlocked": MessageLookupByLibrary.simpleMessage("Заблокировано"),
    "serviceCheckAll": MessageLookupByLibrary.simpleMessage("Проверить все"),
    "serviceComingSoon": MessageLookupByLibrary.simpleMessage("Скоро появится"),
    "serviceDisallowedIsp": MessageLookupByLibrary.simpleMessage(
      "Провайдер не допускается",
    ),
    "serviceFailed": MessageLookupByLibrary.simpleMessage("Ошибка проверки"),
    "serviceManage": MessageLookupByLibrary.simpleMessage(
      "Управление сервисами",
    ),
    "serviceOriginalsOnly": MessageLookupByLibrary.simpleMessage(
      "Только оригиналы",
    ),
    "servicePending": MessageLookupByLibrary.simpleMessage("Не проверено"),
    "serviceRestricted": MessageLookupByLibrary.simpleMessage(
      "Доступ ограничен",
    ),
    "serviceShownOnDashboard": MessageLookupByLibrary.simpleMessage(
      "Показан на панели",
    ),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("Состояние сервисов"),
    "serviceUnavailable": MessageLookupByLibrary.simpleMessage("Недоступен"),
    "serviceUnsupportedRegion": MessageLookupByLibrary.simpleMessage(
      "Регион не поддерживается",
    ),
    "settingEntries": MessageLookupByLibrary.simpleMessage("параметры"),
    "settings": MessageLookupByLibrary.simpleMessage("Настройки"),
    "settingsCount": m95,
    "shareLinkUnreadable": m96,
    "shareLinksInvalid": MessageLookupByLibrary.simpleMessage(
      "Не удалось прочитать прокси из ссылок",
    ),
    "shareLogs": MessageLookupByLibrary.simpleMessage("Поделиться логами"),
    "shareQrcodeTip": MessageLookupByLibrary.simpleMessage(
      "Отсканируйте в FlClashX на другом устройстве, чтобы импортировать этот профиль.",
    ),
    "show": MessageLookupByLibrary.simpleMessage("Показать"),
    "showLess": MessageLookupByLibrary.simpleMessage("Свернуть"),
    "showMore": MessageLookupByLibrary.simpleMessage("Развернуть"),
    "showNotificationStopAction": MessageLookupByLibrary.simpleMessage(
      "Кнопка остановки в уведомлении",
    ),
    "showPassword": MessageLookupByLibrary.simpleMessage("Показать пароль"),
    "sidebarBlurDesc": MessageLookupByLibrary.simpleMessage(
      "Размытие фона показывает рабочий стол за окном сквозь боковую панель.",
    ),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("Тихий запуск"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "При тихом запуске окно не показывается.",
    ),
    "singleAdd": MessageLookupByLibrary.simpleMessage("По одному"),
    "singleImport": MessageLookupByLibrary.simpleMessage("По одному"),
    "singleShareLinkOnly": MessageLookupByLibrary.simpleMessage(
      "Здесь укажите одну ссылку, несколько можно задать в быстром редактировании списка",
    ),
    "singleValueTip": m97,
    "site": MessageLookupByLibrary.simpleMessage("Сайт"),
    "size": MessageLookupByLibrary.simpleMessage("Размер"),
    "skipCertVerify": MessageLookupByLibrary.simpleMessage(
      "Пропускать проверку сертификата",
    ),
    "skipDomain": MessageLookupByLibrary.simpleMessage("Пропускаемые домены"),
    "skipDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Обнаруженный домен из пропускаемых доменов не используется.",
    ),
    "skipDstAddress": MessageLookupByLibrary.simpleMessage(
      "Пропускаемые адреса назначения",
    ),
    "skipSrcAddress": MessageLookupByLibrary.simpleMessage(
      "Пропускаемые адреса источника",
    ),
    "slide": MessageLookupByLibrary.simpleMessage("Сдвиг"),
    "sliders": MessageLookupByLibrary.simpleMessage("Ползунки"),
    "sniffProtocols": MessageLookupByLibrary.simpleMessage("Протоколы"),
    "sniffer": MessageLookupByLibrary.simpleMessage("Сниффер"),
    "snifferStatusDesc": MessageLookupByLibrary.simpleMessage(
      "Сниффер определяет домен по трафику TLS, HTTP и QUIC, чтобы правила могли его сопоставить.",
    ),
    "socksPort": MessageLookupByLibrary.simpleMessage("Порт SOCKS"),
    "softStyle": MessageLookupByLibrary.simpleMessage("Мягкий"),
    "sort": MessageLookupByLibrary.simpleMessage("Сортировка"),
    "sortAsSubscription": MessageLookupByLibrary.simpleMessage(
      "Как в подписке",
    ),
    "sortByName": MessageLookupByLibrary.simpleMessage("По имени"),
    "sortByPing": MessageLookupByLibrary.simpleMessage("По пингу"),
    "sortTooltip": m98,
    "source": MessageLookupByLibrary.simpleMessage("Источник"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("Специальный прокси"),
    "specialRules": MessageLookupByLibrary.simpleMessage("Специальные правила"),
    "spectrum": MessageLookupByLibrary.simpleMessage("Спектр"),
    "speedKilobytes": m99,
    "speedStatistics": MessageLookupByLibrary.simpleMessage(
      "Статистика скорости",
    ),
    "splitStrategy": MessageLookupByLibrary.simpleMessage(
      "Стратегия распределения",
    ),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Стратегия распределения не может быть пустой",
    ),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("Список SSID пуст"),
    "stableImportRetry": MessageLookupByLibrary.simpleMessage("Повторить"),
    "stableImportSkip": MessageLookupByLibrary.simpleMessage(
      "Продолжить без них",
    ),
    "stableImportTip": MessageLookupByLibrary.simpleMessage(
      "FlClashX Pre пока не смог забрать профили и настройки FlClashX. Если FlClashX запущен, закройте его и повторите.",
    ),
    "stableImportTitle": MessageLookupByLibrary.simpleMessage(
      "Перенос профилей FlClashX",
    ),
    "stackMode": MessageLookupByLibrary.simpleMessage("Стек TUN"),
    "stackTrace": MessageLookupByLibrary.simpleMessage("Трассировка стека"),
    "standard": MessageLookupByLibrary.simpleMessage("Стандартный"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "Стандартный режим: добавляет правила поверх профиля",
    ),
    "start": MessageLookupByLibrary.simpleMessage("Старт"),
    "startFromScratch": MessageLookupByLibrary.simpleMessage("С нуля"),
    "startVpn": MessageLookupByLibrary.simpleMessage("Запуск VPN…"),
    "startVpnNetwork": MessageLookupByLibrary.simpleMessage("VPN запускается с раздельными туннелями"),
    "startVpnSimple": MessageLookupByLibrary.simpleMessage("VPN запускается в простом режиме"),
    "startupAndBackground": MessageLookupByLibrary.simpleMessage(
      "Запуск и фоновая работа",
    ),
    "status": MessageLookupByLibrary.simpleMessage("Статус"),
    "statusDesc": MessageLookupByLibrary.simpleMessage(
      "При отключённом DNS используется системный DNS.",
    ),
    "stop": MessageLookupByLibrary.simpleMessage("Стоп"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("Остановка VPN…"),
    "strategy": MessageLookupByLibrary.simpleMessage("Стратегия"),
    "strictRoute": MessageLookupByLibrary.simpleMessage(
      "Строгая маршрутизация",
    ),
    "strictRouteDesc": MessageLookupByLibrary.simpleMessage(
      "Строгая маршрутизация не даёт трафику вроде DNS обходить TUN, а при выключенном IPv6 блокирует IPv6-соединения этого устройства.",
    ),
    "style": MessageLookupByLibrary.simpleMessage("Стиль"),
    "submit": MessageLookupByLibrary.simpleMessage("Применить"),
    "subscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "Ваша подписка истекла",
    ),
    "subscriptionExpiresInDays": m100,
    "subscriptionExpiresSoon": MessageLookupByLibrary.simpleMessage(
      "Подписка скоро истекает",
    ),
    "subscriptionExpiresToday": MessageLookupByLibrary.simpleMessage(
      "Ваша подписка истекает сегодня",
    ),
    "subscriptionInfo": MessageLookupByLibrary.simpleMessage(
      "Информация о подписке",
    ),
    "subscriptionMihomoAbsent": MessageLookupByLibrary.simpleMessage(
      "Mihomo / призрак: формат не отдаётся",
    ),
    "subscriptionMihomoPresent": MessageLookupByLibrary.simpleMessage(
      "Mihomo / призрак: формат есть",
    ),
    "subscriptionXrayAbsent": MessageLookupByLibrary.simpleMessage(
      "Xray: формат не отдаётся",
    ),
    "subscriptionXrayPresent": MessageLookupByLibrary.simpleMessage(
      "Xray: формат есть",
    ),
    "sudoPasswordTitle": MessageLookupByLibrary.simpleMessage(
      "Введите пароль для sudo",
    ),
    "support": MessageLookupByLibrary.simpleMessage("Поддержка"),
    "suspended": MessageLookupByLibrary.simpleMessage("Приостановлено…"),
    "switchProfile": MessageLookupByLibrary.simpleMessage("Сменить профиль"),
    "sync": MessageLookupByLibrary.simpleMessage("Обновить"),
    "system": MessageLookupByLibrary.simpleMessage("Система"),
    "systemApp": MessageLookupByLibrary.simpleMessage("Системные приложения"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("Системный прокси"),
    "tab": MessageLookupByLibrary.simpleMessage("Вкладки"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("Анимация вкладок"),
    "takeOver": MessageLookupByLibrary.simpleMessage("Изменить"),
    "tapIconToRetry": MessageLookupByLibrary.simpleMessage(
      "Нажмите на значок, чтобы повторить",
    ),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage(
      "Нажмите, чтобы разрешить",
    ),
    "target": MessageLookupByLibrary.simpleMessage("Цель"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage(
      "Параллельные TCP-подключения",
    ),
    "testInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал тестирования",
    ),
    "testUrl": MessageLookupByLibrary.simpleMessage("URL для теста"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage(
      "Тестировать при использовании",
    ),
    "textScale": MessageLookupByLibrary.simpleMessage("Масштаб текста"),
    "textScalePreview": MessageLookupByLibrary.simpleMessage(
      "Так будет выглядеть текст в приложении",
    ),
    "theme": MessageLookupByLibrary.simpleMessage("Тема"),
    "themeColor": MessageLookupByLibrary.simpleMessage("Цвет темы"),
    "themeMode": MessageLookupByLibrary.simpleMessage("Оформление"),
    "themeStyle": MessageLookupByLibrary.simpleMessage("Режим темы"),
    "themeStyleDesc": MessageLookupByLibrary.simpleMessage(
      "Улучшенный показывает на главной логотип сервиса, тариф, портал и кнопку подключения вместо сетки виджетов.",
    ),
    "themeStyleEnhanced": MessageLookupByLibrary.simpleMessage("Портал"),
    "themeStyleOriginal": MessageLookupByLibrary.simpleMessage("Оригинальный"),
    "tight": MessageLookupByLibrary.simpleMessage("Плотный"),
    "tilePortal": MessageLookupByLibrary.simpleMessage("Портал"),
    "time": MessageLookupByLibrary.simpleMessage("Время"),
    "timeout": MessageLookupByLibrary.simpleMessage("Тайм-аут"),
    "timeoutLabel": MessageLookupByLibrary.simpleMessage("таймаут"),
    "tintedStyle": MessageLookupByLibrary.simpleMessage("Тонированный"),
    "tip": MessageLookupByLibrary.simpleMessage("Подсказка"),
    "toggle": MessageLookupByLibrary.simpleMessage("Переключить"),
    "tolerance": MessageLookupByLibrary.simpleMessage("Допуск"),
    "tools": MessageLookupByLibrary.simpleMessage("Настройки"),
    "torch": MessageLookupByLibrary.simpleMessage("Фонарик"),
    "total": MessageLookupByLibrary.simpleMessage("Всего"),
    "totalDownload": MessageLookupByLibrary.simpleMessage("Загружено"),
    "totalTraffic": MessageLookupByLibrary.simpleMessage("Общий трафик"),
    "totalUpload": MessageLookupByLibrary.simpleMessage("Отдано"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Порт TProxy"),
    "traffic": MessageLookupByLibrary.simpleMessage("Трафик"),
    "trafficLine": m101,
    "trafficPeak": m102,
    "trafficTotal": m103,
    "trafficUsage": MessageLookupByLibrary.simpleMessage("Статистика трафика"),
    "transport": MessageLookupByLibrary.simpleMessage("Транспорт"),
    "transportHeaders": m104,
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunAuthorizationFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось получить права для TUN, поэтому он выключен.",
    ),
    "tunDesc": MessageLookupByLibrary.simpleMessage(
      "TUN требует прав администратора.",
    ),
    "tunOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "Добавленные здесь параметры заменяют настройки TUN всех профилей; остальные остаются такими, как в профиле. Параметры, добавленные в самом пользовательском профиле, имеют приоритет.",
    ),
    "tunStartFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось запустить TUN, поэтому он выключен.",
    ),
    "turnOff": MessageLookupByLibrary.simpleMessage("Выключить"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Включить"),
    "tutorialBody1": MessageLookupByLibrary.simpleMessage(
      "Сеть порталов позволяет делить трафик, подключая разные приложения через разные страны. Это называется динамическое сплит-туннелирование.\n\nЕсли вам оно не нужно, приложением можно пользоваться в «простом режиме», когда почти весь трафик заворачивается через одну страну.\n\nПереключите режим здесь.",
    ),
    "tutorialBody1Chips": MessageLookupByLibrary.simpleMessage("Это фильтры, которые режут трафик для отдельных приложений — каждому фильтру можно назначить свой сервер. Полистайте плитки влево-вправо."),
    "tutorialBody2": MessageLookupByLibrary.simpleMessage(
      "Кнопка слева открывает список фильтров, которые делят трафик. Здесь можно поменять порядок фильтров и отключить ненужные.",
    ),
    "tutorialBody2Off": MessageLookupByLibrary.simpleMessage(
      "Отключите ненужные фильтры.",
    ),
    "tutorialBody3": MessageLookupByLibrary.simpleMessage(
      "Нажатием на плитку фильтр включается, удержанием — выключается. Так туннелирование настраивается для отдельных сервисов.\n\nНапример, можно включить туннель ТОЛЬКО для Телеграма, Ютуба и Инстаграма.",
    ),
    "tutorialBody4": MessageLookupByLibrary.simpleMessage(
      "Двойным тапом на плитку переключается внешний вид плиток.",
    ),
    "tutorialBody5": MessageLookupByLibrary.simpleMessage(
      "Нажатие на «Сеть порталов» открывает экран, где все фильтры настраиваются сразу — на одном экране.",
    ),
    "tutorialBody6": MessageLookupByLibrary.simpleMessage(
      "Нажмите на портал — он откроется и начнёт работу.",
    ),
    "tutorialBody7": MessageLookupByLibrary.simpleMessage(
      "Нажмите на молнию — приложение замерит задержку до всех серверов этого режима (TLS-рукопожатие до тестового хоста внутри тоннеля), и вместо прочерков появятся цифры. Затем удержите палец на строке сервера, чтобы замерить его отдельно. Проверьте так 2–3 сервера.",
    ),
    "tutorialBody8": MessageLookupByLibrary.simpleMessage(
      "Плитка запускает портал из любого экрана: откройте шторку, нажмите карандаш, пролистайте до пользовательских приложений и добавьте «Портал».",
    ),
    "tutorialChipOff": MessageLookupByLibrary.simpleMessage(
      "Фильтр выключен. Нажмите, чтобы включить.",
    ),
    "tutorialNext": MessageLookupByLibrary.simpleMessage("Далее"),
    "tutorialStart": MessageLookupByLibrary.simpleMessage("Туториал"),
    "tutorialOk": MessageLookupByLibrary.simpleMessage("ОК"),
    "tutorialSkip": MessageLookupByLibrary.simpleMessage("Пропустить"),
    "tutorialStepOf": m105,
    "tutorialTitle1": MessageLookupByLibrary.simpleMessage("Сеть порталов"),
    "tutorialTitle2": MessageLookupByLibrary.simpleMessage("Список фильтров"),
    "tutorialTitle3": MessageLookupByLibrary.simpleMessage("Управление маршрутами"),
    "tutorialTitle4": MessageLookupByLibrary.simpleMessage("Вид плиток"),
    "tutorialTitle5": MessageLookupByLibrary.simpleMessage("Все фильтры сразу"),
    "tutorialTitle6": MessageLookupByLibrary.simpleMessage("Запуск"),
    "tutorialTitle7": MessageLookupByLibrary.simpleMessage(
      "Замер задержки",
    ),
    "tutorialTitle8": MessageLookupByLibrary.simpleMessage("Плитка в шторке"),
    "udpRelayMode": MessageLookupByLibrary.simpleMessage(
      "Режим ретрансляции UDP",
    ),
    "udpTimeout": MessageLookupByLibrary.simpleMessage("Тайм-аут UDP"),
    "udpTimeoutDesc": MessageLookupByLibrary.simpleMessage(
      "Тайм-аут UDP задаётся в секундах и действует только со стеками gvisor, system и mixed.",
    ),
    "ultra": MessageLookupByLibrary.simpleMessage("Максимум"),
    "undo": MessageLookupByLibrary.simpleMessage("Отменить"),
    "unfoldAllGroups": MessageLookupByLibrary.simpleMessage(
      "Развернуть все группы",
    ),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("Чистая задержка"),
    "unknown": MessageLookupByLibrary.simpleMessage("Неизвестно"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage(
      "Неизвестная сетевая ошибка",
    ),
    "unmaximize": MessageLookupByLibrary.simpleMessage("Свернуть в окно"),
    "unnamed": MessageLookupByLibrary.simpleMessage("Без названия"),
    "unpinWindow": MessageLookupByLibrary.simpleMessage("Открепить окно"),
    "update": MessageLookupByLibrary.simpleMessage("Обновить"),
    "updateErrorBusy": MessageLookupByLibrary.simpleMessage(
      "Дождитесь, пока подключение запустится или остановится.",
    ),
    "updateErrorChecksum": MessageLookupByLibrary.simpleMessage(
      "Загрузка не совпала с контрольной суммой релиза и удалена.",
    ),
    "updateErrorIdentity": MessageLookupByLibrary.simpleMessage(
      "Загрузка подписана не так, как это приложение, и удалена.",
    ),
    "updateErrorIncomplete": MessageLookupByLibrary.simpleMessage(
      "Загрузка оборвалась.",
    ),
    "updateErrorInstall": MessageLookupByLibrary.simpleMessage(
      "Не удалось установить обновление.",
    ),
    "updateErrorNetwork": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить. Проверьте соединение и повторите.",
    ),
    "updateErrorNoAsset": MessageLookupByLibrary.simpleMessage(
      "В этом релизе нет сборки для этого устройства.",
    ),
    "updateErrorNoChecksum": MessageLookupByLibrary.simpleMessage(
      "Релиз не публикует контрольную сумму, поэтому загрузку нельзя проверить.",
    ),
    "updateErrorNotNewer": MessageLookupByLibrary.simpleMessage(
      "Загруженная версия не новее установленной.",
    ),
    "updateErrorPermission": MessageLookupByLibrary.simpleMessage(
      "Разрешите установку приложений из этого источника и снова нажмите «Установить».",
    ),
    "updateErrorSafeMode": MessageLookupByLibrary.simpleMessage(
      "В безопасном режиме обновления не устанавливаются.",
    ),
    "updateErrorTooLarge": MessageLookupByLibrary.simpleMessage(
      "Загрузка больше, чем указано в релизе.",
    ),
    "updateErrorUntrustedHost": MessageLookupByLibrary.simpleMessage(
      "Загрузку перенаправили на адрес вне GitHub.",
    ),
    "updateExiting": MessageLookupByLibrary.simpleMessage(
      "Закрываемся, чтобы завершить обновление…",
    ),
    "updateFailedOffline": m106,
    "updateHandedOff": MessageLookupByLibrary.simpleMessage(
      "Завершите обновление в открывшемся установщике.",
    ),
    "updateHide": MessageLookupByLibrary.simpleMessage("Скрыть"),
    "updateInstall": MessageLookupByLibrary.simpleMessage("Установить"),
    "updateInstalling": MessageLookupByLibrary.simpleMessage(
      "Запускаем установщик…",
    ),
    "updateOpenedImage": MessageLookupByLibrary.simpleMessage(
      "Эту копию нельзя заменить на месте. Перетащите приложение из открытого образа в «Программы».",
    ),
    "updatePackageManager": MessageLookupByLibrary.simpleMessage(
      "Эта копия установлена менеджером пакетов. Обновите её через него.",
    ),
    "updateReady": MessageLookupByLibrary.simpleMessage(
      "Загружено и проверено.",
    ),
    "updateUnsupported": MessageLookupByLibrary.simpleMessage(
      "Эта копия не может обновиться сама. Скачайте новую версию на GitHub.",
    ),
    "updateVerifying": MessageLookupByLibrary.simpleMessage(
      "Проверяем загрузку…",
    ),
    "updateViewOnGitHub": MessageLookupByLibrary.simpleMessage(
      "Открыть на GitHub",
    ),
    "upload": MessageLookupByLibrary.simpleMessage("Отдача"),
    "uploadBandwidth": MessageLookupByLibrary.simpleMessage("Скорость отдачи"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlTip": m107,
    "useHosts": MessageLookupByLibrary.simpleMessage("Использовать hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage(
      "Использовать системный hosts",
    ),
    "usedTraffic": MessageLookupByLibrary.simpleMessage(
      "Использованный трафик",
    ),
    "username": MessageLookupByLibrary.simpleMessage("Имя пользователя"),
    "value": MessageLookupByLibrary.simpleMessage("Значение"),
    "vibration": MessageLookupByLibrary.simpleMessage("Вибрация"),
    "vibrationDesc": MessageLookupByLibrary.simpleMessage(
      "Отклик на касания, вибрация при удержании кнопки и при запуске.",
    ),
    "view": MessageLookupByLibrary.simpleMessage("Просмотр"),
    "virtualIpv4": MessageLookupByLibrary.simpleMessage("Виртуальный IPv4"),
    "vividStyle": MessageLookupByLibrary.simpleMessage("Яркий"),
    "vpnBlockedByAnotherApp": MessageLookupByLibrary.simpleMessage(
      "VPN блокирует другое приложение",
    ),
    "vpnBlockedByAnotherAppTip": MessageLookupByLibrary.simpleMessage(
      "У другого VPN-приложения включена «Постоянная VPN». Отключите её для этого приложения в настройках VPN и запустите снова.",
    ),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "Обнаружено изменение настроек VPN",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "VPN автоматически направляет весь системный трафик через VpnService.",
    ),
    "vpnPermissionNotGranted": m108,
    "vpnRestrictedByAdministrator": MessageLookupByLibrary.simpleMessage(
      "VPN на этом устройстве ограничен администратором",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage(
      "Настройка WebDAV",
    ),
    "website": MessageLookupByLibrary.simpleMessage("Сайт"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage(
      "Режим белого списка",
    ),
    "writeToSystem": MessageLookupByLibrary.simpleMessage(
      "Записывать в систему",
    ),
    "writeToSystemDesc": MessageLookupByLibrary.simpleMessage(
      "«Записывать в систему» также устанавливает системные часы; Android это игнорирует.",
    ),
    "yearsAgo": m109,
    "yearsAgoShort": m110,
    "yes": MessageLookupByLibrary.simpleMessage("Да"),
    "zhCN": MessageLookupByLibrary.simpleMessage("Упрощённый китайский"),
  };
}
