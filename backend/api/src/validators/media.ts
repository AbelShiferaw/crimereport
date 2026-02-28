import { z } from 'zod';

const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
const ALLOWED_VIDEO_TYPES = ['video/mp4', 'video/quicktime', 'video/webm'] as const;
const ALLOWED_CONTENT_TYPES = [...ALLOWED_IMAGE_TYPES, ...ALLOWED_VIDEO_TYPES] as const;

export const uploadRequestSchema = z.object({
  device_id: z.string().min(1).max(64),
  file_type: z.enum(['image', 'video']),
  content_type: z.enum(ALLOWED_CONTENT_TYPES),
}).refine(
  (data) => {
    if (data.file_type === 'image') {
      return (ALLOWED_IMAGE_TYPES as readonly string[]).includes(data.content_type);
    }
    return (ALLOWED_VIDEO_TYPES as readonly string[]).includes(data.content_type);
  },
  { message: 'content_type does not match file_type', path: ['content_type'] },
);

export const uploadCompleteSchema = z.object({
  device_id: z.string().min(1).max(64),
  media_key: z.string().min(1).max(500),
});

export type UploadRequestBody = z.infer<typeof uploadRequestSchema>;
export type UploadCompleteBody = z.infer<typeof uploadCompleteSchema>;
