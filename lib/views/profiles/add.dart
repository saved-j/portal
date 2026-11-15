import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/profiles/custom/custom.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adding a subscription: one sheet, every way in visible at once.
///
/// The menu used to hide the link field, the file picker and the scanner behind three
/// taps on a popup. A person adding a subscription knows what they have — a link, a file
/// or a code — so the field, the paste key, the file key, the scanner and the Add button
/// all sit on the same screen and cost exactly one tap.
class AddProfileMenu extends ConsumerWidget {
  const AddProfileMenu({super.key, required this.builder});

  final Widget Function(PopupOpen open) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (innerContext) => builder(
        () => unawaited(_openSheet(innerContext, ref)),
      ),
    );
  }
}

Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _AddProfileSheet(),
  );
}

class _AddProfileSheet extends ConsumerWidget {
  const _AddProfileSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AddProfileForm(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      showTitle: true,
      onDone: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
  }
}

/// The subscription form itself: link field, paste, file, scanner, Add underneath.
///
/// It lives on the empty start screen as well as in a sheet, because a person who has
/// just installed the app should not have to press "Add profile" to discover that there
/// is something to add.
class AddProfileForm extends ConsumerStatefulWidget {
  const AddProfileForm({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
    this.showTitle = false,
    this.hint,
    this.onDone,
  });

  final EdgeInsets padding;
  final bool showTitle;

  /// A line above the field, used on the start screen to say what the field wants.
  final String? hint;
  final VoidCallback? onDone;

  @override
  ConsumerState<AddProfileForm> createState() => _AddProfileFormState();
}

class _AddProfileFormState extends ConsumerState<AddProfileForm> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(profilesActionProvider.notifier).addProfileFormFile();
    if (mounted) {
      setState(() => _busy = false);
      (widget.onDone ?? () => Navigator.of(context).pop())();
    }
  }

  Future<void> _scan() async {
    final url = await BaseNavigator.push<String>(context, const ScanPage());
    if (!mounted || url == null) return;
    setState(() {
      _controller.text = url;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final appLocalizations = context.appLocalizations;
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = appLocalizations.emptyTip(appLocalizations.link));
      return;
    }
    if (!value.isUrl && !value.isShareLink) {
      setState(() => _error = appLocalizations.invalidLinkTip);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await ref.read(profilesActionProvider.notifier).addProfileFromLink(value);
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
      return;
    }
    // Added from the start screen: the subscription is in, so go where it is used. Leaving
    // the form on screen would make the person look for a way forward themselves.
    ref.read(currentPageLabelProvider.notifier).toPage(PageLabel.dashboard);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final theme = Theme.of(context);
    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle) ...[
            Text(
              appLocalizations.addProfile,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: widget.hint ?? appLocalizations.insertSubscriptionLink,
                    errorText: _error,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Every way in, side by side with the field: paste, file, code.
              IconButton.filledTonal(
                tooltip: appLocalizations.paste,
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
              ),
              IconButton.filledTonal(
                tooltip: appLocalizations.file,
                onPressed: _busy ? null : _pickFile,
                icon: const GlyphIcon(AppGlyphs.importFile),
              ),
              IconButton.filledTonal(
                tooltip: appLocalizations.qrcode,
                onPressed: _scan,
                icon: const GlyphIcon(AppGlyphs.qrCode),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CommonCircleLoading(),
                  )
                : Text(appLocalizations.add),
          ),
          const SizedBox(height: 8),
          if (widget.showTitle)
            TextButton(
            onPressed: _busy
                ? null
                : () {
                    final profileId = ref
                        .read(profilesActionProvider.notifier)
                        .addCustomProfile(appLocalizations.unnamed);
                    Navigator.of(context).pop();
                    unawaited(
                      BaseNavigator.push(
                        context,
                        CustomProfileView(profileId: profileId, isNew: true),
                      ),
                    );
                  },
            child: Text(appLocalizations.customProfile),
          ),
        ],
      ),
    );
  }
}

class _SendFromPhoneDialog extends StatefulWidget {
  const _SendFromPhoneDialog();

  @override
  State<_SendFromPhoneDialog> createState() => _SendFromPhoneDialogState();
}

class _SendFromPhoneDialogState extends State<_SendFromPhoneDialog> {
  LinkReceiver? _receiver;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final appLocalizations = currentAppLocalizations;
    final receiver = await LinkReceiver.start((
      title: appLocalizations.sendFromPhonePageTitle,
      hint: appLocalizations.sendFromPhonePageHint,
      send: appLocalizations.send,
      sent: appLocalizations.sendFromPhonePageSent,
      invalid: appLocalizations.invalidLinkTip,
    )).catchError((Object _) => null);
    if (!mounted) {
      unawaited(receiver?.close());
      return;
    }
    setState(() {
      _receiver = receiver;
      _failed = receiver == null;
    });
    final link = await receiver?.link;
    if (link != null && mounted) {
      Navigator.of(context).pop(link);
    }
  }

  @override
  void dispose() {
    unawaited(_receiver?.close());
    super.dispose();
  }

  Widget _buildContent(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    if (_failed) {
      return Text(
        appLocalizations.sendFromPhoneNoNetwork,
        textAlign: TextAlign.center,
      );
    }
    final address = _receiver?.address.toString();
    if (address == null) {
      return const SizedBox.square(
        dimension: 96,
        child: Center(child: CommonCircleLoading()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        QrCodeView(data: address, size: 200),
        SelectableText(address, textAlign: TextAlign.center),
        Text(appLocalizations.sendFromPhoneTip, textAlign: TextAlign.center),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.appLocalizations.sendFromPhone,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.appLocalizations.cancel),
        ),
      ],
      child: _buildContent(context),
    );
  }
}
