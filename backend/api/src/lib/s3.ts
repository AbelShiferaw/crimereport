import {
  S3Client,
  PutObjectCommand,
  HeadObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { config } from '../config';

const PRESIGNED_URL_EXPIRES_IN = 15 * 60; // 15 minutes

const s3 = new S3Client({ region: config.aws.region });

export async function generateUploadUrl(
  key: string,
  contentType: string,
): Promise<{ url: string; expiresIn: number }> {
  const command = new PutObjectCommand({
    Bucket: config.aws.s3UploadsBucket,
    Key: key,
    ContentType: contentType,
  });

  const url = await getSignedUrl(s3, command, { expiresIn: PRESIGNED_URL_EXPIRES_IN });
  return { url, expiresIn: PRESIGNED_URL_EXPIRES_IN };
}

export async function objectExists(bucket: string, key: string): Promise<boolean> {
  try {
    await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch (err: any) {
    if (err.name === 'NotFound' || err.$metadata?.httpStatusCode === 404) {
      return false;
    }
    throw err;
  }
}

export function buildCdnUrl(key: string): string {
  const domain = config.aws.cdnDomain;
  if (!domain) return '';
  return `https://${domain}/${key}`;
}

export function buildMediaKey(
  fileType: 'image' | 'video',
  reportId: string,
  fileId: string,
  ext: string,
): string {
  const prefix = fileType === 'image' ? 'images' : 'videos';
  return `${prefix}/${reportId}/${fileId}.${ext}`;
}
