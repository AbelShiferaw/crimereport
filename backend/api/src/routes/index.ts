import { Router } from 'express';
import reportRouter from './reports';
import commentRouter from './comments';

const router = Router();

router.get('/', (_req, res) => {
  res.json({
    name: 'CrimeReport API',
    version: '1.0.0',
  });
});

router.use('/reports', reportRouter);
router.use('/comments', commentRouter);

export default router;
