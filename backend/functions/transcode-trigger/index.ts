import {
  MediaConvertClient,
  CreateJobCommand,
  DescribeEndpointsCommand,
} from '@aws-sdk/client-mediaconvert';

interface TranscodeInput {
  bucket: string;
  key: string;
}

interface TranscodeOutput {
  jobId: string;
  outputPrefix: string;
}

const MEDIACONVERT_ROLE = process.env.MEDIACONVERT_ROLE_ARN!;
const OUTPUT_BUCKET = process.env.OUTPUT_BUCKET!;

let cachedEndpoint: string | undefined;

async function getEndpoint(): Promise<string> {
  if (cachedEndpoint) return cachedEndpoint;

  const client = new MediaConvertClient({});
  const { Endpoints } = await client.send(
    new DescribeEndpointsCommand({ MaxResults: 1 }),
  );

  cachedEndpoint = Endpoints?.[0]?.Url;
  if (!cachedEndpoint) throw new Error('No MediaConvert endpoint found');
  return cachedEndpoint;
}

function buildJobSettings(inputUri: string, outputPrefix: string) {
  return {
    Inputs: [
      {
        FileInput: inputUri,
        AudioSelectors: {
          'Audio Selector 1': { DefaultSelection: 'DEFAULT' as const },
        },
        VideoSelector: {},
        TimecodeSource: 'ZEROBASED' as const,
      },
    ],
    OutputGroups: [
      {
        Name: 'MP4 Output',
        OutputGroupSettings: {
          Type: 'FILE_GROUP_SETTINGS' as const,
          FileGroupSettings: {
            Destination: `s3://${OUTPUT_BUCKET}/${outputPrefix}/`,
          },
        },
        Outputs: [
          {
            NameModifier: '_720p',
            VideoDescription: {
              Width: 1280,
              Height: 720,
              CodecSettings: {
                Codec: 'H_264' as const,
                H264Settings: {
                  RateControlMode: 'QVBR' as const,
                  QvbrSettings: { QvbrQualityLevel: 7 },
                  MaxBitrate: 5000000,
                },
              },
            },
            AudioDescriptions: [
              {
                CodecSettings: {
                  Codec: 'AAC' as const,
                  AacSettings: {
                    Bitrate: 128000,
                    CodingMode: 'CODING_MODE_2_0' as const,
                    SampleRate: 48000,
                  },
                },
              },
            ],
            ContainerSettings: {
              Container: 'MP4' as const,
            },
          },
        ],
      },
      {
        Name: 'Thumbnail Output',
        OutputGroupSettings: {
          Type: 'FILE_GROUP_SETTINGS' as const,
          FileGroupSettings: {
            Destination: `s3://${OUTPUT_BUCKET}/${outputPrefix}/`,
          },
        },
        Outputs: [
          {
            NameModifier: '_thumb',
            VideoDescription: {
              Width: 480,
              Height: 480,
              CodecSettings: {
                Codec: 'FRAME_CAPTURE' as const,
                FrameCaptureSettings: {
                  FramerateNumerator: 1,
                  FramerateDenominator: 1,
                  MaxCaptures: 1,
                  Quality: 80,
                },
              },
            },
            ContainerSettings: {
              Container: 'RAW' as const,
            },
          },
        ],
      },
      {
        Name: 'GIF Preview Output',
        OutputGroupSettings: {
          Type: 'FILE_GROUP_SETTINGS' as const,
          FileGroupSettings: {
            Destination: `s3://${OUTPUT_BUCKET}/${outputPrefix}/`,
          },
        },
        Outputs: [
          {
            NameModifier: '_preview',
            VideoDescription: {
              Width: 320,
              Height: 320,
              CodecSettings: {
                Codec: 'FRAME_CAPTURE' as const,
                FrameCaptureSettings: {
                  FramerateNumerator: 3,
                  FramerateDenominator: 1,
                  MaxCaptures: 9,
                  Quality: 60,
                },
              },
            },
            ContainerSettings: {
              Container: 'RAW' as const,
            },
          },
        ],
      },
    ],
  };
}

export const handler = async (event: TranscodeInput): Promise<TranscodeOutput> => {
  const { bucket, key } = event;
  const inputUri = `s3://${bucket}/${key}`;

  const baseName = key.split('/').pop()?.replace(/\.[^.]+$/, '') ?? 'output';
  const outputPrefix = `videos/${baseName}`;

  console.log(`Processing: ${inputUri} -> ${outputPrefix}`);

  const endpoint = await getEndpoint();
  const client = new MediaConvertClient({ endpoint });
  const jobSettings = buildJobSettings(inputUri, outputPrefix);

  const result = await client.send(
    new CreateJobCommand({
      Role: MEDIACONVERT_ROLE,
      Settings: jobSettings,
      StatusUpdateInterval: 'SECONDS_60',
      Tags: {
        Project: 'CrimeReport',
        Source: key,
      },
    }),
  );

  const jobId = result.Job?.Id ?? 'unknown';
  console.log(`MediaConvert job created: ${jobId} for ${key}`);

  return { jobId, outputPrefix };
};
