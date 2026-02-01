import '../../core/constants/enums.dart';
import '../../features/feed/data/models/comment.dart';
import '../../features/feed/data/models/media.dart';
import '../../features/feed/data/models/report.dart';

/// Raw mock data for development and testing.
/// All locations are centered around San Francisco (37.7749, -122.4194).
class SampleData {
  SampleData._();

  /// Google's public test video URLs (MP4 format, works with video_player).
  static const _videoUrls = [
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
  ];

  static const _thumbnailUrls = [
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/SubaruOutbackOnStreetAndDirt.jpg',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg',
  ];

  static final now = DateTime.now();

  /// 10 mock crime reports with varied types and locations around SF.
  static final List<Report> reports = [
    // Report 1: Theft - Market Street
    Report(
      id: 'report_001',
      deviceId: 'device_abc123',
      type: ReportType.theft,
      description:
          'Car break-in on Market Street. Window smashed, laptop and backpack stolen from the back seat. Suspect fled on foot toward the BART station.',
      latitude: 37.7849,
      longitude: -122.4094,
      address: 'Market St & 5th St, San Francisco',
      media: [
        Media(
          id: 'media_001',
          reportId: 'report_001',
          type: MediaType.video,
          url: _videoUrls[0],
          thumbnailUrl: _thumbnailUrls[0],
          durationMs: 15000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
      ],
      upvotes: 45,
      commentCount: 12,
      createdAt: now.subtract(const Duration(hours: 2)),
      status: ReportStatus.verified,
    ),

    // Report 2: Assault - Tenderloin
    Report(
      id: 'report_002',
      deviceId: 'device_def456',
      type: ReportType.assault,
      description:
          'Physical altercation between two individuals near the corner. One person was knocked down. Bystanders intervened before it escalated further.',
      latitude: 37.7831,
      longitude: -122.4136,
      address: 'Turk St & Taylor St, San Francisco',
      media: [
        Media(
          id: 'media_002',
          reportId: 'report_002',
          type: MediaType.video,
          url: _videoUrls[1],
          thumbnailUrl: _thumbnailUrls[1],
          durationMs: 22000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(hours: 4)),
        ),
      ],
      upvotes: 89,
      commentCount: 34,
      createdAt: now.subtract(const Duration(hours: 4)),
      status: ReportStatus.verified,
    ),

    // Report 3: Vandalism - Mission District
    Report(
      id: 'report_003',
      deviceId: 'device_ghi789',
      type: ReportType.vandalism,
      description:
          'Someone spray-painted graffiti on the side of the building overnight. Large tags covering most of the wall. Happened between 2-5 AM.',
      latitude: 37.7599,
      longitude: -122.4148,
      address: '24th St & Mission St, San Francisco',
      media: [
        Media(
          id: 'media_003',
          reportId: 'report_003',
          type: MediaType.video,
          url: _videoUrls[2],
          thumbnailUrl: _thumbnailUrls[2],
          durationMs: 18000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(hours: 8)),
        ),
      ],
      upvotes: 23,
      commentCount: 7,
      createdAt: now.subtract(const Duration(hours: 8)),
      status: ReportStatus.pending,
    ),

    // Report 4: Suspicious Activity - Financial District
    Report(
      id: 'report_004',
      deviceId: 'device_jkl012',
      type: ReportType.suspicious,
      description:
          'Individual repeatedly checking car doors in the parking garage. Wearing dark hoodie and carrying a backpack. Left when security approached.',
      latitude: 37.7946,
      longitude: -122.3999,
      address: 'California St & Montgomery St, San Francisco',
      media: [
        Media(
          id: 'media_004',
          reportId: 'report_004',
          type: MediaType.video,
          url: _videoUrls[3],
          thumbnailUrl: _thumbnailUrls[3],
          durationMs: 30000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ],
      upvotes: 67,
      commentCount: 19,
      createdAt: now.subtract(const Duration(hours: 1)),
      status: ReportStatus.verified,
    ),

    // Report 5: Drug Activity - Civic Center
    Report(
      id: 'report_005',
      deviceId: 'device_mno345',
      type: ReportType.drugActivity,
      description:
          'Open drug use near the library entrance. Multiple individuals smoking from glass pipes. This has been an ongoing issue in the area.',
      latitude: 37.7785,
      longitude: -122.4156,
      address: 'Grove St & Larkin St, San Francisco',
      media: [
        Media(
          id: 'media_005',
          reportId: 'report_005',
          type: MediaType.video,
          url: _videoUrls[4],
          thumbnailUrl: _thumbnailUrls[4],
          durationMs: 25000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(hours: 6)),
        ),
      ],
      upvotes: 112,
      commentCount: 45,
      createdAt: now.subtract(const Duration(hours: 6)),
      status: ReportStatus.verified,
    ),

    // Report 6: Disturbance - North Beach
    Report(
      id: 'report_006',
      deviceId: 'device_pqr678',
      type: ReportType.disturbance,
      description:
          'Loud argument at the bar spilled onto the street. Yelling and shoving between two groups. Bouncer trying to separate them.',
      latitude: 37.7979,
      longitude: -122.4074,
      address: 'Broadway & Columbus Ave, San Francisco',
      media: [
        Media(
          id: 'media_006',
          reportId: 'report_006',
          type: MediaType.video,
          url: _videoUrls[5],
          thumbnailUrl: _thumbnailUrls[5],
          durationMs: 45000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(hours: 12)),
        ),
      ],
      upvotes: 34,
      commentCount: 15,
      createdAt: now.subtract(const Duration(hours: 12)),
      status: ReportStatus.pending,
    ),

    // Report 7: Theft - Union Square
    Report(
      id: 'report_007',
      deviceId: 'device_stu901',
      type: ReportType.theft,
      description:
          'Shoplifter grabbed merchandise and ran out of the store. Security chased but lost them in the crowd. Suspect wearing red jacket.',
      latitude: 37.7879,
      longitude: -122.4075,
      address: 'Powell St & Geary St, San Francisco',
      media: [
        Media(
          id: 'media_007',
          reportId: 'report_007',
          type: MediaType.video,
          url: _videoUrls[6],
          thumbnailUrl: _thumbnailUrls[6],
          durationMs: 12000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(minutes: 45)),
        ),
      ],
      upvotes: 78,
      commentCount: 23,
      createdAt: now.subtract(const Duration(minutes: 45)),
      status: ReportStatus.verified,
    ),

    // Report 8: Other - SoMa
    Report(
      id: 'report_008',
      deviceId: 'device_vwx234',
      type: ReportType.other,
      description:
          'Homeless encampment blocking the sidewalk. Tents set up across the entire walkway. Pedestrians forced to walk in the street.',
      latitude: 37.7749,
      longitude: -122.4194,
      address: '6th St & Howard St, San Francisco',
      media: [
        Media(
          id: 'media_008',
          reportId: 'report_008',
          type: MediaType.video,
          url: _videoUrls[7],
          thumbnailUrl: _thumbnailUrls[7],
          durationMs: 20000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ],
      upvotes: 156,
      commentCount: 67,
      createdAt: now.subtract(const Duration(days: 1)),
      status: ReportStatus.verified,
    ),

    // Report 9: Assault - Haight-Ashbury
    Report(
      id: 'report_009',
      deviceId: 'device_yza567',
      type: ReportType.assault,
      description:
          'Man pushed a woman to the ground and grabbed her purse. She screamed and he dropped it and ran. Suspect had tattoos on both arms.',
      latitude: 37.7692,
      longitude: -122.4481,
      address: 'Haight St & Ashbury St, San Francisco',
      media: [
        Media(
          id: 'media_009',
          reportId: 'report_009',
          type: MediaType.video,
          url: _videoUrls[8],
          thumbnailUrl: _thumbnailUrls[8],
          durationMs: 35000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
      ],
      upvotes: 201,
      commentCount: 89,
      createdAt: now.subtract(const Duration(hours: 3)),
      status: ReportStatus.verified,
    ),

    // Report 10: Vandalism - Castro
    Report(
      id: 'report_010',
      deviceId: 'device_bcd890',
      type: ReportType.vandalism,
      description:
          'Car windows smashed on multiple vehicles along the block. At least 5 cars affected. Glass everywhere on the sidewalk.',
      latitude: 37.7609,
      longitude: -122.4350,
      address: 'Castro St & 18th St, San Francisco',
      media: [
        Media(
          id: 'media_010',
          reportId: 'report_010',
          type: MediaType.video,
          url: _videoUrls[9],
          thumbnailUrl: _thumbnailUrls[9],
          durationMs: 28000,
          width: 1920,
          height: 1080,
          createdAt: now.subtract(const Duration(hours: 5)),
        ),
      ],
      upvotes: 134,
      commentCount: 41,
      createdAt: now.subtract(const Duration(hours: 5)),
      status: ReportStatus.verified,
    ),
  ];

  /// Mock comments for the reports (3-5 per report).
  static final List<Comment> comments = [
    // Comments for Report 1 (Theft - Market Street)
    Comment(
      id: 'comment_001',
      reportId: 'report_001',
      deviceId: 'device_xyz789',
      content:
          'I saw this happen around 3pm. The guy ran toward the BART station.',
      upvotes: 8,
      createdAt: now.subtract(const Duration(hours: 1, minutes: 45)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_002',
      reportId: 'report_001',
      deviceId: 'device_abc123',
      content: 'This is my car. Already filed a police report. So frustrating.',
      upvotes: 23,
      createdAt: now.subtract(const Duration(hours: 1, minutes: 30)),
      isReporter: true,
    ),
    Comment(
      id: 'comment_003',
      reportId: 'report_001',
      deviceId: 'device_qrs456',
      content: 'Third break-in this week on this block. When will it stop?',
      upvotes: 15,
      createdAt: now.subtract(const Duration(hours: 1)),
      isReporter: false,
    ),

    // Comments for Report 2 (Assault - Tenderloin)
    Comment(
      id: 'comment_004',
      reportId: 'report_002',
      deviceId: 'device_lmn123',
      content: 'This area is getting worse. I avoid walking here after dark.',
      upvotes: 34,
      createdAt: now.subtract(const Duration(hours: 3, minutes: 30)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_005',
      reportId: 'report_002',
      deviceId: 'device_opq789',
      content: 'Did anyone call 911? Is the person who got knocked down okay?',
      upvotes: 12,
      createdAt: now.subtract(const Duration(hours: 3)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_006',
      reportId: 'report_002',
      deviceId: 'device_def456',
      content:
          'The person was helped up by bystanders. Seemed shaken but walking.',
      upvotes: 28,
      createdAt: now.subtract(const Duration(hours: 2, minutes: 45)),
      isReporter: true,
    ),
    Comment(
      id: 'comment_007',
      reportId: 'report_002',
      deviceId: 'device_rst012',
      content: 'I work nearby. This happens almost every week at this corner.',
      upvotes: 45,
      createdAt: now.subtract(const Duration(hours: 2)),
      isReporter: false,
    ),

    // Comments for Report 3 (Vandalism - Mission)
    Comment(
      id: 'comment_008',
      reportId: 'report_003',
      deviceId: 'device_uvw345',
      content: 'That mural was beautiful. So sad to see it covered in tags.',
      upvotes: 11,
      createdAt: now.subtract(const Duration(hours: 7)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_009',
      reportId: 'report_003',
      deviceId: 'device_xyz678',
      content: 'Security cameras on the building next door might have footage.',
      upvotes: 19,
      createdAt: now.subtract(const Duration(hours: 6)),
      isReporter: false,
    ),

    // Comments for Report 4 (Suspicious - Financial District)
    Comment(
      id: 'comment_010',
      reportId: 'report_004',
      deviceId: 'device_abc901',
      content: 'Good catch. These parking garages are targeted frequently.',
      upvotes: 22,
      createdAt: now.subtract(const Duration(minutes: 50)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_011',
      reportId: 'report_004',
      deviceId: 'device_jkl012',
      content:
          'Security said they\'ve seen the same person before. They\'re increasing patrols.',
      upvotes: 31,
      createdAt: now.subtract(const Duration(minutes: 40)),
      isReporter: true,
    ),
    Comment(
      id: 'comment_012',
      reportId: 'report_004',
      deviceId: 'device_def234',
      content: 'Always lock your doors and don\'t leave anything visible!',
      upvotes: 8,
      createdAt: now.subtract(const Duration(minutes: 30)),
      isReporter: false,
    ),

    // Comments for Report 5 (Drug Activity - Civic Center)
    Comment(
      id: 'comment_013',
      reportId: 'report_005',
      deviceId: 'device_ghi567',
      content:
          'I take my kids to this library. It\'s so sad they have to see this.',
      upvotes: 67,
      createdAt: now.subtract(const Duration(hours: 5, minutes: 30)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_014',
      reportId: 'report_005',
      deviceId: 'device_jkl890',
      content: 'The city needs to provide more resources for these people.',
      upvotes: 45,
      createdAt: now.subtract(const Duration(hours: 5)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_015',
      reportId: 'report_005',
      deviceId: 'device_mno123',
      content: 'Reported this same area last month. Nothing changes.',
      upvotes: 89,
      createdAt: now.subtract(const Duration(hours: 4, minutes: 30)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_016',
      reportId: 'report_005',
      deviceId: 'device_mno345',
      content:
          'I walk by here every day. It\'s gotten worse over the past year.',
      upvotes: 34,
      createdAt: now.subtract(const Duration(hours: 4)),
      isReporter: true,
    ),

    // Comments for Report 6 (Disturbance - North Beach)
    Comment(
      id: 'comment_017',
      reportId: 'report_006',
      deviceId: 'device_pqr456',
      content: 'Classic Saturday night on Broadway. Not surprised.',
      upvotes: 12,
      createdAt: now.subtract(const Duration(hours: 11)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_018',
      reportId: 'report_006',
      deviceId: 'device_stu789',
      content: 'The bouncers here do a good job usually. Must have escalated fast.',
      upvotes: 7,
      createdAt: now.subtract(const Duration(hours: 10)),
      isReporter: false,
    ),

    // Comments for Report 7 (Theft - Union Square)
    Comment(
      id: 'comment_019',
      reportId: 'report_007',
      deviceId: 'device_vwx012',
      content: 'I was in the store when this happened! Everyone was shocked.',
      upvotes: 34,
      createdAt: now.subtract(const Duration(minutes: 35)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_020',
      reportId: 'report_007',
      deviceId: 'device_yza345',
      content: 'Retail theft is out of control downtown. Stores are closing.',
      upvotes: 56,
      createdAt: now.subtract(const Duration(minutes: 30)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_021',
      reportId: 'report_007',
      deviceId: 'device_stu901',
      content: 'Security caught up with them a block away. Police were called.',
      upvotes: 23,
      createdAt: now.subtract(const Duration(minutes: 20)),
      isReporter: true,
    ),

    // Comments for Report 8 (Other - SoMa)
    Comment(
      id: 'comment_022',
      reportId: 'report_008',
      deviceId: 'device_bcd678',
      content:
          'This has been here for weeks. Called 311 multiple times, no response.',
      upvotes: 78,
      createdAt: now.subtract(const Duration(hours: 20)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_023',
      reportId: 'report_008',
      deviceId: 'device_efg901',
      content: 'The people living here need help, not just displacement.',
      upvotes: 45,
      createdAt: now.subtract(const Duration(hours: 18)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_024',
      reportId: 'report_008',
      deviceId: 'device_hij234',
      content: 'Had to push my stroller into traffic to get around. Dangerous.',
      upvotes: 67,
      createdAt: now.subtract(const Duration(hours: 16)),
      isReporter: false,
    ),

    // Comments for Report 9 (Assault - Haight)
    Comment(
      id: 'comment_025',
      reportId: 'report_009',
      deviceId: 'device_klm567',
      content: 'Oh my god, is she okay? Did anyone help her?',
      upvotes: 45,
      createdAt: now.subtract(const Duration(hours: 2, minutes: 45)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_026',
      reportId: 'report_009',
      deviceId: 'device_yza567',
      content:
          'A shop owner came out and helped her. She was crying but not hurt badly.',
      upvotes: 89,
      createdAt: now.subtract(const Duration(hours: 2, minutes: 30)),
      isReporter: true,
    ),
    Comment(
      id: 'comment_027',
      reportId: 'report_009',
      deviceId: 'device_nop890',
      content:
          'I think I saw the same guy earlier acting erratically near the park.',
      upvotes: 34,
      createdAt: now.subtract(const Duration(hours: 2)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_028',
      reportId: 'report_009',
      deviceId: 'device_qrs123',
      content: 'Tattoos on both arms - important detail for identification.',
      upvotes: 56,
      createdAt: now.subtract(const Duration(hours: 1, minutes: 30)),
      isReporter: false,
    ),

    // Comments for Report 10 (Vandalism - Castro)
    Comment(
      id: 'comment_029',
      reportId: 'report_010',
      deviceId: 'device_tuv456',
      content: 'My car is one of them. Window replacement is \$300+.',
      upvotes: 34,
      createdAt: now.subtract(const Duration(hours: 4, minutes: 30)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_030',
      reportId: 'report_010',
      deviceId: 'device_wxy789',
      content:
          'Check for security cameras at the businesses. Might have caught something.',
      upvotes: 23,
      createdAt: now.subtract(const Duration(hours: 4)),
      isReporter: false,
    ),
    Comment(
      id: 'comment_031',
      reportId: 'report_010',
      deviceId: 'device_bcd890',
      content:
          'Happened sometime between 2-4 AM. No witnesses that I could find.',
      upvotes: 12,
      createdAt: now.subtract(const Duration(hours: 3, minutes: 30)),
      isReporter: true,
    ),
  ];
}
