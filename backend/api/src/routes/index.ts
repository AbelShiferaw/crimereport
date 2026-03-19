import { Router } from 'express';
import reportRouter from './reports';
import commentRouter from './comments';
import notificationRouter from './notifications';

const router = Router();

router.get('/', (_req, res) => {
  res.json({
    name: 'CrimeReport API',
    version: '1.0.0',
  });
});

router.use('/reports', reportRouter);
router.use('/comments', commentRouter);
router.use('/notifications', notificationRouter);

export default router;
