import 'package:flutter/material.dart';

import '../services/switch_service.dart';
import '../theme/app_theme.dart';

/// How a switch state is shown: the headline, and whether it's good news,
/// a warning, or a problem.
enum SwitchSeverity { good, warning, problem, working }

class SwitchStateText {
  final String headline;
  final SwitchSeverity severity;
  const SwitchStateText(this.headline, this.severity);
}

/// The wording for each [SwitchState]. [changedAt] is shown for "enabled".
SwitchStateText describeSwitchState(SwitchStatus status) {
  switch (status.state) {
    case SwitchState.pending:
      return const SwitchStateText(
        'Checking the switch...',
        SwitchSeverity.working,
      );
    case SwitchState.ok:
      return const SwitchStateText(
        'Multicast (IGMP) is set up correctly',
        SwitchSeverity.good,
      );
    case SwitchState.enabled:
      final at = status.changedAt;
      return SwitchStateText(
        at == null
            ? 'The SC-1 just turned IGMP on'
            : 'The SC-1 just turned IGMP on at ${_clock(at)}',
        SwitchSeverity.good,
      );
    case SwitchState.unsaved:
      return const SwitchStateText(
        'On, but not saved on the switch yet; will retry',
        SwitchSeverity.warning,
      );
    case SwitchState.unverified:
      return const SwitchStateText(
        "Couldn't read every setting",
        SwitchSeverity.warning,
      );
    case SwitchState.failed:
      return const SwitchStateText(
        "Couldn't set up the switch",
        SwitchSeverity.problem,
      );
    case SwitchState.unreachable:
      return const SwitchStateText(
        "Can't reach the switch",
        SwitchSeverity.problem,
      );
    case SwitchState.authFailed:
      return const SwitchStateText(
        'The switch rejected the password',
        SwitchSeverity.problem,
      );
    case SwitchState.needsPassword:
      return const SwitchStateText(
        'The switch wants a new password',
        SwitchSeverity.problem,
      );
    case SwitchState.notConfigured:
      return const SwitchStateText(
        'No managed switch on this SC-1',
        SwitchSeverity.warning,
      );
    case SwitchState.unknown:
      return const SwitchStateText(
        'The switch reported a status this app does not know',
        SwitchSeverity.warning,
      );
  }
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The network switch's multicast (IGMP) status, with a "Check now" button.
/// Shows nothing when the SC-1 has no managed switch.
class SwitchStatusCard extends StatelessWidget {
  final SwitchStatus status;

  /// A check started from this card is running.
  final bool checking;

  /// Null hides the button.
  final VoidCallback? onCheckNow;

  const SwitchStatusCard({
    super.key,
    required this.status,
    this.checking = false,
    this.onCheckNow,
  });

  /// False for a unit with no managed switch: there is nothing to show.
  static bool shouldShow(SwitchStatus status) =>
      status.configured && status.state != SwitchState.notConfigured;

  @override
  Widget build(BuildContext context) {
    if (!shouldShow(status)) return const SizedBox.shrink();

    final text = describeSwitchState(status);
    final (color, icon) = switch (text.severity) {
      SwitchSeverity.good => (Colors.greenAccent, Icons.check_circle_rounded),
      SwitchSeverity.warning => (
        Colors.orangeAccent,
        Icons.warning_amber_rounded,
      ),
      SwitchSeverity.problem => (Colors.redAccent, Icons.error_rounded),
      SwitchSeverity.working => (Colors.white70, Icons.hourglass_top_rounded),
    };
    final busy = checking || status.state == SwitchState.pending;
    // "ok" needs no explanation; every other state shows the controller's.
    final message =
        status.state == SwitchState.ok ? null : (status.message ?? '').trim();
    final subtitle = [
      status.displayName,
      if (status.host != null) status.host!,
    ].join(' · ');
    final igmp = status.igmp;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              text.severity == SwitchSeverity.problem
                  ? Colors.redAccent
                  : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hub_outlined, color: Colors.lightBlueAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Network switch',
                      style: TextStyle(
                        color: AppTheme.accentWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              busy && text.severity == SwitchSeverity.working
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                  : Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text.headline,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (message != null && message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 6),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          if (igmp != null) ...[
            const SizedBox(height: 12),
            _row('IGMP snooping', _flag(igmp.snooping, igmp.vlanSnooping)),
            _row(
              'IGMP querier',
              [
                _flag(igmp.querier, igmp.vlanQuerier),
                if (igmp.querierRole != null) igmp.querierRole!,
              ].join(' · '),
            ),
            if (status.vlan != null) _row('VLAN', '${status.vlan}'),
          ],
          if (status.checkedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Last checked ${_clock(status.checkedAt!)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ),
          if (onCheckNow != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : onCheckNow,
              icon:
                  checking
                      ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(checking ? 'Checking...' : 'Check now'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            if (checking)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'This usually takes a few seconds, but can take a few '
                  'minutes.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // The switch reports a setting for the whole switch and for the VLAN the
  // boxes are on; both must be on for multicast to work.
  static String _flag(bool? overall, bool? onVlan) {
    if (overall == true && onVlan != false) return 'On';
    if (overall == false && onVlan != true) return 'Off';
    if (overall == null && onVlan == null) return '—';
    return 'Partly on';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
