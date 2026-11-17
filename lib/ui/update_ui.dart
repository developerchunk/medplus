import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/unsaved_work.dart';
import '../core/updater.dart';
import 'nav.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Thin bar over the pages when a downloaded update is waiting for a restart.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});
  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _later = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Updater.instance,
      builder: (context, _) {
        final u = Updater.instance;
        final show = (u.stage == UpdateStage.ready || u.stage == UpdateStage.installing) && !_later;
        if (!show) return const SizedBox.shrink();
        return Material(
          color: AppColors.info.withValues(alpha: context.isDark ? 0.22 : 0.1),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.system_update_alt, color: AppColors.info, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'A new version of MedBillings (${u.latest}) is ready. Restart to start using it — nothing you saved is lost.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (u.releaseNotes.isNotEmpty) TextButton(onPressed: () => showReleaseNotes(context), child: const Text("What's new")),
                TextButton(onPressed: () => setState(() => _later = true), child: const Text('Later')),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: u.stage == UpdateStage.installing ? null : () => restartToUpdate(context),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Restart & update'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> showReleaseNotes(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("What's new in ${Updater.instance.latest}"),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: SelectableText(Updater.instance.releaseNotes))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );

/// Asks the user to finish unsaved work, installs the update and restarts the app.
Future<void> restartToUpdate(BuildContext context) async {
  final u = Updater.instance;
  if (!u.ready) return;
  final pending = UnsavedWork.pending();
  if (pending.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.edit_note, color: AppColors.warning, size: 32),
        title: const Text('Finish this first'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MedBillings will close for a few seconds to update. Save or clear this work before restarting:'),
              const SizedBox(height: 12),
              for (final w in pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.circle, size: 8, color: AppColors.warning),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${w.where}: ',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: w.message),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Nav.go(pending.first.page);
            },
            child: Text('Go to ${pending.first.where}'),
          ),
        ],
      ),
    );
    return;
  }
  if (!context.mounted) return;
  final go = await confirm(
    context,
    title: 'Restart & update?',
    message: 'MedBillings will close, install version ${u.latest} and open again in a few seconds. '
        'All bills, stock and settings are already saved.',
    confirmLabel: 'Restart now',
  );
  if (!go || !context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('Installing the update… MedBillings will reopen by itself.')),
        ],
      ),
    ),
  );
  final err = await u.install();
  if (err == null) await u.relaunch();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  showSnack(context, err, error: true);
}

/// "App updates" box for the Settings page.
class UpdateSettingsCard extends StatelessWidget {
  const UpdateSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Updater.instance,
      builder: (context, _) {
        final u = Updater.instance;
        final busy = u.stage == UpdateStage.checking || u.stage == UpdateStage.downloading || u.stage == UpdateStage.installing;
        final status = switch (u.stage) {
          _ when !u.supported => 'Automatic updates work on the installed Linux app (the shop PC).',
          UpdateStage.checking => 'Checking for updates…',
          UpdateStage.downloading => 'Downloading version ${u.latest}… ${(u.progress * 100).round()}%',
          UpdateStage.ready => 'Version ${u.latest} is downloaded and ready to install.',
          UpdateStage.installing => 'Installing…',
          UpdateStage.upToDate => 'You have the latest version.',
          UpdateStage.failed => 'Could not check: ${u.error ?? 'unknown error'}',
          UpdateStage.idle => 'Checks automatically every few hours when the internet is on.',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Installed version', style: TextStyle(color: context.muted)),
                const Spacer(),
                Text(u.currentLabel.isEmpty ? '—' : u.currentLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (busy) ...[const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10)],
                Expanded(
                  child: Text(status, style: TextStyle(color: u.stage == UpdateStage.failed ? AppColors.danger : null)),
                ),
              ],
            ),
            if (u.ready && u.error != null) ...[const SizedBox(height: 6), Text(u.error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))],
            if (u.lastChecked != null) ...[
              const SizedBox(height: 4),
              Text('Last checked ${fmtDateTime(u.lastChecked!)}', style: TextStyle(color: context.muted, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: !u.supported || busy ? null : () => u.check(manual: true),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check for updates'),
                ),
                if (u.ready)
                  FilledButton.icon(
                    onPressed: () => restartToUpdate(context),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Restart & update'),
                  ),
                if (u.ready && u.releaseNotes.isNotEmpty) TextButton(onPressed: () => showReleaseNotes(context), child: const Text("What's new")),
              ],
            ),
          ],
        );
      },
    );
  }
}
