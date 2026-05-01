export interface Coordinates {
  lat: number;
  lng: number;
}

export interface Report {
  id: string;
  device_id: string;
  type: string;
  description: string | null;
  location: Coordinates;
  address: string | null;
  status: string;
  upvotes: number;
  comment_count: number;
  created_at: Date;
  updated_at: Date;
}

export interface ReportRow {
  id: string;
  device_id: string;
  type: string;
  description: string | null;
  lat: number;
  lng: number;
  address: string | null;
  status: string;
  upvotes: number;
  comment_count: number;
  created_at: Date;
  updated_at: Date;
  distance_m?: number;
}

export interface CreateReportInput {
  device_id: string;
  type: string;
  description?: string;
  lat: number;
  lng: number;
  address?: string;
}

export type MediaFailureReason =
  | 'flagged_content'
  | 'processing_error'
  | 'unsupported_format';

export interface Media {
  id: string;
  report_id: string;
  type: 'video' | 'image';
  url: string;
  thumbnail_url: string | null;
  media_key: string | null;
  status: string;
  failure_reason: MediaFailureReason | null;
  duration_ms: number | null;
  width: number | null;
  height: number | null;
  created_at: Date;
}

export interface CreateMediaInput {
  report_id: string;
  type: 'video' | 'image';
  url: string;
  media_key?: string;
  thumbnail_url?: string;
  duration_ms?: number;
  width?: number;
  height?: number;
}

export interface Comment {
  id: string;
  report_id: string;
  device_id: string;
  content: string;
  upvotes: number;
  flag_count: number;
  created_at: Date;
}

export interface CommentFlag {
  comment_id: string;
  device_id: string;
  created_at: Date;
}

export interface CreateCommentInput {
  report_id: string;
  device_id: string;
  content: string;
}

export interface ReportUpvote {
  report_id: string;
  device_id: string;
  created_at: Date;
}

export interface DeviceActivity {
  device_id: string;
  report_count_today: number;
  last_report_at: Date | null;
  flagged: boolean;
  created_at: Date;
}

export interface PaginationOptions {
  limit: number;
  offset: number;
}

export interface PushSubscription {
  device_id: string;
  fcm_token: string;
  platform: 'ios' | 'android';
  endpoint_arn: string | null;
  lat: number;
  lng: number;
  radius: number;
  types: string[] | null;
  enabled: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface CreatePushSubscriptionInput {
  device_id: string;
  fcm_token: string;
  platform: 'ios' | 'android';
  lat: number;
  lng: number;
}

export interface UpdatePushPreferencesInput {
  enabled?: boolean;
  radius?: number;
  types?: string[];
}
