import 'package:flutter/widgets.dart';
import 'package:surlor_ai/generated/l10n/l10n.dart';
import 'package:surlor_ai/generated/l10n/l10n_en.dart';

AppLocalizations l10n = AppLocalizationsEn();

extension LocaleX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
