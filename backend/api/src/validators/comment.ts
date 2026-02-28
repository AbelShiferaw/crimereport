import { z } from 'zod';

export const createCommentSchema = z.object({
  device_id: z.string().min(1).max(64),
  content: z.string().trim().min(1).max(1000),
});

export const flagCommentSchema = z.object({
  device_id: z.string().min(1).max(64),
});

export const commentListQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

export type CreateCommentBody = z.infer<typeof createCommentSchema>;
export type FlagCommentBody = z.infer<typeof flagCommentSchema>;
export type CommentListQuery = z.infer<typeof commentListQuerySchema>;
