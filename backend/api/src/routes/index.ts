import { Router } from 'express';
import reportRouter from './reports';

const router = Router();

router.get('/', (_req, res) => {
  res.json({
    name: 'CrimeReport API',
    version: '1.0.0',
  });
});

router.use('/reports', reportRouter);

export default router;
