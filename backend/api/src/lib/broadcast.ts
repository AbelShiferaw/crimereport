import { getIO, overlappingRooms } from './socket';
import { logger } from './logger';

export function broadcastNewReport(report: {
  id: string;
  type: string;
  lat: number;
  lng: number;
  description: string | null;
  upvotes: number;
  comment_count: number;
  created_at: Date;
}) {
  try {
    const io = getIO();
    const rooms = overlappingRooms(report.lat, report.lng);
    const payload = {
      id: report.id,
      type: report.type,
      lat: report.lat,
      lng: report.lng,
      description: report.description,
      upvotes: report.upvotes,
      comment_count: report.comment_count,
      created_at: report.created_at,
    };
    for (const room of rooms) {
      io.to(room).emit('report:new', payload);
    }
    logger.debug({ reportId: report.id, rooms: rooms.length }, 'broadcast report:new');
  } catch (err) {
    logger.error({ err }, 'broadcast report:new failed');
  }
}

export function broadcastNewComment(comment: {
  id: string;
  report_id: string;
  device_id: string;
  content: string;
  created_at: Date;
}) {
  try {
    const io = getIO();
    io.to(`report:${comment.report_id}`).emit('comment:new', {
      id: comment.id,
      report_id: comment.report_id,
      content: comment.content,
      created_at: comment.created_at,
    });
    logger.debug({ commentId: comment.id, reportId: comment.report_id }, 'broadcast comment:new');
  } catch (err) {
    logger.error({ err }, 'broadcast comment:new failed');
  }
}

export function broadcastUpvote(reportId: string, upvoted: boolean) {
  try {
    const io = getIO();
    io.to(`report:${reportId}`).emit('report:upvote', {
      report_id: reportId,
      upvoted,
    });
    logger.debug({ reportId, upvoted }, 'broadcast report:upvote');
  } catch (err) {
    logger.error({ err }, 'broadcast report:upvote failed');
  }
}
