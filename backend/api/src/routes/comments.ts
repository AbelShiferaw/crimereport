import { Router, Request, Response } from 'express';
import { validate } from '../middleware/validate';
import { writeLimiter } from '../middleware/rate-limit';
import { flagCommentSchema } from '../validators/comment';
import { HttpError } from '../lib/errors';
import * as commentModel from '../models/comment';
import * as commentFlagModel from '../models/comment-flag';

const router = Router();

router.post('/:id/flag', writeLimiter, validate(flagCommentSchema), async (req: Request, res: Response) => {
  const { id } = req.params;
  const { device_id } = req.body;

  const comment = await commentModel.findById(id);
  if (!comment) {
    throw HttpError.notFound('Comment not found');
  }

  const flagged = await commentFlagModel.flag(id, device_id);

  res.json({ flagged });
});

export default router;
