import 'package:flutter/material.dart';
import '../models/audio_recording_model.dart';
import '../models/hive_data.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';

class HiveRecordingsView extends StatefulWidget {
  final HiveData hive;

  const HiveRecordingsView({super.key, required this.hive});

  @override
  State<HiveRecordingsView> createState() => _HiveRecordingsViewState();
}

class _HiveRecordingsViewState extends State<HiveRecordingsView> {
  @override
  void initState() {
    super.initState();
    // Pre-fetch live audio clips for this device
    AudioService().fetchRecordingsForDevice(widget.hive.deviceId);
  }

  String _getClipDisplayTimestamp(int index, AudioRecordingModel clip) {
    int epoch = clip.createdAt;
    if (epoch > 0 && epoch < 1700000000000 && epoch > 1700000000) {
      epoch = epoch * 1000;
    }

    if (epoch > 1700000000000) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final diffMs = now - epoch;
      if (diffMs >= 0) {
        final diffMin = diffMs ~/ 60000;
        if (diffMin < 1) {
          return 'Just now';
        } else if (diffMin < 60) {
          return '$diffMin min${diffMin > 1 ? "s" : ""} ago';
        } else {
          final hours = diffMin ~/ 60;
          if (hours < 24) {
            return '$hours hr${hours > 1 ? "s" : ""} ago';
          } else {
            final days = hours ~/ 24;
            return '$days day${days > 1 ? "s" : ""} ago';
          }
        }
      }
    }
    return 'Recorded earlier';
  }

  Widget _buildAcousticSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: AppStyles.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFD54F), width: 1.2),
                ),
                child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFFB78103), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Acoustic Telemetry Stream',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Live harmonic: ${widget.hive.acoustic} • ${widget.hive.acousticStatus}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Frequency Band Indicator Chips
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: const Column(
                    children: [
                      Text('90–260 Hz', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                      Text('Worker Hum', style: TextStyle(fontSize: 9, color: Color(0xFF2E7D32))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFFD54F)),
                  ),
                  child: const Column(
                    children: [
                      Text('260–300 Hz', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB78103))),
                      Text('Queen Piping', style: TextStyle(fontSize: 9, color: Color(0xFF795548))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: const Column(
                    children: [
                      Text('≥ 300 Hz', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB71C1C))),
                      Text('Queenless Roar', style: TextStyle(fontSize: 9, color: Color(0xFFC62828))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRecordingsCard() {
    return AnimatedBuilder(
      animation: AudioService(),
      builder: (context, _) {
        final audioService = AudioService();
        final recordings = audioService.getCachedRecordings(widget.hive.deviceId);
        final isPlaying = audioService.isPlaying;
        final activeId = audioService.activePlayingId;

        return Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.headphones_outlined, size: 20, color: Colors.black87),
                      SizedBox(width: 8),
                      Text(
                        'Recent Hive Buzz Recordings',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      audioService.fetchRecordingsForDevice(widget.hive.deviceId);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.refresh, size: 12, color: Colors.black54),
                          SizedBox(width: 4),
                          Text(
                            'Refresh',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Up to 5 recent 3.0-second acoustic audio clips captured on boot and cycle cooldown.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 14),

              if (recordings.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.mic_none_outlined, size: 36, color: Colors.black38),
                      const SizedBox(height: 8),
                      Text(
                        'Awaiting buzz recordings from ${widget.hive.name}...',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Recordings are captured in 3-second clips whenever the ESP32 node boots up or completes a cooldown cycle.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recordings.length,
                  separatorBuilder: (context, index) => const Divider(height: 16, color: Colors.black12),
                  itemBuilder: (context, index) {
                    final clip = recordings[index];
                    final isThisPlaying = isPlaying && activeId == clip.id;

                    Color badgeColor = AppColors.healthyGreen;
                    Color badgeBg = AppColors.queenPresentGreenBg;
                    if (clip.frequency == 0 || clip.condition.toLowerCase().contains('no buzz')) {
                      badgeColor = AppColors.queenAbsentRed;
                      badgeBg = AppColors.queenAbsentRedBg;
                    } else if (clip.frequency >= 300 || clip.condition.toLowerCase().contains('rejected')) {
                      badgeColor = AppColors.queenRejectedOrange;
                      badgeBg = AppColors.queenRejectedOrangeBg;
                    } else if (clip.condition.toLowerCase().contains('accepted')) {
                      badgeColor = AppColors.queenAcceptedBlue;
                      badgeBg = AppColors.queenAcceptedBlueBg;
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // Play/Pause button
                          GestureDetector(
                            onTap: () {
                              audioService.playRecording(clip);
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isThisPlaying ? Colors.black : const Color(0xFFFFCC00),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isThisPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                color: isThisPlaying ? Colors.white : Colors.black,
                                size: 26,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Metadata column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Text(
                                            'Clip #${index + 1}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.black,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: clip.isRestartEvent
                                                  ? const Color(0xFFFFF3E0)
                                                  : const Color(0xFFE3F2FD),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: clip.isRestartEvent
                                                    ? const Color(0xFFFFB74D)
                                                    : const Color(0xFF90CAF9),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  clip.isRestartEvent ? Icons.restart_alt : Icons.hourglass_bottom_rounded,
                                                  size: 10,
                                                  color: clip.isRestartEvent ? const Color(0xFFE65100) : const Color(0xFF1976D2),
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  clip.triggerLabel,
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: clip.isRestartEvent ? const Color(0xFFE65100) : const Color(0xFF1976D2),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badgeBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        clip.frequency > 0 ? '${clip.frequency} Hz' : '0 Hz',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: badgeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_filled, size: 12, color: Colors.black45),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Recorded at ${clip.formattedRecordedTime}${clip.formattedRecordedDate.isNotEmpty ? " • ${clip.formattedRecordedDate}" : ""} (${_getClipDisplayTimestamp(index, clip)})',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text(
                                      clip.condition,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: badgeColor,
                                      ),
                                    ),
                                    const Text(' • ', style: TextStyle(fontSize: 11, color: Colors.black38)),
                                    Text(
                                      '${clip.temperature.toStringAsFixed(1)}°C / ${clip.humidity.toStringAsFixed(0)}%',
                                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                                    ),
                                    const Spacer(),
                                    Text(
                                      isThisPlaying ? 'Playing...' : '3.0s',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isThisPlaying ? const Color(0xFFE65100) : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAcousticSummaryCard(),
        const SizedBox(height: 16),
        _buildRecentRecordingsCard(),
        const SizedBox(height: 24),
      ],
    );
  }
}
