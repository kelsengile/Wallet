import 'package:flutter/material.dart';

/// A currency the app can show.
class AppCurrency {
  final String code;
  final String symbol;
  final String name;

  /// Approximate units per 1 US dollar. Only a starting point for the
  /// convert pop-up, where the user can edit the rate.
  final double perUsd;
  const AppCurrency(this.code, this.symbol, this.name, this.perUsd);
}

/// A place whose clock the app follows (standard time, no daylight saving).
class AppLocation {
  final String id;
  final String name;
  final int utcMinutes;
  const AppLocation(this.id, this.name, this.utcMinutes);
}

class AppLanguage {
  final String code;
  final String name;
  final String native;
  const AppLanguage(this.code, this.name, this.native);
}

/// Translations. The key is the English text. A missing entry shows English.
/// To translate more text: write 'Text'.tr in the screen, add a line here.
class AppStrings {
  AppStrings._();

  static String of(String key) {
    if (AppConstants.languageCode == 'en') return key;
    return _table[AppConstants.languageCode]?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _table = {
    'fil': {
      'Settings': 'Mga Setting', 'Appearance': 'Hitsura',
      'Localization': 'Lokalisasyon', 'Security': 'Seguridad',
      'Theme': 'Tema', 'Font': 'Font', 'Animation': 'Animasyon',
      'Currency': 'Salapi', 'Location': 'Lokasyon', 'Language': 'Wika',
      'Close': 'Isara', 'Cancel': 'Kanselahin', 'Apply': 'Ilapat',
      'Convert': 'I-convert', 'Keep amounts': 'Panatilihin ang halaga',
      'Convert your amounts?': 'I-convert ang mga halaga?',
      'Profile': 'Profile', 'Notifications': 'Mga Abiso',
      'Tools': 'Mga Kasangkapan', 'Calculator': 'Calculator',
      'Converter': 'Converter', 'Pages': 'Mga Pahina',
      'Finance': 'Pananalapi', 'Schedule': 'Iskedyul', 'Health': 'Kalusugan',
      'Preferences': 'Mga Kagustuhan', 'Categories': 'Mga Kategorya',
      'Database': 'Database', 'Help & Support': 'Tulong at Suporta',
      'FAQ': 'Mga Madalas Itanong', 'Rate': 'I-rate', 'Feedback': 'Puna',
      'About': 'Tungkol', 'Version': 'Bersyon',
      'Search Momentum': 'Hanapin sa Momentum', 'Income': 'Kita',
      'Expense': 'Gastos', 'Transfer': 'Paglipat', 'Reminder': 'Paalala',
      'My Accounts': 'Aking mga Account', 'Total Balance': 'Kabuuang Balanse',
      'History': 'Kasaysayan', 'Analytics': 'Analytics',
      'App Security': 'Seguridad ng App', 'Unlock': 'I-unlock',
      'Momentum is locked': 'Naka-lock ang Momentum',
      'Unlock Momentum': 'I-unlock ang Momentum',
    },
    'es': {
      'Settings': 'Ajustes', 'Appearance': 'Apariencia',
      'Localization': 'Localización', 'Security': 'Seguridad',
      'Theme': 'Tema', 'Font': 'Fuente', 'Animation': 'Animación',
      'Currency': 'Moneda', 'Location': 'Ubicación', 'Language': 'Idioma',
      'Close': 'Cerrar', 'Cancel': 'Cancelar', 'Apply': 'Aplicar',
      'Convert': 'Convertir', 'Keep amounts': 'Mantener importes',
      'Convert your amounts?': '¿Convertir tus importes?',
      'Profile': 'Perfil', 'Notifications': 'Notificaciones',
      'Tools': 'Herramientas', 'Calculator': 'Calculadora',
      'Converter': 'Conversor', 'Pages': 'Páginas',
      'Finance': 'Finanzas', 'Schedule': 'Agenda', 'Health': 'Salud',
      'Preferences': 'Preferencias', 'Categories': 'Categorías',
      'Database': 'Base de datos', 'Help & Support': 'Ayuda y soporte',
      'FAQ': 'Preguntas frecuentes', 'Rate': 'Valorar',
      'Feedback': 'Comentarios', 'About': 'Acerca de', 'Version': 'Versión',
      'Search Momentum': 'Buscar en Momentum', 'Income': 'Ingresos',
      'Expense': 'Gastos', 'Transfer': 'Transferencia',
      'Reminder': 'Recordatorio', 'My Accounts': 'Mis cuentas',
      'Total Balance': 'Saldo total', 'History': 'Historial',
      'Analytics': 'Analíticas', 'App Security': 'Seguridad de la app',
      'Unlock': 'Desbloquear', 'Momentum is locked': 'Momentum está bloqueado',
      'Unlock Momentum': 'Desbloquear Momentum',
    },
    'fr': {
      'Settings': 'Paramètres', 'Appearance': 'Apparence',
      'Localization': 'Localisation', 'Security': 'Sécurité',
      'Theme': 'Thème', 'Font': 'Police', 'Animation': 'Animation',
      'Currency': 'Devise', 'Location': 'Emplacement', 'Language': 'Langue',
      'Close': 'Fermer', 'Cancel': 'Annuler', 'Apply': 'Appliquer',
      'Convert': 'Convertir', 'Keep amounts': 'Garder les montants',
      'Convert your amounts?': 'Convertir vos montants ?',
      'Profile': 'Profil', 'Notifications': 'Notifications',
      'Tools': 'Outils', 'Calculator': 'Calculatrice',
      'Converter': 'Convertisseur', 'Pages': 'Pages',
      'Finance': 'Finances', 'Schedule': 'Agenda', 'Health': 'Santé',
      'Preferences': 'Préférences', 'Categories': 'Catégories',
      'Database': 'Base de données', 'Help & Support': 'Aide et assistance',
      'FAQ': 'FAQ', 'Rate': 'Noter', 'Feedback': 'Retour',
      'About': 'À propos', 'Version': 'Version',
      'Search Momentum': 'Rechercher dans Momentum', 'Income': 'Revenus',
      'Expense': 'Dépenses', 'Transfer': 'Virement', 'Reminder': 'Rappel',
      'My Accounts': 'Mes comptes', 'Total Balance': 'Solde total',
      'History': 'Historique', 'Analytics': 'Analyses',
      'App Security': "Sécurité de l'app", 'Unlock': 'Déverrouiller',
      'Momentum is locked': 'Momentum est verrouillé',
      'Unlock Momentum': 'Déverrouiller Momentum',
    },
        'zh': {
      'Settings': '设置', 'Appearance': '外观',
      'Localization': '本地化', 'Security': '安全',
      'Theme': '主题', 'Font': '字体', 'Animation': '动画',
      'Currency': '货币', 'Location': '位置', 'Language': '语言',
      'Close': '关闭', 'Cancel': '取消', 'Apply': '应用',
      'Convert': '转换', 'Keep amounts': '保留金额',
      'Convert your amounts?': '转换您的金额？',
      'Profile': '个人资料', 'Notifications': '通知',
      'Tools': '工具', 'Calculator': '计算器',
      'Converter': '转换器', 'Pages': '页面',
      'Finance': '财务', 'Schedule': '日程', 'Health': '健康',
      'Preferences': '偏好设置', 'Categories': '分类',
      'Database': '数据库', 'Help & Support': '帮助与支持',
      'FAQ': '常见问题', 'Rate': '评分', 'Feedback': '反馈',
      'About': '关于', 'Version': '版本',
      'Search Momentum': '搜索 Momentum', 'Income': '收入',
      'Expense': '支出', 'Transfer': '转账', 'Reminder': '提醒',
      'My Accounts': '我的账户', 'Total Balance': '总余额',
      'History': '历史记录', 'Analytics': '数据分析',
      'App Security': '应用安全', 'Unlock': '解锁',
      'Momentum is locked': 'Momentum 已锁定',
      'Unlock Momentum': '解锁 Momentum',
    },
    'hi': {
      'Settings': 'सेटिंग्स', 'Appearance': 'दिखावट',
      'Localization': 'स्थानीयकरण', 'Security': 'सुरक्षा',
      'Theme': 'थीम', 'Font': 'फ़ॉन्ट', 'Animation': 'एनिमेशन',
      'Currency': 'मुद्रा', 'Location': 'स्थान', 'Language': 'भाषा',
      'Close': 'बंद करें', 'Cancel': 'रद्द करें', 'Apply': 'लागू करें',
      'Convert': 'बदलें', 'Keep amounts': 'राशि वैसी रखें',
      'Convert your amounts?': 'क्या राशि बदलें?',
      'Profile': 'प्रोफ़ाइल', 'Notifications': 'सूचनाएँ',
      'Tools': 'उपकरण', 'Calculator': 'कैलकुलेटर',
      'Converter': 'कन्वर्टर', 'Pages': 'पेज',
      'Finance': 'वित्त', 'Schedule': 'कार्यक्रम', 'Health': 'स्वास्थ्य',
      'Preferences': 'प्राथमिकताएँ', 'Categories': 'श्रेणियाँ',
      'Database': 'डेटाबेस', 'Help & Support': 'सहायता और समर्थन',
      'FAQ': 'अक्सर पूछे जाने वाले प्रश्न', 'Rate': 'रेट करें',
      'Feedback': 'प्रतिक्रिया', 'About': 'परिचय', 'Version': 'संस्करण',
      'Search Momentum': 'Momentum में खोजें', 'Income': 'आय',
      'Expense': 'खर्च', 'Transfer': 'ट्रांसफ़र', 'Reminder': 'रिमाइंडर',
      'My Accounts': 'मेरे खाते', 'Total Balance': 'कुल शेष',
      'History': 'इतिहास', 'Analytics': 'विश्लेषण',
      'App Security': 'ऐप सुरक्षा', 'Unlock': 'अनलॉक करें',
      'Momentum is locked': 'Momentum लॉक है',
      'Unlock Momentum': 'Momentum अनलॉक करें',
    },
    'ar': {
      'Settings': 'الإعدادات', 'Appearance': 'المظهر',
      'Localization': 'التوطين', 'Security': 'الأمان',
      'Theme': 'السمة', 'Font': 'الخط', 'Animation': 'الحركة',
      'Currency': 'العملة', 'Location': 'الموقع', 'Language': 'اللغة',
      'Close': 'إغلاق', 'Cancel': 'إلغاء', 'Apply': 'تطبيق',
      'Convert': 'تحويل', 'Keep amounts': 'الإبقاء على المبالغ',
      'Convert your amounts?': 'هل تريد تحويل مبالغك؟',
      'Profile': 'الملف الشخصي', 'Notifications': 'الإشعارات',
      'Tools': 'الأدوات', 'Calculator': 'الآلة الحاسبة',
      'Converter': 'المحوّل', 'Pages': 'الصفحات',
      'Finance': 'المالية', 'Schedule': 'الجدول', 'Health': 'الصحة',
      'Preferences': 'التفضيلات', 'Categories': 'الفئات',
      'Database': 'قاعدة البيانات', 'Help & Support': 'المساعدة والدعم',
      'FAQ': 'الأسئلة الشائعة', 'Rate': 'قيّم', 'Feedback': 'ملاحظات',
      'About': 'حول', 'Version': 'الإصدار',
      'Search Momentum': 'البحث في Momentum', 'Income': 'الدخل',
      'Expense': 'المصروفات', 'Transfer': 'تحويل', 'Reminder': 'تذكير',
      'My Accounts': 'حساباتي', 'Total Balance': 'الرصيد الإجمالي',
      'History': 'السجل', 'Analytics': 'التحليلات',
      'App Security': 'أمان التطبيق', 'Unlock': 'فتح القفل',
      'Momentum is locked': 'Momentum مقفل',
      'Unlock Momentum': 'فتح قفل Momentum',
    },
    'pt': {
      'Settings': 'Configurações', 'Appearance': 'Aparência',
      'Localization': 'Localização', 'Security': 'Segurança',
      'Theme': 'Tema', 'Font': 'Fonte', 'Animation': 'Animação',
      'Currency': 'Moeda', 'Location': 'Local', 'Language': 'Idioma',
      'Close': 'Fechar', 'Cancel': 'Cancelar', 'Apply': 'Aplicar',
      'Convert': 'Converter', 'Keep amounts': 'Manter valores',
      'Convert your amounts?': 'Converter seus valores?',
      'Profile': 'Perfil', 'Notifications': 'Notificações',
      'Tools': 'Ferramentas', 'Calculator': 'Calculadora',
      'Converter': 'Conversor', 'Pages': 'Páginas',
      'Finance': 'Finanças', 'Schedule': 'Agenda', 'Health': 'Saúde',
      'Preferences': 'Preferências', 'Categories': 'Categorias',
      'Database': 'Banco de dados', 'Help & Support': 'Ajuda e suporte',
      'FAQ': 'Perguntas frequentes', 'Rate': 'Avaliar',
      'Feedback': 'Feedback', 'About': 'Sobre', 'Version': 'Versão',
      'Search Momentum': 'Buscar no Momentum', 'Income': 'Receitas',
      'Expense': 'Despesas', 'Transfer': 'Transferência',
      'Reminder': 'Lembrete', 'My Accounts': 'Minhas contas',
      'Total Balance': 'Saldo total', 'History': 'Histórico',
      'Analytics': 'Análises', 'App Security': 'Segurança do app',
      'Unlock': 'Desbloquear', 'Momentum is locked': 'O Momentum está bloqueado',
      'Unlock Momentum': 'Desbloquear o Momentum',
    },
  };
}

/// 'Settings'.tr -> the text in the chosen language.
extension TranslateText on String {
  String get tr => AppStrings.of(this);
}

/// App-wide constants. Every fixed value that is shared between files
/// (or is a tuning knob for a screen) lives here.
class AppConstants {
  AppConstants._();

  // ---------- App ----------
  static const String appName = 'Momentum';
  static const String appVersion = '1.0.0'; // keep in sync with pubspec.yaml
  static const String databaseName = 'momentum.db';
  static const int databaseVersion = 1;

  // ---------- Database ----------
  static const String schemaAsset = 'lib/database/schema.sql';
  static const String seedAsset = 'lib/database/seed.sql';

  /// Written into backup files and checked again on import.
  static const String exportApp = 'momentum';
  static const int exportFormat = 1;

  // ---------- Money ----------
  /// Changed from Settings > Localization > Currency (default: dollar).
  static String currencySymbol = '\$';

  /// Symbol followed by a space, used on the big balance numbers.
  static String get currencyPrefix => '$currencySymbol ';

  /// Money is stored as whole centavos.
  static const int centavosPerPeso = 100;

  static const Color incomeColor = Color(0xFF4CAF50);
  static const Color expenseColor = Color(0xFFF44A5A);
  // Defaults for the other transaction colors
  static const Color transferColor = Color(0xFF2196F3);
  static const Color reminderColor = Color(0xFFFFA726);

  // ---------- Localization ----------
  static const String prefCurrency = 'settings.currency';
  static const String prefLocation = 'settings.location';
  static const String prefLanguage = 'settings.language';

  // Security is kept in SharedPreferences (not the database) so it is not
  // written into backup files.
  static const String prefSecurityOn = 'security.enabled';
  static const String prefSecurityMethods = 'security.methods';

  static const String prefSecurityPinHash = 'security.pinHash';
  static const String prefSecurityPinSalt = 'security.pinSalt';

  static const String prefSecurityPinLength = 'security.pinLength';

  static const int pinMinLength = 4;
  static const int pinMaxLength = 6;

  /// How long the app can stay in the background before it locks again.
  static const Duration lockAfterBackground = Duration(seconds: 30);

  /// Minutes from UTC of the chosen location (default America Eastern).
  static int locationOffsetMinutes = -300;
  static String languageCode = 'en';

  static const List<AppCurrency> currencies = [
    AppCurrency('USD', '\$', 'US Dollar', 1),
    AppCurrency('EUR', '€', 'Euro', 0.92),
    AppCurrency('GBP', '£', 'British Pound', 0.79),
    AppCurrency('JPY', '¥', 'Japanese Yen', 150),
    AppCurrency('PHP', '₱', 'Philippine Peso', 57),
    AppCurrency('INR', '₹', 'Indian Rupee', 85),
    AppCurrency('CNY', 'CN¥', 'Chinese Yuan', 7.2),
    AppCurrency('KRW', '₩', 'South Korean Won', 1400),
    AppCurrency('AUD', 'A\$', 'Australian Dollar', 1.55),
    AppCurrency('CAD', 'C\$', 'Canadian Dollar', 1.38),
    AppCurrency('CHF', 'CHF', 'Swiss Franc', 0.88),
    AppCurrency('SGD', 'S\$', 'Singapore Dollar', 1.34),
    AppCurrency('HKD', 'HK\$', 'Hong Kong Dollar', 7.8),
    AppCurrency('NZD', 'NZ\$', 'New Zealand Dollar', 1.65),
    AppCurrency('MXN', 'MX\$', 'Mexican Peso', 18.5),
    AppCurrency('BRL', 'R\$', 'Brazilian Real', 5.5),
    AppCurrency('AED', 'AED', 'UAE Dirham', 3.67),
    AppCurrency('SAR', 'SAR', 'Saudi Riyal', 3.75),
    AppCurrency('ZAR', 'R', 'South African Rand', 18),
    AppCurrency('NGN', '₦', 'Nigerian Naira', 1550),
    AppCurrency('EGP', 'E£', 'Egyptian Pound', 49),
    AppCurrency('TRY', '₺', 'Turkish Lira', 38),
    AppCurrency('RUB', '₽', 'Russian Ruble', 90),
    AppCurrency('IDR', 'Rp', 'Indonesian Rupiah', 16000),
    AppCurrency('THB', '฿', 'Thai Baht', 35),
    AppCurrency('MYR', 'RM', 'Malaysian Ringgit', 4.4),
    AppCurrency('VND', '₫', 'Vietnamese Dong', 25000),
  ];

  static AppCurrency currencyByCode(String? code) => currencies.firstWhere(
    (c) => c.code == code,
    orElse: () => currencies.first,
  );

  /// The first one is the default (America).
  static const List<AppLocation> locations = [
    AppLocation('us_east', 'America (Eastern)', -300),
    AppLocation('us_central', 'America (Central)', -360),
    AppLocation('us_mountain', 'America (Mountain)', -420),
    AppLocation('us_pacific', 'America (Pacific)', -480),
    AppLocation('canada', 'Canada (Toronto)', -300),
    AppLocation('mexico', 'Mexico (Mexico City)', -360),
    AppLocation('brazil', 'Brazil (São Paulo)', -180),
    AppLocation('uk', 'United Kingdom', 0),
    AppLocation('france', 'France', 60),
    AppLocation('germany', 'Germany', 60),
    AppLocation('spain', 'Spain', 60),
    AppLocation('italy', 'Italy', 60),
    AppLocation('nigeria', 'Nigeria', 60),
    AppLocation('southafrica', 'South Africa', 120),
    AppLocation('egypt', 'Egypt', 120),
    AppLocation('turkey', 'Turkey', 180),
    AppLocation('saudi', 'Saudi Arabia', 180),
    AppLocation('russia', 'Russia (Moscow)', 180),
    AppLocation('uae', 'United Arab Emirates', 240),
    AppLocation('india', 'India', 330),
    AppLocation('thailand', 'Thailand', 420),
    AppLocation('indonesia', 'Indonesia (Jakarta)', 420),
    AppLocation('china', 'China', 480),
    AppLocation('singapore', 'Singapore', 480),
    AppLocation('philippines', 'Philippines', 480),
    AppLocation('japan', 'Japan', 540),
    AppLocation('korea', 'South Korea', 540),
    AppLocation('australia', 'Australia (Sydney)', 600),
    AppLocation('newzealand', 'New Zealand', 720),
  ];

  static AppLocation locationById(String? id) => locations.firstWhere(
    (l) => l.id == id,
    orElse: () => locations.first,
  );

  static const List<AppLanguage> languages = [
    AppLanguage('en', 'English', 'English'),
    AppLanguage('fil', 'Filipino', 'Filipino'),
    AppLanguage('es', 'Spanish', 'Español'),
    AppLanguage('fr', 'French', 'Français'),
    AppLanguage('zh', 'Chinese (Mandarin)', '中文'),
    AppLanguage('hi', 'Hindi', 'हिन्दी'),
    AppLanguage('ar', 'Arabic', 'العربية'),
    AppLanguage('pt', 'Portuguese', 'Português'),
  ];

  static AppLanguage languageByCode(String? code) => languages.firstWhere(
    (l) => l.code == code,
    orElse: () => languages.first,
  );

  // ---------- Spacing scale ----------
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceSmMd = 12; // between Sm and Md
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // ---------- Radii ----------
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 20;

  // ---------- Common sizes ----------
  /// Height of the progress bar under an app bar.
  static const double progressBarHeight = 3;

  /// Big icon on "empty" screens.
  static const double emptyStateIconSize = 48;

  /// Space at the top of the drawer list.
  static const double drawerTopGap = 10;

  /// Normal body font size, used to read the current text scale.
  static const double baseFontSize = 14;

    /// Makes the floating + button and its small buttons bigger
  /// (1.0 = the old size).
  static const double addButtonScale = 1.2;

  /// How much the + button (and its small buttons) follow the font size.
  /// 0 = always the same size, 1 = changes as much as the font setting.
  /// Lower = the smallest size is bigger and the biggest size is smaller.
  static const double addButtonFollow = 0.5;

  /// Slide time when changing pages.
  static const Duration pageAnimationDuration = Duration(milliseconds: 250);

  // ---------- Opacity / blending ----------
  /// Softer text and icons (secondary text).
  static const double mutedAlpha = 0.7;

  /// Lines between rows / header and content inside a card.
  static const double dividerAlpha = 0.25;

  /// Outlines of fields and boxes.
  static const double borderAlpha = 0.5;

  /// Light tint behind icons and chips drawn on the accent color.
  static const double tintAlpha = 0.18;

  /// Thin vertical separator between income and expense.
  static const double separatorAlpha = 0.3;

  /// How far the divider color moves from the accent toward its glyph color.
  static const double dividerBlend = 0.18;

  // ---------- Pop-ups ----------
  /// Darker dim behind every pop-up, so the pop-up colors stand out more.
  static const Color popupBarrier = Color(0xCC000000);
  static const double popupRadius = 24;
  static const EdgeInsets popupInsetPadding =
      EdgeInsets.symmetric(horizontal: 40, vertical: 24);
  static const EdgeInsets popupTitlePadding = EdgeInsets.fromLTRB(20, 18, 20, 0);
  static const EdgeInsets popupContentPadding =
      EdgeInsets.fromLTRB(20, 12, 20, 4);
  static const EdgeInsets popupActionsPadding =
      EdgeInsets.fromLTRB(12, 0, 12, 10);

  /// Shorter version (used by the delete pop-up).
  static const EdgeInsets popupTitlePaddingCompact =
      EdgeInsets.fromLTRB(20, 14, 20, 0);
  static const EdgeInsets popupContentPaddingCompact =
      EdgeInsets.fromLTRB(20, 6, 20, 0);
  static const EdgeInsets popupActionsPaddingCompact =
      EdgeInsets.fromLTRB(12, 0, 12, 6);

  // ---------- Categories screen ----------
  static const double categoryBarRadius = 16;
  static const double categoryCardHeaderHeight = 48;
  static const int iconGridColumns = 8;
  static const double iconGridGap = 4;
  static const double iconTileRadius = 10;
  static const double categoryBarLighten = 0.15;
  static const double categoryAvatarAlpha = 0.12;
  static const double iconTileAlpha = 0.10;
  static const double iconTileSelectedAlpha = 0.28;

  // Imported (picture) icons on the Categories screen.
  // An icon value that starts with this prefix is a file path.
  static const String iconImagePrefix = 'img:';
  static const String prefIconLibrary = 'categoryIcons.library'; // imported icons
  static const String prefIconHidden = 'categoryIcons.hidden'; // deleted built-ins
  static const String iconImageFolder = 'category_icons';

  // ---------- Settings screen ----------
  static const String prefTheme = 'settings.theme';
  static const String prefColor = 'settings.customColor';
  static const String prefAccent = 'settings.accentColor';
  static const String prefText = 'settings.textColor';
  static const String prefTextSize = 'settings.textSizeIndex';
  static const String prefFontStyle = 'settings.fontStyle';
  static const String prefBoldText = 'settings.boldText';
  // Saved transaction colors (Specific Color)
  static const String prefIncomeColor = 'settings.transactionColor.income';
  static const String prefExpenseColor = 'settings.transactionColor.expense';
  static const String prefTransferColor = 'settings.transactionColor.transfer';
  // Defaults for the action colors (Delete / Done)
  static const Color deleteColor = Color(0xFFE53935); // Colors.red.shade600
  static const Color doneColor = Color(0xFF1B6B3A);
  // Key text kept from the old "notification" name so saved colors survive.
  static const String prefReminderColor = 'settings.transactionColor.notification';
  // Order of the account types on the Finance screen.
  static const String prefTypeOrder = 'finance.typeOrder';
  // Order of each category list on the Categories screen.
  // The full key is this prefix + the group name (e.g. "category.order.income").
  static const String prefCategoryOrder = 'category.order.';
  static const prefAnimEnabled = 'settings.animEnabled';
  // Saved action colors (Specific Color)
  static const String prefDeleteColor = 'settings.actionColor.delete';
  static const String prefDoneColor = 'settings.actionColor.done';

  static const List<String> textSizeLabels = [
    'Smallest',
    'Small',
    'Default (system)',
    'Big',
    'Biggest',
  ];
  static const List<double> textScales = [0.8, 0.9, 1.0, 1.15, 1.3];
  static const int defaultTextSizeIndex = 2;

  static const double fontSliderWidth = 150;
  static const double colorBoxHeight = 72;
  static const double hexFontSize = 18;
  static const int hexInputLength = 7; // "#" + 6 digits
  static const double hueGradientStep = 60;
  static const double gradientSliderHeight = 32;
  static const double gradientTrackHeight = 12;
  static const double segmentSelectedAlpha = 0.25;

  // Animation speed (Settings > Appearance). Same 5 steps as font size.
  // Each value is a time dilation: bigger = slower, smaller = faster.
  static const String prefAnimSpeed = 'settings.animationSpeedIndex';
  static const List<String> animSpeedLabels = [
    'Slowest',
    'Slow',
    'Default',
    'Fast',
    'Fastest',
  ];
  static const List<double> animTimeDilations = [2.0, 1.5, 1.0, 0.7, 0.45];
  static const int defaultAnimSpeedIndex = 2;

  // ---------- Finance screen: account cards ----------
  // The card has the real card ratio (ISO/IEC 7810 ID-1: 85.60 x 53.98 mm).
  // Every size inside the card is a multiple of "u" = card width / 612.
  // At the "Big" font size the card and its text match the sample.
  // cardFollow / textFollow = how much of the font size change the CARD /
  // TEXT follows (0 = never changes, 1 = changes as much as the setting).
  static const double cardSampleWidth = 612;
  static const double cardRatio = 85.60 / 53.98;
  static const double bigTextScale = 1.15;
  static const double baseCardWidth = 250 * bigTextScale;
  static const double cardFollow = 0.25;
  static const double textFollow = 0.4;
  static const Duration cardFlipDuration = Duration(milliseconds: 400);
  static const double cardBandAlpha = 0.6;

  // ---------- Finance screen: total balance card ----------
  /// true  = keep the exact debit/credit card ratio (taller).
  /// false = only as tall as the content.
  static const bool totalCardUseRatio = false;

  /// Space between the app bar and "Total Balance".
  static const double totalCardTopMargin = 60;

  /// Space between the balance row and the bottom edge of the card.
  static const double totalCardBottomMargin = 35;
  static const double totalCardSideMargin = spaceLg - spaceXs;

  /// Space between "Total Balance" and the balance row.
  static const double totalCardLabelGap = 10;
  static const double totalCardRadius = 28;

  /// w300 = light ... w700 = bold.
  static const FontWeight balanceWeight = FontWeight.w700;
  static const double balanceFontSize = 38;

  /// Moves the * down. Fraction of the font size.
  static const double maskDrop = 0.25;

  /// Shown instead of amounts when hidden.
  static const String maskText = '****';
}