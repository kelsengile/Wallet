import 'package:material_ui/material_ui.dart';

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

  static const _langOrder = ['fil', 'es', 'fr', 'zh', 'hi', 'ar', 'pt'];

  static String of(String key) {
    final code = AppConstants.languageCode;
    if (code == 'en') return key;
    final direct = _table[code]?[key];
    if (direct != null) return direct;
    final i = _langOrder.indexOf(code);
    final row = _more[key];
    if (i < 0 || row == null || i >= row.length) return key;
    return row[i];
  }

  // Order: fil, es, fr, zh, hi, ar, pt
  static const Map<String, List<String>> _more = {
    // ----- Profile -----
    'Identification': ['Pagkakakilanlan', 'Identificación', 'Identification', '身份证件', 'पहचान', 'الهوية', 'Identificação'],
    'Your name': ['Iyong pangalan', 'Tu nombre', 'Votre nom', '你的姓名', 'आपका नाम', 'اسمك', 'Seu nome'],
    'Tap the pencil at the top to set up your profile.': ['I-tap ang lapis sa itaas para i-set up ang iyong profile.', 'Toca el lápiz de arriba para configurar tu perfil.', 'Touchez le crayon en haut pour configurer votre profil.', '点击顶部的铅笔来设置你的个人资料。', 'अपनी प्रोफ़ाइल सेट करने के लिए ऊपर पेंसिल पर टैप करें।', 'اضغط على القلم في الأعلى لإعداد ملفك الشخصي.', 'Toque no lápis no topo para configurar seu perfil.'],
    'Edit Profile': ['I-edit ang Profile', 'Editar perfil', 'Modifier le profil', '编辑个人资料', 'प्रोफ़ाइल संपादित करें', 'تعديل الملف الشخصي', 'Editar perfil'],
    'Name': ['Pangalan', 'Nombre', 'Nom', '姓名', 'नाम', 'الاسم', 'Nome'],
    'Username': ['Username', 'Nombre de usuario', "Nom d'utilisateur", '用户名', 'उपयोगकर्ता नाम', 'اسم المستخدم', 'Nome de usuário'],
    'Bio': ['Bio', 'Biografía', 'Bio', '简介', 'परिचय', 'نبذة', 'Bio'],
    'Save Changes': ['I-save ang mga Pagbabago', 'Guardar cambios', 'Enregistrer', '保存更改', 'बदलाव सहेजें', 'حفظ التغييرات', 'Salvar alterações'],
    'Banner picture': ['Larawan ng banner', 'Imagen de banner', 'Image de bannière', '横幅图片', 'बैनर चित्र', 'صورة الغلاف', 'Imagem do banner'],
    'Profile picture': ['Larawan ng profile', 'Foto de perfil', 'Photo de profil', '头像', 'प्रोफ़ाइल चित्र', 'صورة الملف الشخصي', 'Foto de perfil'],
    'Camera': ['Camera', 'Cámara', 'Appareil photo', '相机', 'कैमरा', 'الكاميرا', 'Câmera'],
    'Gallery': ['Gallery', 'Galería', 'Galerie', '相册', 'गैलरी', 'المعرض', 'Galeria'],
    'Remove picture': ['Alisin ang larawan', 'Quitar imagen', "Retirer l'image", '移除图片', 'चित्र हटाएँ', 'إزالة الصورة', 'Remover imagem'],
    'New ID': ['Bagong ID', 'Nueva identificación', "Nouvelle pièce d'identité", '新证件', 'नई आईडी', 'هوية جديدة', 'Novo documento'],
    'Edit ID': ['I-edit ang ID', 'Editar identificación', "Modifier la pièce d'identité", '编辑证件', 'आईडी संपादित करें', 'تعديل الهوية', 'Editar documento'],
    'ID front': ['Harap ng ID', 'Frente del documento', 'Recto de la pièce', '证件正面', 'आईडी का अगला भाग', 'وجه الهوية', 'Frente do documento'],
    'ID back': ['Likod ng ID', 'Reverso del documento', 'Verso de la pièce', '证件背面', 'आईडी का पिछला भाग', 'ظهر الهوية', 'Verso do documento'],
    'Front': ['Harap', 'Frente', 'Recto', '正面', 'आगे', 'الأمام', 'Frente'],
    'Back': ['Likod', 'Reverso', 'Verso', '背面', 'पीछे', 'الخلف', 'Verso'],
    'Details': ['Mga detalye', 'Detalles', 'Détails', '详情', 'विवरण', 'التفاصيل', 'Detalhes'],
    'Add ID': ['Magdagdag ng ID', 'Añadir identificación', "Ajouter une pièce d'identité", '添加证件', 'आईडी जोड़ें', 'إضافة هوية', 'Adicionar documento'],
    'Delete ID': ['Burahin ang ID', 'Eliminar identificación', "Supprimer la pièce d'identité", '删除证件', 'आईडी हटाएँ', 'حذف الهوية', 'Excluir documento'],
    'Delete': ['Burahin', 'Eliminar', 'Supprimer', '删除', 'हटाएँ', 'حذف', 'Excluir'],
    'No front picture yet': ['Wala pang larawan sa harap', 'Aún no hay imagen frontal', "Pas encore d'image du recto", '尚无正面图片', 'अभी तक कोई अगला चित्र नहीं', 'لا توجد صورة أمامية بعد', 'Ainda sem imagem da frente'],
    'No back picture yet': ['Wala pang larawan sa likod', 'Aún no hay imagen del reverso', "Pas encore d'image du verso", '尚无背面图片', 'अभी तक कोई पिछला चित्र नहीं', 'لا توجد صورة خلفية بعد', 'Ainda sem imagem do verso'],
    'This ID and its pictures will be permanently deleted.': ['Permanenteng buburahin ang ID na ito at ang mga larawan nito.', 'Esta identificación y sus imágenes se eliminarán permanentemente.', "Cette pièce d'identité et ses images seront définitivement supprimées.", '此证件及其图片将被永久删除。', 'यह आईडी और इसके चित्र हमेशा के लिए हटा दिए जाएँगे।', 'سيتم حذف هذه الهوية وصورها نهائيًا.', 'Este documento e suas imagens serão excluídos permanentemente.'],
    "This can't be undone.": ['Hindi na ito maibabalik.', 'Esto no se puede deshacer.', 'Cette action est irréversible.', '此操作无法撤销。', 'इसे वापस नहीं किया जा सकता।', 'لا يمكن التراجع عن هذا.', 'Isto não pode ser desfeito.'],
    // ----- Calculator -----
    'Clear': ['I-clear', 'Borrar', 'Effacer', '清除', 'साफ़ करें', 'مسح', 'Limpar'],
    'No history yet': ['Wala pang kasaysayan', 'Aún no hay historial', "Pas encore d'historique", '暂无历史记录', 'अभी तक कोई इतिहास नहीं', 'لا يوجد سجل بعد', 'Ainda sem histórico'],
    // ----- Converter: categories -----
    'Data': ['Data', 'Datos', 'Données', '数据', 'डेटा', 'البيانات', 'Dados'],
    'Date': ['Petsa', 'Fecha', 'Date', '日期', 'तारीख़', 'التاريخ', 'Data'],
    'Discount': ['Diskwento', 'Descuento', 'Remise', '折扣', 'छूट', 'الخصم', 'Desconto'],
    'Volume': ['Volume', 'Volumen', 'Volume', '体积', 'आयतन', 'الحجم', 'Volume'],
    'Speed': ['Bilis', 'Velocidad', 'Vitesse', '速度', 'गति', 'السرعة', 'Velocidade'],
    'Length': ['Haba', 'Longitud', 'Longueur', '长度', 'लंबाई', 'الطول', 'Comprimento'],
    'Mass': ['Masa', 'Masa', 'Masse', '质量', 'द्रव्यमान', 'الكتلة', 'Massa'],
    'Area': ['Lawak', 'Área', 'Surface', '面积', 'क्षेत्रफल', 'المساحة', 'Área'],
    'Time': ['Oras', 'Tiempo', 'Temps', '时间', 'समय', 'الوقت', 'Tempo'],
    'Temperature': ['Temperatura', 'Temperatura', 'Température', '温度', 'तापमान', 'درجة الحرارة', 'Temperatura'],
    'Numeral system': ['Sistema ng numero', 'Sistema numérico', 'Système numérique', '进制', 'संख्या प्रणाली', 'النظام العددي', 'Sistema numérico'],
    'BMI': ['BMI', 'IMC', 'IMC', 'BMI', 'बीएमआई', 'مؤشر كتلة الجسم', 'IMC'],
    // ----- Converter: Finance -----
    'Loan': ['Utang', 'Préstamo', 'Prêt', '贷款', 'ऋण', 'قرض', 'Empréstimo'],
    'Simple interest': ['Simpleng interes', 'Interés simple', 'Intérêt simple', '单利', 'साधारण ब्याज', 'فائدة بسيطة', 'Juros simples'],
    'Compound interest': ['Tambalang interes', 'Interés compuesto', 'Intérêt composé', '复利', 'चक्रवृद्धि ब्याज', 'فائدة مركبة', 'Juros compostos'],
    'Tax / VAT': ['Buwis / VAT', 'Impuesto / IVA', 'Taxe / TVA', '税 / 增值税', 'कर / वैट', 'ضريبة / ض.ق.م', 'Imposto / IVA'],
    'Yearly': ['Taun-taon', 'Anual', 'Annuel', '每年', 'वार्षिक', 'سنويًا', 'Anual'],
    'Semi-annual': ['Kada anim na buwan', 'Semestral', 'Semestriel', '每半年', 'अर्धवार्षिक', 'نصف سنوي', 'Semestral'],
    'Quarterly': ['Kada quarter', 'Trimestral', 'Trimestriel', '每季度', 'त्रैमासिक', 'ربع سنوي', 'Trimestral'],
    'Monthly': ['Buwan-buwan', 'Mensual', 'Mensuel', '每月', 'मासिक', 'شهريًا', 'Mensal'],
    'Daily': ['Araw-araw', 'Diario', 'Quotidien', '每天', 'दैनिक', 'يوميًا', 'Diário'],
    'Add tax': ['Magdagdag ng buwis', 'Añadir impuesto', 'Ajouter la taxe', '加税', 'कर जोड़ें', 'إضافة الضريبة', 'Adicionar imposto'],
    'Remove tax': ['Alisin ang buwis', 'Quitar impuesto', 'Retirer la taxe', '去税', 'कर हटाएँ', 'إزالة الضريبة', 'Remover imposto'],
    'Monthly payment': ['Buwanang bayad', 'Pago mensual', 'Mensualité', '月供', 'मासिक भुगतान', 'القسط الشهري', 'Pagamento mensal'],
    'Loan amount': ['Halaga ng utang', 'Monto del préstamo', 'Montant du prêt', '贷款金额', 'ऋण राशि', 'مبلغ القرض', 'Valor do empréstimo'],
    'Interest rate per year': ['Interes kada taon', 'Tasa de interés anual', "Taux d'intérêt annuel", '年利率', 'वार्षिक ब्याज दर', 'معدل الفائدة السنوي', 'Taxa de juros anual'],
    'Term': ['Termino', 'Plazo', 'Durée', '期限', 'अवधि', 'المدة', 'Prazo'],
    'Interest': ['Interes', 'Interés', 'Intérêt', '利息', 'ब्याज', 'الفائدة', 'Juros'],
    'Principal': ['Puhunan', 'Capital', 'Capital', '本金', 'मूलधन', 'المبلغ الأصلي', 'Principal'],
    'Future value': ['Halaga sa hinaharap', 'Valor futuro', 'Valeur future', '终值', 'भविष्य मूल्य', 'القيمة المستقبلية', 'Valor futuro'],
    'Interest earned': ['Kinitang interes', 'Interés ganado', 'Intérêts gagnés', '已赚利息', 'अर्जित ब्याज', 'الفائدة المكتسبة', 'Juros ganhos'],
    'Total with tax': ['Kabuuan kasama ang buwis', 'Total con impuesto', 'Total avec taxe', '含税总额', 'कर सहित कुल', 'الإجمالي مع الضريبة', 'Total com imposto'],
    'Price without tax': ['Presyo na walang buwis', 'Precio sin impuesto', 'Prix hors taxe', '不含税价格', 'कर रहित मूल्य', 'السعر بدون ضريبة', 'Preço sem imposto'],
    'Amount': ['Halaga', 'Importe', 'Montant', '金额', 'राशि', 'المبلغ', 'Valor'],
    'Tax rate': ['Rate ng buwis', 'Tasa de impuesto', 'Taux de taxe', '税率', 'कर दर', 'معدل الضريبة', 'Taxa de imposto'],
    'Tax': ['Buwis', 'Impuesto', 'Taxe', '税', 'कर', 'الضريبة', 'Imposto'],
    'Amount without tax': ['Halaga na walang buwis', 'Importe sin impuesto', 'Montant hors taxe', '不含税金额', 'कर रहित राशि', 'المبلغ بدون ضريبة', 'Valor sem imposto'],
    'Amount with tax': ['Halaga kasama ang buwis', 'Importe con impuesto', 'Montant avec taxe', '含税金额', 'कर सहित राशि', 'المبلغ مع الضريبة', 'Valor com imposto'],
    'Total payment': ['Kabuuang bayad', 'Pago total', 'Paiement total', '总还款额', 'कुल भुगतान', 'إجمالي الدفع', 'Pagamento total'],
    'Total interest': ['Kabuuang interes', 'Interés total', 'Intérêts totaux', '总利息', 'कुल ब्याज', 'إجمالي الفائدة', 'Juros totais'],
    'Total amount': ['Kabuuang halaga', 'Importe total', 'Montant total', '总金额', 'कुल राशि', 'المبلغ الإجمالي', 'Valor total'],
    // ----- Converter: Date -----
    'Date difference': ['Pagkakaiba ng petsa', 'Diferencia de fechas', 'Écart entre dates', '日期差', 'तारीख़ का अंतर', 'الفرق بين التواريخ', 'Diferença de datas'],
    'Add / subtract': ['Idagdag / ibawas', 'Sumar / restar', 'Ajouter / soustraire', '加 / 减', 'जोड़ें / घटाएँ', 'إضافة / طرح', 'Somar / subtrair'],
    'Difference': ['Pagkakaiba', 'Diferencia', 'Écart', '差值', 'अंतर', 'الفرق', 'Diferença'],
    'From': ['Mula', 'Desde', 'De', '从', 'से', 'من', 'De'],
    'To': ['Hanggang', 'Hasta', 'À', '至', 'तक', 'إلى', 'Até'],
    'Result date': ['Petsa ng resulta', 'Fecha resultante', 'Date obtenue', '结果日期', 'परिणाम तारीख़', 'تاريخ النتيجة', 'Data resultante'],
    'Start date': ['Petsa ng simula', 'Fecha de inicio', 'Date de début', '开始日期', 'प्रारंभ तिथि', 'تاريخ البدء', 'Data de início'],
    'Add': ['Idagdag', 'Sumar', 'Ajouter', '加', 'जोड़ें', 'إضافة', 'Somar'],
    'Subtract': ['Ibawas', 'Restar', 'Soustraire', '减', 'घटाएँ', 'طرح', 'Subtrair'],
    'Years': ['Mga taon', 'Años', 'Années', '年', 'वर्ष', 'سنوات', 'Anos'],
    'Months': ['Mga buwan', 'Meses', 'Mois', '月', 'महीने', 'أشهر', 'Meses'],
    'Days': ['Mga araw', 'Días', 'Jours', '天', 'दिन', 'أيام', 'Dias'],
    'Weekday': ['Araw ng linggo', 'Día de la semana', 'Jour de la semaine', '星期', 'सप्ताह का दिन', 'يوم الأسبوع', 'Dia da semana'],
    'Days from start': ['Araw mula sa simula', 'Días desde el inicio', 'Jours depuis le début', '距开始天数', 'आरंभ से दिन', 'أيام منذ البداية', 'Dias desde o início'],
    'Total days': ['Kabuuang araw', 'Días totales', 'Total de jours', '总天数', 'कुल दिन', 'إجمالي الأيام', 'Total de dias'],
    'Weeks': ['Mga linggo', 'Semanas', 'Semaines', '周数', 'सप्ताह', 'أسابيع', 'Semanas'],
    'Total months': ['Kabuuang buwan', 'Meses totales', 'Total de mois', '总月数', 'कुल महीने', 'إجمالي الأشهر', 'Total de meses'],
    // ----- Converter: Discount -----
    'Original price': ['Orihinal na presyo', 'Precio original', 'Prix initial', '原价', 'मूल कीमत', 'السعر الأصلي', 'Preço original'],
    'Extra discount (optional)': ['Dagdag na diskwento (opsyonal)', 'Descuento extra (opcional)', 'Remise supplémentaire (facultatif)', '额外折扣（可选）', 'अतिरिक्त छूट (वैकल्पिक)', 'خصم إضافي (اختياري)', 'Desconto extra (opcional)'],
    'Tax (optional)': ['Buwis (opsyonal)', 'Impuesto (opcional)', 'Taxe (facultatif)', '税（可选）', 'कर (वैकल्पिक)', 'الضريبة (اختياري)', 'Imposto (opcional)'],
    'Final price': ['Pinal na presyo', 'Precio final', 'Prix final', '最终价格', 'अंतिम कीमत', 'السعر النهائي', 'Preço final'],
    'You save': ['Natipid mo', 'Ahorras', 'Vous économisez', '你节省', 'आपकी बचत', 'توفّر', 'Você economiza'],
    'Total discount': ['Kabuuang diskwento', 'Descuento total', 'Remise totale', '总折扣', 'कुल छूट', 'إجمالي الخصم', 'Desconto total'],
    'Price after discount': ['Presyo pagkatapos ng diskwento', 'Precio tras el descuento', 'Prix après remise', '折后价格', 'छूट के बाद कीमत', 'السعر بعد الخصم', 'Preço após desconto'],
    // ----- Converter: BMI -----
    'Metric': ['Metric', 'Métrico', 'Métrique', '公制', 'मीट्रिक', 'متري', 'Métrico'],
    'Imperial': ['Imperial', 'Imperial', 'Impérial', '英制', 'इंपीरियल', 'إمبراطوري', 'Imperial'],
    'Height': ['Taas', 'Altura', 'Taille', '身高', 'ऊँचाई', 'الطول', 'Altura'],
    'Weight': ['Timbang', 'Peso', 'Poids', '体重', 'वज़न', 'الوزن', 'Peso'],
    'Inches': ['Pulgada', 'Pulgadas', 'Pouces', '英寸', 'इंच', 'بوصات', 'Polegadas'],
    'Your BMI': ['Iyong BMI', 'Tu IMC', 'Votre IMC', '你的 BMI', 'आपका बीएमआई', 'مؤشر كتلة جسمك', 'Seu IMC'],
    'Underweight': ['Kulang sa timbang', 'Bajo peso', 'Insuffisance pondérale', '体重过轻', 'कम वज़न', 'نقص الوزن', 'Abaixo do peso'],
    'Normal weight': ['Normal na timbang', 'Peso normal', 'Poids normal', '体重正常', 'सामान्य वज़न', 'وزن طبيعي', 'Peso normal'],
    'Overweight': ['Sobra sa timbang', 'Sobrepeso', 'Surpoids', '超重', 'अधिक वज़न', 'زيادة الوزن', 'Sobrepeso'],
    'Obese': ['Obese', 'Obesidad', 'Obésité', '肥胖', 'मोटापा', 'سمنة', 'Obesidade'],
    'Healthy weight range': ['Malusog na saklaw ng timbang', 'Rango de peso saludable', 'Plage de poids sain', '健康体重范围', 'स्वस्थ वज़न सीमा', 'نطاق الوزن الصحي', 'Faixa de peso saudável'],
    // ----- Converter: Numeral system -----
    'Binary': ['Binary', 'Binario', 'Binaire', '二进制', 'बाइनरी', 'ثنائي', 'Binário'],
    'Octal': ['Octal', 'Octal', 'Octal', '八进制', 'ऑक्टल', 'ثماني', 'Octal'],
    'Decimal': ['Decimal', 'Decimal', 'Décimal', '十进制', 'दशमलव', 'عشري', 'Decimal'],
    'Hexadecimal': ['Hexadecimal', 'Hexadecimal', 'Hexadécimal', '十六进制', 'हेक्साडेसिमल', 'سداسي عشري', 'Hexadecimal'],
  };
  
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
      'Search Wallet': 'Hanapin sa Wallet', 'Income': 'Kita',
      'Expense': 'Gastos', 'Transfer': 'Paglipat', 'Reminder': 'Paalala',
      'My Accounts': 'Aking mga Account', 'Total Balance': 'Kabuuang Balanse',
      'History': 'Kasaysayan', 'Analytics': 'Analytics',
      'App Security': 'Seguridad ng App', 'Unlock': 'I-unlock',
      'Wallet is locked': 'Naka-lock ang Wallet',
      'Unlock Wallet': 'I-unlock ang Wallet',
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
      'Search Wallet': 'Buscar en Wallet', 'Income': 'Ingresos',
      'Expense': 'Gastos', 'Transfer': 'Transferencia',
      'Reminder': 'Recordatorio', 'My Accounts': 'Mis cuentas',
      'Total Balance': 'Saldo total', 'History': 'Historial',
      'Analytics': 'Analíticas', 'App Security': 'Seguridad de la app',
      'Unlock': 'Desbloquear', 'Wallet is locked': 'Wallet está bloqueado',
      'Unlock Wallet': 'Desbloquear Wallet',
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
      'Search Wallet': 'Rechercher dans Wallet', 'Income': 'Revenus',
      'Expense': 'Dépenses', 'Transfer': 'Virement', 'Reminder': 'Rappel',
      'My Accounts': 'Mes comptes', 'Total Balance': 'Solde total',
      'History': 'Historique', 'Analytics': 'Analyses',
      'App Security': "Sécurité de l'app", 'Unlock': 'Déverrouiller',
      'Wallet is locked': 'Wallet est verrouillé',
      'Unlock Wallet': 'Déverrouiller Wallet',
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
      'Search Wallet': '搜索 Wallet', 'Income': '收入',
      'Expense': '支出', 'Transfer': '转账', 'Reminder': '提醒',
      'My Accounts': '我的账户', 'Total Balance': '总余额',
      'History': '历史记录', 'Analytics': '数据分析',
      'App Security': '应用安全', 'Unlock': '解锁',
      'Wallet is locked': 'Wallet 已锁定',
      'Unlock Wallet': '解锁 Wallet',
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
      'Search Wallet': 'Wallet में खोजें', 'Income': 'आय',
      'Expense': 'खर्च', 'Transfer': 'ट्रांसफ़र', 'Reminder': 'रिमाइंडर',
      'My Accounts': 'मेरे खाते', 'Total Balance': 'कुल शेष',
      'History': 'इतिहास', 'Analytics': 'विश्लेषण',
      'App Security': 'ऐप सुरक्षा', 'Unlock': 'अनलॉक करें',
      'Wallet is locked': 'Wallet लॉक है',
      'Unlock Wallet': 'Wallet अनलॉक करें',
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
      'Search Wallet': 'البحث في Wallet', 'Income': 'الدخل',
      'Expense': 'المصروفات', 'Transfer': 'تحويل', 'Reminder': 'تذكير',
      'My Accounts': 'حساباتي', 'Total Balance': 'الرصيد الإجمالي',
      'History': 'السجل', 'Analytics': 'التحليلات',
      'App Security': 'أمان التطبيق', 'Unlock': 'فتح القفل',
      'Wallet is locked': 'Wallet مقفل',
      'Unlock Wallet': 'فتح قفل Wallet',
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
      'Search Wallet': 'Buscar no Wallet', 'Income': 'Receitas',
      'Expense': 'Despesas', 'Transfer': 'Transferência',
      'Reminder': 'Lembrete', 'My Accounts': 'Minhas contas',
      'Total Balance': 'Saldo total', 'History': 'Histórico',
      'Analytics': 'Análises', 'App Security': 'Segurança do app',
      'Unlock': 'Desbloquear', 'Wallet is locked': 'O Wallet está bloqueado',
      'Unlock Wallet': 'Desbloquear o Wallet',
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
  static const String appName = 'Wallet';
  static const String appVersion = '1.0.0'; // keep in sync with pubspec.yaml
  static const String databaseName = 'Wallet.db';
  static const int databaseVersion = 1;
  static const String logoAsset = 'assets/images/wallet_logo.png';

  // ---------- About / contact (EDIT THESE 3) ----------
  static const String developerName = 'Kelsen Gile';
  static const String developerEmail = 'kelsengile.dev@gmail.com';
  static const String repositoryUrl = 'https://github.com/kelsengile/wallet';

  // ---------- Notifications ----------
  static const String prefNotifPush = 'settings.notif.push';
  static const String prefNotifReminders = 'settings.notif.reminders';
  static const String prefNotifBudget = 'settings.notif.budget';
  static const String prefNotifSummary = 'settings.notif.summary';
  static const String prefNotifSound = 'settings.notif.sound';
  static const String prefNotifVibration = 'settings.notif.vibration';

  /// Daily summary time (24h, in the app's Location time).
  static const int notifySummaryHour = 20;

  /// Budget alert starts at this share of the budget (and again at 100%).
  static const double budgetWarnRatio = 0.8;

  // ---------- Database ----------
  static const String schemaAsset = 'lib/database/schema.sql';
  static const String seedAsset = 'lib/database/seed.sql';

  /// Written into backup files and checked again on import.
  static const String exportApp = 'Wallet';
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

  static const String prefProfile = 'profile.data';
  static const String profileFolder = 'profile';

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

  static const String prefFontLibrary = 'fonts.library'; // imported fonts
  static const String fontFolder = 'fonts';
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