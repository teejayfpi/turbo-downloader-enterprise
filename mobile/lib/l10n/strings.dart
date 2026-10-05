import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Locale-aware strings for the app.
///
/// A small, dependency-free lookup keeps the string table in one place and
/// avoids generated code. Keys are grouped by screen. Adding a language means
/// adding one map below and one entry to [supportedLocales].
class TurboStrings {
  final Locale locale;
  const TurboStrings(this.locale);

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
    Locale('yo'),
  ];

  static const localeNames = <String, String>{
    'en': 'English',
    'fr': 'Français',
    'yo': 'Yorùbá',
  };

  static TurboStrings of(BuildContext context) =>
      Localizations.of<TurboStrings>(context, TurboStrings) ??
      const TurboStrings(Locale('en'));

  String _t(String key) {
    final table = _tables[locale.languageCode] ?? _tables['en']!;
    return table[key] ?? _tables['en']![key] ?? key;
  }

  // Navigation
  String get tabDownloads => _t('tab.downloads');
  String get tabAdd => _t('tab.add');
  String get tabBrowse => _t('tab.browse');
  String get tabHistory => _t('tab.history');
  String get tabSettings => _t('tab.settings');

  // Common actions
  String get actionRetry => _t('action.retry');
  String get actionShare => _t('action.share');
  String get actionOpen => _t('action.open');
  String get actionReveal => _t('action.reveal');
  String get actionDelete => _t('action.delete');
  String get actionCancel => _t('action.cancel');
  String get actionCopy => _t('action.copy');
  String get actionSave => _t('action.save');
  String get actionExport => _t('action.export');
  String get actionClose => _t('action.close');
  String get actionNext => _t('action.next');
  String get actionBack => _t('action.back');
  String get actionDone => _t('action.done');
  String get actionSkip => _t('action.skip');

  // Downloads
  String get queueEmpty => _t('downloads.empty');
  String get pauseAll => _t('downloads.pauseAll');
  String get resumeAll => _t('downloads.resumeAll');
  String get clearCompleted => _t('downloads.clearCompleted');
  String get cancelAll => _t('downloads.cancelAll');
  String get statActive => _t('downloads.statActive');
  String get statSpeed => _t('downloads.statSpeed');
  String get statDone => _t('downloads.statDone');
  String get statTotal => _t('downloads.statTotal');

  // Statuses
  String get statusQueued => _t('status.queued');
  String get statusPreparing => _t('status.preparing');
  String get statusDownloading => _t('status.downloading');
  String get statusPaused => _t('status.paused');
  String get statusFailed => _t('status.failed');
  String get statusCompleted => _t('status.completed');

  // History
  String get historyTitle => _t('history.title');
  String get historyEmpty => _t('history.empty');
  String get historySearchHint => _t('history.searchHint');
  String get historyExportCsv => _t('history.exportCsv');
  String get historyExportJson => _t('history.exportJson');
  String get historyClearAll => _t('history.clearAll');
  String get historyFilterDate => _t('history.filterDate');
  String get historyAllTime => _t('history.allTime');
  String get historyToday => _t('history.today');
  String get historyWeek => _t('history.week');
  String get historyMonth => _t('history.month');

  // Storage
  String get storageTitle => _t('storage.title');
  String get storageAvailable => _t('storage.available');
  String get storageDownloaded => _t('storage.downloaded');
  String get storageTemporary => _t('storage.temporary');
  String get storageAppData => _t('storage.appData');
  String get storageCleanup => _t('storage.cleanup');
  String get storageLowWarning => _t('storage.lowWarning');
  String get storageCriticalWarning => _t('storage.criticalWarning');

  // Errors / diagnostics
  String get errorDetails => _t('error.details');
  String get errorCopyDetails => _t('error.copyDetails');
  String get diagnosticsTitle => _t('diagnostics.title');
  String get diagnosticsExport => _t('diagnostics.export');

  // Onboarding
  String get onboardingSkip => _t('onboarding.skip');
  String get onboardingNext => _t('onboarding.next');
  String get onboardingStart => _t('onboarding.start');

  static const Map<String, Map<String, String>> _tables = {
    'en': {
      'tab.downloads': 'Downloads',
      'tab.add': 'Add',
      'tab.browse': 'Browse',
      'tab.history': 'History',
      'tab.settings': 'Settings',
      'action.retry': 'Retry',
      'action.share': 'Share',
      'action.open': 'Open',
      'action.reveal': 'Show in folder',
      'action.delete': 'Delete',
      'action.cancel': 'Cancel',
      'action.copy': 'Copy',
      'action.save': 'Save',
      'action.export': 'Export',
      'action.close': 'Close',
      'action.next': 'Next',
      'action.back': 'Back',
      'action.done': 'Done',
      'action.skip': 'Skip',
      'downloads.empty': 'Open the Add tab to start a transfer.',
      'downloads.pauseAll': 'Pause all',
      'downloads.resumeAll': 'Resume all',
      'downloads.clearCompleted': 'Clear done',
      'downloads.cancelAll': 'Cancel all',
      'downloads.statActive': 'Active',
      'downloads.statSpeed': 'Speed',
      'downloads.statDone': 'Done',
      'downloads.statTotal': 'Total',
      'status.queued': 'Queued',
      'status.preparing': 'Preparing',
      'status.downloading': 'Downloading',
      'status.paused': 'Paused',
      'status.failed': 'Failed',
      'status.completed': 'Completed',
      'history.title': 'Download history',
      'history.empty': 'Nothing here yet. Finished and failed transfers appear here.',
      'history.searchHint': 'Search name, URL, or folder',
      'history.exportCsv': 'Export CSV',
      'history.exportJson': 'Export JSON',
      'history.clearAll': 'Clear history',
      'history.filterDate': 'Date',
      'history.allTime': 'All time',
      'history.today': 'Today',
      'history.week': 'Last 7 days',
      'history.month': 'Last 30 days',
      'storage.title': 'Storage',
      'storage.available': 'Available',
      'storage.downloaded': 'Downloaded',
      'storage.temporary': 'Temporary',
      'storage.appData': 'App data',
      'storage.cleanup': 'Clean up partial files',
      'storage.lowWarning': 'Storage is running low. Free up space soon.',
      'storage.criticalWarning': 'Storage is critically low. Downloads may fail.',
      'error.details': 'Technical details',
      'error.copyDetails': 'Copy details',
      'diagnostics.title': 'Diagnostics',
      'diagnostics.export': 'Export diagnostics',
      'onboarding.skip': 'Skip',
      'onboarding.next': 'Next',
      'onboarding.start': 'Start downloading',
    },
    'fr': {
      'tab.downloads': 'Téléchargements',
      'tab.add': 'Ajouter',
      'tab.browse': 'Explorer',
      'tab.history': 'Historique',
      'tab.settings': 'Réglages',
      'action.retry': 'Réessayer',
      'action.share': 'Partager',
      'action.open': 'Ouvrir',
      'action.reveal': 'Afficher le dossier',
      'action.delete': 'Supprimer',
      'action.cancel': 'Annuler',
      'action.copy': 'Copier',
      'action.save': 'Enregistrer',
      'action.export': 'Exporter',
      'action.close': 'Fermer',
      'action.next': 'Suivant',
      'action.back': 'Retour',
      'action.done': 'Terminé',
      'action.skip': 'Passer',
      'downloads.empty': 'Ouvrez l\'onglet Ajouter pour lancer un transfert.',
      'downloads.pauseAll': 'Tout mettre en pause',
      'downloads.resumeAll': 'Tout reprendre',
      'downloads.clearCompleted': 'Effacer terminés',
      'downloads.cancelAll': 'Tout annuler',
      'downloads.statActive': 'Actifs',
      'downloads.statSpeed': 'Vitesse',
      'downloads.statDone': 'Terminés',
      'downloads.statTotal': 'Total',
      'status.queued': 'En attente',
      'status.preparing': 'Préparation',
      'status.downloading': 'Téléchargement',
      'status.paused': 'En pause',
      'status.failed': 'Échoué',
      'status.completed': 'Terminé',
      'history.title': 'Historique',
      'history.empty':
          'Rien pour l\'instant. Les transferts terminés et échoués apparaissent ici.',
      'history.searchHint': 'Rechercher un nom, une URL ou un dossier',
      'history.exportCsv': 'Exporter CSV',
      'history.exportJson': 'Exporter JSON',
      'history.clearAll': 'Effacer l\'historique',
      'history.filterDate': 'Date',
      'history.allTime': 'Tout',
      'history.today': 'Aujourd\'hui',
      'history.week': '7 derniers jours',
      'history.month': '30 derniers jours',
      'storage.title': 'Stockage',
      'storage.available': 'Disponible',
      'storage.downloaded': 'Téléchargé',
      'storage.temporary': 'Temporaire',
      'storage.appData': 'Données de l\'app',
      'storage.cleanup': 'Nettoyer les fichiers partiels',
      'storage.lowWarning': 'Espace faible. Libérez bientôt de l\'espace.',
      'storage.criticalWarning':
          'Espace critique. Les téléchargements peuvent échouer.',
      'error.details': 'Détails techniques',
      'error.copyDetails': 'Copier les détails',
      'diagnostics.title': 'Diagnostic',
      'diagnostics.export': 'Exporter le diagnostic',
      'onboarding.skip': 'Passer',
      'onboarding.next': 'Suivant',
      'onboarding.start': 'Commencer',
    },
    'yo': {
      'tab.downloads': 'Ìgbasílẹ̀',
      'tab.add': 'Fikún',
      'tab.browse': 'Ṣàwárí',
      'tab.history': 'Ìtàn',
      'tab.settings': 'Ètò',
      'action.retry': 'Gbìyànjú',
      'action.share': 'Pín',
      'action.open': 'Ṣí',
      'action.reveal': 'Fi fóldà hàn',
      'action.delete': 'Paarẹ́',
      'action.cancel': 'Fagilé',
      'action.copy': 'Dàkọ',
      'action.save': 'Fi pamọ́',
      'action.export': 'Gbé jáde',
      'action.close': 'Ti',
      'action.next': 'Tókàn',
      'action.back': 'Padà',
      'action.done': 'Ó ti parí',
      'action.skip': 'Fò ó',
      'downloads.empty': 'Ṣí ẹ̀ka Fikún láti bẹ̀rẹ̀ ìgbasílẹ̀.',
      'downloads.pauseAll': 'Dúró gbogbo rẹ̀',
      'downloads.resumeAll': 'Tẹ̀síwájú gbogbo rẹ̀',
      'downloads.clearCompleted': 'Nu tí ó parí',
      'downloads.cancelAll': 'Fagilé gbogbo rẹ̀',
      'downloads.statActive': 'Ńṣiṣẹ́',
      'downloads.statSpeed': 'Ìyára',
      'downloads.statDone': 'Ó parí',
      'downloads.statTotal': 'Àpapọ̀',
      'status.queued': 'Nínú ìlà',
      'status.preparing': 'Ńmúra',
      'status.downloading': 'Ńgbasílẹ̀',
      'status.paused': 'Dúró',
      'status.failed': 'Kùnà',
      'status.completed': 'Ó parí',
      'history.title': 'Ìtàn ìgbasílẹ̀',
      'history.empty':
          'Kò sí nǹkan níbí. Àwọn tí ó parí àti tí ó kùnà yóò hàn níbí.',
      'history.searchHint': 'Wá orúkọ, URL, tàbí fóldà',
      'history.exportCsv': 'Gbé CSV jáde',
      'history.exportJson': 'Gbé JSON jáde',
      'history.clearAll': 'Nu ìtàn',
      'history.filterDate': 'Ọjọ́',
      'history.allTime': 'Gbogbo àkókò',
      'history.today': 'Òní',
      'history.week': 'Ọjọ́ 7 sẹ́yìn',
      'history.month': 'Ọjọ́ 30 sẹ́yìn',
      'storage.title': 'Ibìpamọ́',
      'storage.available': 'Ó wà',
      'storage.downloaded': 'Tí a gbasílẹ̀',
      'storage.temporary': 'Ìgbà díẹ̀',
      'storage.appData': 'Dátà app',
      'storage.cleanup': 'Nu àwọn fáìlì àárọ̀',
      'storage.lowWarning': 'Ibìpamọ́ kéré. Nu ibìpamọ́ láìpẹ́.',
      'storage.criticalWarning':
          'Ibìpamọ́ kéré gan. Ìgbasílẹ̀ lè kùnà.',
      'error.details': 'Àlàyé ìmọ̀ ẹ̀rọ',
      'error.copyDetails': 'Dàkọ àlàyé',
      'diagnostics.title': 'Àyẹ̀wò',
      'diagnostics.export': 'Gbé àyẹ̀wò jáde',
      'onboarding.skip': 'Fò ó',
      'onboarding.next': 'Tókàn',
      'onboarding.start': 'Bẹ̀rẹ̀ ìgbasílẹ̀',
    },
  };
}

/// Wires [TurboStrings] into Flutter's localization system.
class TurboStringsDelegate extends LocalizationsDelegate<TurboStrings> {
  const TurboStringsDelegate();

  @override
  bool isSupported(Locale locale) => TurboStrings.supportedLocales
      .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<TurboStrings> load(Locale locale) =>
      SynchronousFuture(TurboStrings(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<TurboStrings> old) => false;
}
